import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One WiFi host this app has successfully connected to before.
///
/// Bluetooth is deliberately excluded — a `BleTarget` has no IP to
/// remember, and BLE discovery is already fast and automatic (physical
/// proximity is the whole filter). This is specifically the WiFi
/// fallback path's own memory, for a network where discovery/broadcast
/// cannot reach the phone (AP client isolation, a different subnet).
class HostHistoryEntry {
  const HostHistoryEntry({
    required this.hostId,
    required this.address,
    required this.port,
    required this.name,
    required this.lastConnectedAt,
  });

  /// Whatever [WifiTarget.hostId] the connection this was recorded from
  /// actually used — the real, persistent id for a beacon- or QR-
  /// discovered host, or the synthetic `manual:...` one from
  /// [manualWifiHostId] if it was typed in by hand. Reused verbatim when
  /// reconnecting from this entry, so a QR-paired host's cached
  /// layout/icons stay the same cache entry on a later history-reconnect
  /// instead of silently splitting into a second, `manual:`-prefixed one.
  final String hostId;

  final String address;
  final int port;
  final String name;
  final DateTime lastConnectedAt;

  Map<String, Object?> toJson() => {
    'hostId': hostId,
    'address': address,
    'port': port,
    'name': name,
    'lastConnectedAt': lastConnectedAt.toIso8601String(),
  };

  static HostHistoryEntry? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final hostId = json['hostId'];
    final address = json['address'];
    final port = json['port'];
    final name = json['name'];
    final lastConnectedAt = json['lastConnectedAt'];
    if (hostId is! String || hostId.isEmpty) return null;
    if (address is! String || address.isEmpty) return null;
    if (port is! int) return null;
    if (name is! String) return null;
    if (lastConnectedAt is! String) return null;
    final parsed = DateTime.tryParse(lastConnectedAt);
    if (parsed == null) return null;
    return HostHistoryEntry(
      hostId: hostId,
      address: address,
      port: port,
      name: name,
      lastConnectedAt: parsed,
    );
  }
}

/// How many hosts [upsertHistory] keeps. A short list someone can
/// actually scan by eye beats a complete log of every network this
/// phone has ever seen a HotkeyPad host on.
const hostHistoryLimit = 8;

/// Pure — inserts or updates [entry] in [current], keyed by
/// address+port (a host that changed its display name since is still
/// "the same host" for this list), moves it to the front as the most
/// recent, and trims to [hostHistoryLimit].
///
/// Extracted from [HostHistoryStore] so the actual list-maintenance
/// policy is testable without touching SharedPreferences, the same
/// reason `wifiTrustFor`/`isPressAllowed` are standalone functions on
/// the host side.
List<HostHistoryEntry> upsertHistory(
  List<HostHistoryEntry> current,
  HostHistoryEntry entry,
) {
  final next = [
    entry,
    ...current.where(
      (e) => !(e.address == entry.address && e.port == entry.port),
    ),
  ];
  if (next.length > hostHistoryLimit) next.removeRange(hostHistoryLimit, next.length);
  return next;
}

/// Persists every WiFi host this app has connected to, most recent
/// first — so a manual reconnect on a network discovery can't reach
/// (AP client isolation, a different subnet than last time) is a tap
/// instead of retyping an IP address.
abstract final class HostHistoryStore {
  static const _key = 'wifi_host_history';

  static Future<List<HostHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key);
    if (encoded == null) return [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return [];
      return [
        for (final item in decoded) ?HostHistoryEntry.tryFromJson(item),
      ];
    } on FormatException {
      return [];
    }
  }

  /// Records a successful connection — called once a WiFi session
  /// actually reaches [LinkStage.ready], never on a mere attempt.
  static Future<void> recordConnected({
    required String hostId,
    required String address,
    required int port,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final next = upsertHistory(
      current,
      HostHistoryEntry(
        hostId: hostId,
        address: address,
        port: port,
        name: name,
        lastConnectedAt: DateTime.now(),
      ),
    );
    await prefs.setString(
      _key,
      jsonEncode([for (final entry in next) entry.toJson()]),
    );
  }

  static Future<void> forget(String address, int port) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final next = current
        .where((e) => !(e.address == address && e.port == port))
        .toList();
    if (next.length == current.length) return;
    await prefs.setString(
      _key,
      jsonEncode([for (final entry in next) entry.toJson()]),
    );
  }
}
