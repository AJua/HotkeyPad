import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Stores app icons so they are fetched over BLE once, not on every launch.
/// A 64px PNG is ~5KB and takes a dozen notifications to transfer.
///
/// Icons are files rather than base64 in shared_preferences: preferences are
/// loaded into memory wholesale at startup, so a deck of thirty icons would
/// add a few hundred KB to every launch of the app whether the deck is opened
/// or not. Files are read only when a button needs one.
///
/// Icons are namespaced by host: two hosts can have different apps, and
/// different icons for the same app name.
abstract final class IconCache {
  static Future<Directory?> _directory(String hostId) async {
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/icons/${_safe(hostId)}');
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      return directory;
    } catch (_) {
      // No cache directory means a slower deck, not a broken one.
      return null;
    }
  }

  /// App names contain spaces, slashes and non-ASCII characters, none of
  /// which belong in a filename. Hex of the UTF-8 bytes is reversible and
  /// short enough for the names involved.
  static String _safe(String value) => utf8
      .encode(value)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  /// Bumped whenever the host changes how it renders an icon, so the phone
  /// refetches instead of showing a stale copy forever — the cache is keyed
  /// by app name alone, with no way to tell the old bytes are outdated.
  /// v2: the host trims macOS icons' transparent margin (see the host's
  /// IconTrim), so they fill the button.
  /// A change of [HotkeyPad.iconSize] alone needs no bump — it is part of
  /// the key already.
  static const _renderVersion = 2;

  static String _fileName(String appName) =>
      '${_safe(appName)}@${HotkeyPad.iconSize}v$_renderVersion';

  /// Names earlier builds used for [appName] — older render versions and
  /// the old 128px icon size — discarded on a miss the same way
  /// [_discardLegacyEntry] drops the older prefs copies. Spelled out rather
  /// than derived from the current constants, which no longer match them.
  static List<String> _staleFileNames(String appName) => [
    '${_safe(appName)}@128',
    '${_safe(appName)}@128v2',
  ];

  static Future<Uint8List?> read(String hostId, String appName) async {
    final directory = await _directory(hostId);
    if (directory == null) return null;
    final file = File('${directory.path}/${_fileName(appName)}');
    try {
      if (file.existsSync()) return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
    await _discardLegacyEntry(hostId, appName);
    await _discardStaleFiles(directory, appName);
    return null;
  }

  /// Earlier builds kept icons in shared_preferences, at a smaller size.
  /// Those bytes are the wrong resolution to reuse, so they are dropped to
  /// reclaim the space and refetched at the current size.
  static Future<void> _discardLegacyEntry(String hostId, String appName) async {
    final key = 'icon:$hostId:$appName';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(key)) await prefs.remove(key);
  }

  static Future<void> _discardStaleFiles(
    Directory directory,
    String appName,
  ) async {
    for (final name in _staleFileNames(appName)) {
      try {
        final file = File('${directory.path}/$name');
        if (file.existsSync()) await file.delete();
      } on FileSystemException {
        // Left behind, it only costs a few KB.
      }
    }
  }

  static Future<void> write(
    String hostId,
    String appName,
    Uint8List bytes,
  ) async {
    final directory = await _directory(hostId);
    if (directory == null) return;
    try {
      await File(
        '${directory.path}/${_fileName(appName)}',
      ).writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      // A cache that cannot be written is a slow deck, not a broken one.
    }
  }
}
