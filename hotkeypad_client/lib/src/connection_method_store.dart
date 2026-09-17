import 'package:shared_preferences/shared_preferences.dart';

/// Which discovery transport the client actively tries — chosen once by
/// the user rather than raced silently on every launch. Racing both was
/// the original design (see `deck_page.dart`'s history), but a host some
/// clients simply cannot reach one way — an emulator with no Bluetooth
/// radio and a NAT'd network the WiFi beacon never crosses, say — turned
/// the race into a silent stall with no way to skip straight to the
/// transport that would actually work.
enum ConnectionMethod { bluetooth, wifi }

/// Pure — turns a stored key back into the [ConnectionMethod] it names.
/// Null (never saved, or an unrecognized value from some future build)
/// means "show the choice screen", the same meaning [ConnectionMethodStore
/// .load]'s null already carries.
ConnectionMethod? connectionMethodFromKey(String? key) => switch (key) {
  'bluetooth' => ConnectionMethod.bluetooth,
  'wifi' => ConnectionMethod.wifi,
  _ => null,
};

/// Pure — the inverse of [connectionMethodFromKey], for saving what the
/// choice screen (or the settings sheet that revisits it) picked.
String keyFromConnectionMethod(ConnectionMethod method) => switch (method) {
  ConnectionMethod.bluetooth => 'bluetooth',
  ConnectionMethod.wifi => 'wifi',
};

/// The user's own chosen [ConnectionMethod], stored on this phone only —
/// the host has no say in it, the same reason `LocaleStore` is never sent
/// to or learned from the host either.
///
/// Null means "never chosen" and is what tells `DeckPage` to show the
/// choice screen instead of connecting to anything.
abstract final class ConnectionMethodStore {
  static const _key = 'connection_method';

  static Future<ConnectionMethod?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return connectionMethodFromKey(prefs.getString(_key));
  }

  static Future<void> save(ConnectionMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, keyFromConnectionMethod(method));
  }
}
