import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';

/// Caches the layout the host sent, per host.
///
/// The host owns the layout; this is only so the deck can draw something
/// before the link is up, and so a brief drop does not blank the screen.
abstract final class DeckStore {
  static String _key(String hostId) => 'layout:$hostId';

  static Future<DeckLayout?> load(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key(hostId));
    if (encoded == null) return null;
    try {
      return DeckLayout.fromJson(jsonDecode(encoded));
    } on FormatException {
      await prefs.remove(_key(hostId));
      return null;
    }
  }

  static Future<DeckTheme> loadTheme(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    return DeckTheme.fromWire(prefs.getString('theme:$hostId'));
  }

  static Future<void> saveTheme(String hostId, DeckTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme:$hostId', theme.wire);
  }

  static Future<void> save(String hostId, DeckLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(hostId), jsonEncode(layout.toJson()));
  }
}
