import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

import 'config_dir.dart';
import 'emoji_icon.dart';

/// Persists the deck layout on the host.
///
/// The host owns the layout, so this is the only copy that matters; the
/// client caches what it is sent but never edits it.
abstract final class LayoutStore {
  /// Shown before anything has ever been saved, so a first install is not a
  /// blank grid — a stock deck to start from, picked per platform since an
  /// app that does not exist there would just be a dead button.
  static DeckLayout get _defaultLayout =>
      !kIsWeb && Platform.isWindows ? _defaultLayoutWindows : _defaultLayoutMac;

  // Authored landscape (how it reads naturally: rows of related apps) and
  // then turned upright — see DeckLayout.transposed — since the shipped
  // default is shown on a phone, which is portrait.
  static final _defaultLayoutMac =
      DeckLayout.fromJson({
        'columns': 6,
        'rows': 3,
        'pages': 2,
        'slots': [
          '{"t":"widget","k":"digital_clock","rs":3,"cs":2}',
          null,
          'app:Finder',
          'app:Mail',
          'app:Contacts',
          'app:Xcode',
          null,
          null,
          'app:App Store',
          'app:Calendar',
          'app:Messages',
          'app:Terminal',
          null,
          null,
          'app:Safari',
          'app:Maps',
          'app:FaceTime',
          'app:Activity Monitor',
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
        ],
      })!.transposed();

  static final _defaultLayoutWindows =
      DeckLayout.fromJson({
        'columns': 3,
        'rows': 2,
        'pages': 1,
        'slots': [
          'app:Windows PowerShell',
          'app:OneNote',
          'app:Microsoft Edge',
          'app:Control Panel',
          'app:Event Viewer',
          'app:System Information',
        ],
      })!;

  /// Used when there is no filesystem — the web build, which exists only to
  /// develop the editor UI.
  static DeckLayout? _inMemory;

  static File? get _file {
    final dir = ConfigDir.path;
    if (dir == null) return null;
    return File('$dir/layout.json');
  }

  /// The one [migrateEmojiIcons] run in flight, shared by every [load]
  /// that overlaps it — [load] runs on every button press, and two
  /// concurrent migrations would each mint their own copy of every image.
  static Future<DeckLayout>? _migrating;

  /// Loads the layout, first turning any legacy emoji icons into custom
  /// images (see [migrateEmojiIcons]) and saving the result, so nothing
  /// past this point — the editor or the client — ever sees an emoji.
  /// Checked on every load rather than once at startup, since restoring an
  /// old backup can bring emoji back at any time.
  static Future<DeckLayout> load() async {
    final layout = await _loadRaw();
    if (!hasEmojiIcons(layout)) return layout;
    return _migrating ??= () async {
      try {
        final migrated = await migrateEmojiIcons(layout);
        await save(migrated);
        return migrated;
      } finally {
        _migrating = null;
      }
    }();
  }

  static Future<DeckLayout> _loadRaw() async {
    final file = _file;
    if (file == null) return _inMemory ??= _defaultLayout;
    try {
      if (!file.existsSync()) return _defaultLayout;
      final decoded = jsonDecode(await file.readAsString());
      return DeckLayout.fromJson(decoded) ?? DeckLayout.empty();
    } catch (_) {
      // A corrupt layout should not stop the service from starting.
      return DeckLayout.empty();
    }
  }

  static Future<void> save(DeckLayout layout) async {
    final file = _file;
    if (file == null) {
      _inMemory = layout;
      return;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(layout.toJson()), flush: true);
    } on FileSystemException {
      // Losing the layout on disk is better than taking the app down.
    }
  }
}
