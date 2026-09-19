import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Everything [DeckStore.loadAppearance] restores before the link comes up,
/// bundled together because it always travels as one unit — see
/// [HotkeyPadSession]'s own appearance fields, which mirror this shape.
typedef CachedAppearance = ({
  DeckTheme theme,
  bool showLabels,
  String? backgroundImageId,
  double backgroundOpacity,
  BackgroundFit backgroundFit,
});

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

  static Future<CachedAppearance> loadAppearance(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    return (
      theme: DeckTheme.fromWire(prefs.getString('theme:$hostId')),
      showLabels: prefs.getBool('labels:$hostId') ?? true,
      backgroundImageId: prefs.getString('bg:$hostId'),
      backgroundOpacity: prefs.getDouble('bgOpacity:$hostId') ?? 1.0,
      backgroundFit: BackgroundFit.fromWire(prefs.getString('bgFit:$hostId')),
    );
  }

  static Future<void> saveAppearance(
    String hostId,
    DeckTheme theme,
    bool showLabels, {
    String? backgroundImageId,
    double backgroundOpacity = 1.0,
    BackgroundFit backgroundFit = BackgroundFit.cover,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme:$hostId', theme.wire);
    await prefs.setBool('labels:$hostId', showLabels);
    // Removed rather than set to an empty string: a missing key is what
    // loadAppearance's prefs.getString(...) == null branch expects for "no
    // background", matching how the host itself treats a null id.
    if (backgroundImageId == null) {
      await prefs.remove('bg:$hostId');
    } else {
      await prefs.setString('bg:$hostId', backgroundImageId);
    }
    await prefs.setDouble('bgOpacity:$hostId', backgroundOpacity);
    await prefs.setString('bgFit:$hostId', backgroundFit.wire);
  }

  static Future<void> save(String hostId, DeckLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(hostId), jsonEncode(layout.toJson()));
  }
}
