import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import 'deck_store.dart';
import 'protocol.dart';

/// Where the link is in the connect -> discover -> subscribe sequence.
enum LinkStage {
  connecting('Connecting'),
  discovering('Discovering services'),
  subscribing('Subscribing'),
  ready('Connected'),
  disconnected('Disconnected'),
  failed('Failed');

  const LinkStage(this.label);
  final String label;
}

/// An app on the host that a deck button can launch.
class DeckApp {
  const DeckApp({required this.name, required this.category});

  final String name;
  final String category;
}

/// One line in the debug console.
class LinkMessage {
  LinkMessage({required this.text, required this.inbound})
    : at = DateTime.now();

  final String text;
  final bool inbound;
  final DateTime at;
}

/// Owns the BLE link to one host and the state both client screens read.
///
/// The deck and the debug console are two views of this single connection,
/// so neither may open one of its own.
class BtLinkSession extends ChangeNotifier {
  BtLinkSession({required this.peripheral, required this.name});

  final Peripheral peripheral;
  final String name;

  final _central = CentralManager();
  final _subscriptions = <StreamSubscription>[];

  LinkStage _stage = LinkStage.connecting;
  String? _error;
  GATTCharacteristic? _notifyCharacteristic;
  GATTCharacteristic? _writeCharacteristic;

  /// The user's chosen buttons, in deck order. Held here because both
  /// screens read it, and it belongs to this host like the catalogue does.
  var _selected = <String>[];
  final _apps = <DeckApp>[];
  bool _loadingApps = false;
  final _log = <LinkMessage>[];
  int? _mtu;
  String? _lastAck;

  LinkStage get stage => _stage;
  String? get error => _error;
  bool get ready => _stage == LinkStage.ready;
  List<DeckApp> get apps => List.unmodifiable(_apps);
  List<String> get selected => List.unmodifiable(_selected);
  bool isSelected(String appName) => _selected.contains(appName);

  /// Identifies this host's layout in storage.
  String get hostId => peripheral.uuid.toString();
  bool get loadingApps => _loadingApps;
  List<LinkMessage> get log => List.unmodifiable(_log);
  int? get mtu => _mtu;
  String? get lastAck => _lastAck;

  void start() {
    _loadSelection();
    _subscriptions.add(
      _central.connectionStateChanged.listen((event) {
        if (event.peripheral.uuid != peripheral.uuid) return;
        if (event.state == ConnectionState.disconnected) {
          _stage = LinkStage.disconnected;
          _notifyCharacteristic = null;
          _writeCharacteristic = null;
          notifyListeners();
        }
      }),
    );

    _subscriptions.add(
      _central.characteristicNotified.listen((event) {
        if (event.peripheral.uuid != peripheral.uuid) return;
        if (event.characteristic.uuid != BtLink.notifyCharacteristicUuid) {
          return;
        }
        _receive(event.value);
      }),
    );

    connect();
  }

  void _receive(List<int> bytes) {
    final message = BtMessage.decode(bytes);
    if (message == null) {
      _append('unparsed (${bytes.length} bytes)', inbound: true);
      return;
    }
    switch (message) {
      case AppEntry(:final name, :final category):
        _apps.add(DeckApp(name: name, category: category ?? 'Apps'));
      case ListEnd(:final count):
        _loadingApps = false;
        _append('catalogue complete: $count apps', inbound: true);
      case Ack(:final ok, :final message):
        _lastAck = message;
        _append('${ok ? 'ok' : 'error'}: $message', inbound: true);
      case DebugText(:final text):
        _append(text, inbound: true);
      case ListApps() || OpenApp():
        // Client-to-host shapes; a host has no business sending them.
        _append('ignored a ${message.runtimeType}', inbound: true);
    }
    notifyListeners();
  }

  void _append(String text, {required bool inbound}) {
    _log.add(LinkMessage(text: text, inbound: inbound));
    if (_log.length > 200) _log.removeAt(0);
  }

