import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// Which host a [BtLinkSession] connects to, and over which transport —
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

  /// The host's own persistent id (see `bt_host`'s `HostIdentity`) —
  /// namespaced separately from a BLE peripheral's uuid, since the two
  /// transports share no identity; see [BtLinkSession.hostId].
  final String hostId;

  final String address;
  final int port;
}
