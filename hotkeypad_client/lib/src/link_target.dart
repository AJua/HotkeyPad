import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// Which host a [HotkeyPadSession] connects to, and over which transport —
/// the one thing that differs between an otherwise identical link, so
/// everything else about a session (message parsing, icon reassembly,
/// reconnect backoff) stays the same regardless of which of these it holds.
sealed class LinkTarget {
  const LinkTarget();
}

/// A host reached over Bluetooth LE — the peripheral discovered scanning.
final class BleTarget extends LinkTarget {
  const BleTarget(this.peripheral);

  final Peripheral peripheral;
}

/// A host reached over the local network, found via its `WifiBeacon`.
final class WifiTarget extends LinkTarget {
  const WifiTarget({
    required this.hostId,
    required this.address,
    required this.port,
  });

  /// The host's own persistent id (see `hotkeypad_host`'s `HostIdentity`) —
  /// namespaced separately from a BLE peripheral's uuid, since the two
  /// transports share no identity; see [HotkeyPadSession.hostId].
  final String hostId;

  final String address;
  final int port;
}

/// The synthetic host id a manually-typed WiFi target gets, since there is
/// no beacon to learn the real one (see [WifiTarget.hostId]'s doc comment)
/// from when discovery cannot reach the host — a client on an emulator or
/// a network with AP client isolation, say. Stable for as long as the same
/// address:port is entered again, which is exactly what layout/icon
/// caching (`HotkeyPadSession.hostId`) needs; if the host's address changes
/// later (a DHCP lease renewing, say) this becomes a distinct cache entry
/// rather than a merged one — an acceptable rough edge for a fallback
/// path that beacon discovery makes unnecessary the rest of the time.
///
/// A pure function of the two inputs so it is testable without a widget.
String manualWifiHostId({required String address, required int port}) =>
    'manual:$address:$port';
