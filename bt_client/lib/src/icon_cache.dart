import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<Uint8List?> read(String hostId, String appName) async {
    final directory = await _directory(hostId);
    if (directory == null) return null;
    final file = File('${directory.path}/${_safe(appName)}');
    try {
      if (file.existsSync()) return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
    return _adoptLegacyEntry(hostId, appName, file);
  }

  /// Earlier builds kept icons in shared_preferences. Move one across on
  /// first read so an upgrade does not refetch a deck's worth of icons, and
  /// drop the preference so the space is reclaimed.
  static Future<Uint8List?> _adoptLegacyEntry(
    String hostId,
    String appName,
    File destination,
  ) async {
    final key = 'icon:$hostId:$appName';
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(key);
    if (encoded == null) return null;
    await prefs.remove(key);
    try {
      final bytes = base64Decode(encoded);
      await destination.writeAsBytes(bytes, flush: true);
      return bytes;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
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
        '${directory.path}/${_safe(appName)}',
      ).writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      // A cache that cannot be written is a slow deck, not a broken one.
    }
  }
}
