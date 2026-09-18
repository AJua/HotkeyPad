import 'package:shared_preferences/shared_preferences.dart';

/// Whether to show the analog clock and/or the month calendar beside the
/// deck in landscape — a per-device display preference only, same as
/// [ConnectionMethodStore]: never sent to or learned from the host, off by
/// default since the deck's own margins are the whole point until asked
/// for otherwise.
abstract final class LandscapeWidgetsStore {
  static const _clockKey = 'landscape_show_clock';
  static const _dateKey = 'landscape_show_date';

  static Future<bool> loadShowClock() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_clockKey) ?? false;
  }

  static Future<void> saveShowClock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clockKey, value);
  }

  static Future<bool> loadShowDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dateKey) ?? false;
  }

  static Future<void> saveShowDate(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dateKey, value);
  }
}
