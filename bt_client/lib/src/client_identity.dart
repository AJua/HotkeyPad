import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A persistent id for this install, generated once and sent as part of
/// every [Hello] regardless of transport.
///
/// Bluetooth has no use for it — a subscribed central is already usable,
/// gated only by the host's device lock. WiFi's trust-on-first-use PIN
/// pairing needs it though: the transport-level id
/// (`BtLinkSession.hostId`'s WiFi counterpart, a socket's address:port)
/// changes on every reconnect, so it cannot be what the host remembers
/// "this device already answered the PIN correctly" against — this can.
abstract final class ClientIdentity {
  static String? _cached;
  static const _key = 'clientId';

  static Future<String> id() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return _cached = existing;

    final generated = _generate();
    await prefs.setString(_key, generated);
    return _cached = generated;
  }

  static String _generate() =>
      'client_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
}
