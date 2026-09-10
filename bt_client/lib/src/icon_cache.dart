import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores app icons so they are fetched over BLE once, not on every launch.
/// A 64px PNG is ~5KB and takes a dozen notifications to transfer.
///
/// Icons live in shared_preferences as base64 rather than in files under
/// `path_provider`. That package pulls in `objective_c`, which loads a dylib
/// through Flutter's native-assets mechanism; on this toolchain it failed to
/// resolve on macOS and crashed the app at launch on iOS. shared_preferences
/// is a plain method channel, is already a dependency, and the volume here is
/// small: a deck is a handful of buttons, not the host's whole catalogue.
///
/// Icons are namespaced by host: two hosts can have different apps, and
/// different icons for the same app name.
abstract final class IconCache {
  static String _key(String hostId, String appName) =>
      'icon:$hostId:$appName';

  static Future<Uint8List?> read(String hostId, String appName) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key(hostId, appName));
    if (encoded == null) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      // A corrupt entry should be refetched, not crash the deck.
      await prefs.remove(_key(hostId, appName));
      return null;
    }
  }

  static Future<void> write(
    String hostId,
    String appName,
    Uint8List bytes,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(hostId, appName), base64Encode(bytes));
  }
}
