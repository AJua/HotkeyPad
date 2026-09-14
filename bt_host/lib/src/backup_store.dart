import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'backup_bundle.dart';
import 'custom_icon_store.dart';
import 'layout_store.dart';
import 'settings_store.dart';

/// Wraps the native Save/Open panels behind export and import.
///
/// Kept apart from [BackupStore] the same way [CustomIconStore] keeps its
/// own channel call apart from [CustomIconStore.cropToSquarePng] — so the
/// actual bundle logic in [BackupStore] and backup_bundle.dart needs
/// nothing from here to be exercised in a test.
abstract final class BackupFilePicker {
  // Reuses the icon channel's native side (AppIconChannel.swift), which
  // already hosts a picker, rather than standing up a second
  // MethodChannel just to add two more methods to it.
  static const _channel = MethodChannel('btlink/icons');

  /// The native picker is macOS-only, the same gap [CustomIconStore] and
  /// [AppLauncher] already report elsewhere.
  static bool get supported => !kIsWeb && Platform.isMacOS;

  /// Opens a native Save panel pre-filled with [suggestedName]. Returns the
  /// chosen path, or null if the user cancelled — cancelling is not an
  /// error, the same stance [CustomIconStore.pickAndProcess] takes.
  static Future<String?> pickSaveLocation(String suggestedName) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('pickSaveLocation', {
        'suggestedName': suggestedName,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens a native Open panel restricted to backup files. Returns the
  /// chosen path, or null if the user cancelled.
  static Future<String?> pickOpenFile() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('pickOpenFile');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// The result of reading a file the user picked as a backup: either a
/// ready-to-apply [bundle], or a [message] explaining why it could not be
/// used. Never both — [ok] just mirrors whichever one is set.
///
/// A small class rather than a record: unlike [CommandRunner]'s
/// `(ok, message)` pairs, a successful read also needs to carry the parsed
/// [BackupBundle] on to the confirmation step, not just a status string.
class BackupReadResult {
  const BackupReadResult.ok(this.bundle) : message = null;
  const BackupReadResult.failed(this.message) : bundle = null;

  final BackupBundle? bundle;
  final String? message;

  bool get ok => bundle != null;
}

/// Reads and writes the single-file backup bundle covering everything the
/// host persists — settings, layout, and the custom icons that layout uses
/// — so the whole setup can move to a new Mac, or come back after
/// `~/.config/BTLink` is lost, as one file rather than three stores plus a
/// folder of images.
abstract final class BackupStore {
  /// Gathers what's currently on disk into one encoded bundle. Only the
  /// icons [customIconIdsReferencedBy] the current layout are included, not
  /// everything under `custom_icons/`, which may hold icons orphaned by a
  /// since-edited button.
  static Future<Uint8List> exportCurrent() async {
    final appearance = await SettingsStore.load();
    final layout = await LayoutStore.load();
    final icons = <String, Uint8List>{};
    for (final id in customIconIdsReferencedBy(layout)) {
      final bytes = await CustomIconStore.read(id);
      if (bytes != null) icons[id] = bytes;
    }
    return encodeBackupBundle(
      BackupBundle(
        theme: appearance.theme,
        showLabels: appearance.showLabels,
        layout: layout,
        customIcons: icons,
      ),
    );
  }

  /// Writes the current configuration to a file the user picks via a native
  /// Save panel. Null means the user cancelled the picker — nothing worth
  /// telling them; otherwise the (ok, message) pair reports success or why
  /// it failed, the same shape [CommandRunner] already uses for a result
  /// worth showing.
  static Future<({bool ok, String message})?> exportToFile() async {
    if (!BackupFilePicker.supported) {
      return (ok: false, message: 'Export is only supported on macOS');
    }
    final path = await BackupFilePicker.pickSaveLocation(
      backupSuggestedFileName(DateTime.now()),
    );
    if (path == null) return null;
    try {
      await File(path).writeAsBytes(await exportCurrent(), flush: true);
      return (ok: true, message: 'Exported settings to ${path.split('/').last}');
    } on FileSystemException catch (error) {
      return (ok: false, message: 'Export failed: ${error.message}');
    }
  }

  /// Opens a file the user picks via a native Open panel and parses it as a
  /// backup, without changing anything on disk yet — so the caller can
  /// confirm the destructive overwrite only once there is a real bundle to
  /// apply. Null means the user cancelled the picker.
  static Future<BackupReadResult?> pickAndReadFile() async {
    if (!BackupFilePicker.supported) {
      return const BackupReadResult.failed(
        'Import is only supported on macOS',
      );
    }
    final path = await BackupFilePicker.pickOpenFile();
    if (path == null) return null;
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (error) {
      return BackupReadResult.failed('Could not read that file: ${error.message}');
    }
    final bundle = decodeBackupBundle(bytes);
    if (bundle == null) {
      return const BackupReadResult.failed(
        'That file is not a valid BTLink backup',
      );
    }
    return BackupReadResult.ok(bundle);
  }

  /// Overwrites settings, layout, and custom icons with what's in [bundle].
  ///
  /// Icon files are written under the exact ids the bundle carries — the
  /// same ids [bundle]'s own layout points at — so nothing needs
  /// renumbering. An existing custom icon file the new layout no longer
  /// references is left in place rather than swept: the same as editing a
  /// button by hand, an orphan just outlives the button that used it.
  static Future<void> apply(BackupBundle bundle) async {
    await SettingsStore.save(
      theme: bundle.theme,
      showLabels: bundle.showLabels,
    );
    for (final entry in bundle.customIcons.entries) {
      await CustomIconStore.writeAtId(entry.key, entry.value);
    }
    await LayoutStore.save(bundle.layout);
  }
}
