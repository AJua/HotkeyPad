import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// One connected WiFi client — the WiFi transport's equivalent of a BLE
/// `Central`, minimal on purpose since [WifiServer] is the only thing that
/// ever touches the underlying [Socket] directly.
class WifiClient {
  /// Captures [id] once here rather than computing it lazily from
  /// [socket] on every access: `socket.remoteAddress`/`remotePort` throw
  /// `SocketException: Socket has been closed` once the socket actually
  /// is — exactly the moment a disconnect handler needs the id to remove
  /// this client from a map. Confirmed against a real disconnect: the old
  /// getter form took the whole cleanup path down with it, silently
  /// leaking the entry (see `WifiServer.start`'s `cleanUp`) rather than
  /// ever reaching `onDisconnected`.
  WifiClient(this.socket)
    : id = 'wifi:${socket.remoteAddress.address}:${socket.remotePort}';

  final Socket socket;

  /// Namespaced and scoped to this one TCP connection, unlike a BLE
  /// central's uuid — a reconnect after any drop gets a new ephemeral
  /// source port, and therefore a new id, so a WiFi client that drops and
  /// comes back is (deliberately) treated as a new device-lock candidate
  /// rather than assumed to be the one that just left.
  final String id;

  Future<void> send(Uint8List bytes) async {
    socket.add(FrameCodec.encode(bytes));
    await socket.flush();
  }
}

/// The host's WiFi transport: a TCP server for the link itself, plus a
/// periodic UDP beacon so a client on the same LAN can find it.
///
/// Every message on the wire — [HotkeyPadMessage] JSON, [IconFrame] chunks — is
/// byte-for-byte identical to what the Bluetooth transport carries; only
/// framing differs (see [FrameCodec]/[FrameReassembler]), since a GATT
/// write/notify already delivers one whole message per call and a TCP
/// socket does not. That is the only reason this class exists rather than
/// reusing the BLE path directly.
class WifiServer {
  ServerSocket? _tcpServer;
  RawDatagramSocket? _beaconSocket;
  Timer? _beaconTimer;
  final _clients = <String, WifiClient>{};

  bool get running => _tcpServer != null;

  Future<void> start({
    required String hostId,
    required String hostName,
    required void Function(WifiClient client) onConnected,
    required void Function(WifiClient client, Uint8List message) onMessage,
    required void Function(WifiClient client) onDisconnected,
  }) async {
    if (running) return;
    _tcpServer = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      WifiLink.tcpPort,
    );
    _tcpServer!.listen((socket) {
      final client = WifiClient(socket);
      _clients[client.id] = client;
      onConnected(client);

      final reassembler = FrameReassembler();
      void cleanUp() {
        if (_clients.remove(client.id) != null) onDisconnected(client);
      }

      socket.listen(
        (chunk) {
          for (final frame in reassembler.add(chunk)) {
            onMessage(client, frame);
          }
        },
        onDone: cleanUp,
        onError: (_) => cleanUp(),
        cancelOnError: true,
      );
    });

    // Best-effort: a host that cannot bind a UDP broadcast socket (an
    // unusual sandbox, say) still serves the clients that already know its
    // address, so a failure here does not take the TCP server down too.
    try {
      final beaconSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      beaconSocket.broadcastEnabled = true;
      _beaconSocket = beaconSocket;
      // A RawDatagramSocket only keeps accepting sends while something is
      // pumping its event loop via listen() — without this, the very
      // first send() succeeds (the socket starts writable) but every one
      // after silently returns 0 bytes and is dropped, since nothing ever
      // observes the write-readiness event that would let it accept more.
      // This socket never receives anything back, so the subscription
      // itself has nothing to do beyond existing — except handle errors:
      // an unreachable broadcast route surfaces here, asynchronously,
      // rather than by throwing out of send() below, and an error left
      // unhandled on a stream crashes the whole zone instead of just
      // this one beacon.
      beaconSocket.listen((_) {}, onError: (_) {});
      final beacon = WifiBeacon(
        hostId: hostId,
        name: hostName,
        port: WifiLink.tcpPort,
      ).encode();
      // The global limited broadcast (255.255.255.255) is included for
      // portability, but is not enough on its own: confirmed on real
      // hardware, repeat sends to it can fail outright (SocketException:
      // No route to host) on some networks after the very first one — a
      // subnet-directed broadcast (below) is what actually gets through
      // reliably there. Computed once at start rather than per tick:
      // interfaces essentially never change mid-run, and recomputing on
      // every timer tick would mean an async NetworkInterface.list() call
      // every 2 seconds for no benefit.
      final targets = await _broadcastTargets();
      _beaconTimer = Timer.periodic(WifiLink.beaconInterval, (_) {
        for (final target in targets) {
          try {
            beaconSocket.send(beacon, target, WifiLink.discoveryPort);
          } catch (_) {
            // This target's route may simply not be there right now; the
            // other targets, and the next tick, still get a chance.
          }
        }
      });
    } catch (_) {
      // No discovery beacon; the TCP server above still runs.
    }
  }

  /// Every address worth broadcasting the beacon to: the global limited
  /// broadcast, plus a best-effort subnet-directed broadcast for each
  /// active IPv4 interface — see the call site for why the global one
  /// alone is not reliable enough. `NetworkInterface` exposes no netmask
  /// on any platform Dart supports, so the subnet address is a deliberate
  /// /24 assumption (`x.y.z.255`) rather than a computed one; every
  /// network this needs to reach in practice — a home or office LAN — is
  /// one, even though nothing here guarantees it in general.
  Future<Set<InternetAddress>> _broadcastTargets() async {
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final octets = address.address.split('.');
          if (octets.length == 4) {
            targets.add(
              InternetAddress('${octets[0]}.${octets[1]}.${octets[2]}.255'),
            );
          }
        }
      }
    } catch (_) {
      // The global broadcast above is still attempted regardless.
    }
    return targets;
  }

  /// Every non-loopback IPv4 address this machine currently has, for
  /// display — the host has no way to know which one (if more than one)
  /// is actually reachable from a given client, so this just lists all of
  /// them and leaves picking the right one to whoever is typing it into
  /// the client's manual-entry field. Static, and independent of
  /// [running], since it is just as useful to see before starting the
  /// service as after.
  static Future<List<String>> localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return [
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _beaconSocket?.close();
    _beaconSocket = null;
    for (final client in _clients.values.toList()) {
      await client.socket.close();
    }
    _clients.clear();
    await _tcpServer?.close();
    _tcpServer = null;
  }
}