  Future<void> connect() async {
    _stage = LinkStage.connecting;
    _error = null;
    // A drop mid-catalogue leaves this set; clear it so the retry can ask.
    _loadingApps = false;
    notifyListeners();
    try {
      // Scanning while connecting slows the connection down and on some
      // platforms blocks it outright.
      await _central.stopDiscovery();
      await _central.connect(peripheral);

      _stage = LinkStage.discovering;
      notifyListeners();

      // The default 23-byte MTU leaves 20 bytes of payload, too little for
      // even a short JSON message. Android is the only platform that lets us
      // ask; elsewhere the stack negotiates on its own.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          _mtu = await _central.requestMTU(peripheral, mtu: 512);
        } on UnsupportedError {
          // Not fatal — the negotiated default may still be enough.
        }
      }

      final services = await _central.discoverGATT(peripheral);
      final service = services
          .where((s) => s.uuid == BtLink.serviceUuid)
          .firstOrNull;
      if (service == null) {
        throw StateError(
          'This device does not expose the BTLink service '
          '(${BtLink.serviceUuid}).',
        );
      }

      final notify = service.characteristics
          .where((c) => c.uuid == BtLink.notifyCharacteristicUuid)
          .firstOrNull;
      final write = service.characteristics
          .where((c) => c.uuid == BtLink.writeCharacteristicUuid)
          .firstOrNull;
      if (notify == null || write == null) {
        throw StateError(
          'The BTLink service is missing its notify or write characteristic.',
        );
      }

      _stage = LinkStage.subscribing;
      _notifyCharacteristic = notify;
      _writeCharacteristic = write;
      notifyListeners();

      await _central.setCharacteristicNotifyState(
        peripheral,
        notify,
        state: true,
      );

      _stage = LinkStage.ready;
      notifyListeners();

      await refreshApps();
    } catch (error) {
      _stage = LinkStage.failed;
      _error = '$error';
      notifyListeners();
    }
  }

  Future<void> _loadSelection() async {
    _selected = List.of(await DeckStore.load(hostId));
    notifyListeners();
  }

  Future<void> toggleSelection(String appName) async {
    if (!_selected.remove(appName)) _selected.add(appName);
    notifyListeners();
    await DeckStore.save(hostId, _selected);
  }

  Future<void> reorderSelection(int oldIndex, int newIndex) async {
    _selected = DeckStore.reordered(_selected, oldIndex, newIndex);
    notifyListeners();
    await DeckStore.save(hostId, _selected);
  }

  Future<void> refreshApps() async {
    // The catalogue is ~100 notifications paced at 20ms; overlapping requests
    // would interleave two streams into one list.
    if (!ready || _loadingApps) return;
    _apps.clear();
    _loadingApps = true;
    notifyListeners();
    await _send(const ListApps());
  }

  Future<void> openApp(String name) async {
    _append('open $name', inbound: false);
    notifyListeners();
    await _send(OpenApp(name: name));
  }

  Future<void> sendDebugText(String text) async {
    _append(text, inbound: false);
    notifyListeners();
    await _send(DebugText(text: text));
  }

  Future<void> _send(BtMessage message) async {
    final characteristic = _writeCharacteristic;
    if (characteristic == null) return;
    try {
      await _central.writeCharacteristic(
        peripheral,
        characteristic,
        value: message.encode(),
        type: GATTCharacteristicWriteType.withResponse,
      );
    } catch (error) {
      _append('send failed: $error', inbound: true);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _teardown();
    super.dispose();
  }

  Future<void> _teardown() async {
    try {
      final notify = _notifyCharacteristic;
      if (notify != null && _stage == LinkStage.ready) {
        await _central.setCharacteristicNotifyState(
          peripheral,
          notify,
          state: false,
        );
      }
      await _central.disconnect(peripheral);
    } catch (_) {
      // Tearing down a link that is already gone is not worth reporting.
    }
  }
}
