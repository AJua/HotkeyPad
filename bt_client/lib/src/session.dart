import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
// Flutter's ConnectionState (StreamBuilder) collides with the BLE one.
import 'package:flutter/widgets.dart' hide ConnectionState;

import 'dart:typed_data';

import 'deck_store.dart';
import 'icon_cache.dart';
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

  /// The grid the host sent. Cached locally so the deck draws immediately
  /// on open rather than after the link comes up.
  DeckLayout? _layout;

  /// A layout being received cell by cell; promoted to [_layout] on
  /// LayoutEnd so a partial grid is never shown.
  DeckLayout? _incoming;
  bool _loadingLayout = false;
  final _apps = <DeckApp>[];

  /// Decoded icons, keyed by app name. Populated from the disk cache first
  /// and from the host only for what is missing.
  final _icons = <String, Uint8List>{};

  /// Frames arriving for an icon that is not complete yet.
  final _partialIcons = <String, List<Uint8List?>>{};

  /// Names already asked for, so a rebuild does not re-request.
  final _requestedIcons = <String>{};
  final _iconQueue = <String>[];
  bool _fetchingIcon = false;
  bool _loadingApps = false;
  final _log = <LinkMessage>[];
  int? _mtu;
  String? _lastAck;

  Timer? _reconnectTimer;
  Timer? _countdownTimer;
  int _reconnectAttempt = 0;
  int? _reconnectIn;
  AppLifecycleListener? _lifecycle;

  LinkStage get stage => _stage;
  String? get error => _error;
  bool get ready => _stage == LinkStage.ready;
  List<DeckApp> get apps => List.unmodifiable(_apps);
  DeckLayout? get layout => _layout;
  bool get loadingLayout => _loadingLayout;
  Uint8List? iconFor(String appName) => _icons[appName];

  /// Identifies this host's layout in storage.
  String get hostId => peripheral.uuid.toString();
  bool get loadingApps => _loadingApps;
  List<LinkMessage> get log => List.unmodifiable(_log);
  int? get mtu => _mtu;
  String? get lastAck => _lastAck;

  /// How many reconnects have been attempted since the last good link.
  int get reconnectAttempt => _reconnectAttempt;

  /// Seconds until the next automatic attempt, or null when not waiting.
  int? get reconnectIn => _reconnectIn;

  void start() {
    _loadLayout();

    // Coming back from a locked screen is the common way this link dies, and
    // the user is looking at the deck when it happens. Do not make them wait
    // out the backoff.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_reconnectTimer?.isActive ?? false) _reconnectNow();
      },
    );
    _subscriptions.add(
      _central.connectionStateChanged.listen((event) {
        if (event.peripheral.uuid != peripheral.uuid) return;
        if (event.state == ConnectionState.disconnected) {
          _stage = LinkStage.disconnected;
          _notifyCharacteristic = null;
          _writeCharacteristic = null;
          notifyListeners();
          _scheduleReconnect();
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
    if (IconFrame.looksLikeFrame(bytes)) {
      _receiveIconFrame(bytes);
      return;
    }
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
        // Now that the names are in, start filling in the pictures.
        unawaited(_drainIconQueue());
      case Ack(:final ok, :final message):
        _lastAck = message;
        _append('${ok ? 'ok' : 'error'}: $message', inbound: true);
      case DebugText(:final text):
        _append(text, inbound: true);
      case LayoutStart(:final columns, :final rows, :final pages):
        _incoming = DeckLayout.empty(
          columns: columns,
          rows: rows,
          pages: pages,
        );
        _loadingLayout = true;
      case LayoutSlot(:final index, :final value):
        final incoming = _incoming;
        if (incoming != null && index >= 0 && index < incoming.capacity) {
          _incoming = incoming.withSlot(index, value);
        }
      case LayoutEnd():
        final incoming = _incoming;
        _loadingLayout = false;
        if (incoming != null) {
          _layout = incoming;
          _incoming = null;
          unawaited(DeckStore.save(hostId, incoming));
          _append('layout: ${incoming.columns}x${incoming.rows}', inbound: true);
        }
      case IconUnavailable(:final name):
        _append('no icon for $name', inbound: true);
        _finishIconFetch(name);
      case ListApps() ||
          OpenApp() ||
          RequestIcon() ||
          RunAction() ||
          RequestLayout():
        // Client-to-host shapes; a host has no business sending them.
        _append('ignored a ${message.runtimeType}', inbound: true);
    }
    notifyListeners();
  }

  void _receiveIconFrame(List<int> bytes) {
    final frame = IconFrame.decode(bytes);
    if (frame == null) {
      _append('malformed icon frame (${bytes.length} bytes)', inbound: true);
      return;
    }

    final slots = _partialIcons.putIfAbsent(
      frame.name,
      () => List<Uint8List?>.filled(frame.total, null),
    );
    if (slots.length != frame.total) {
      // The host restarted the transfer with a different chunk count.
      _partialIcons[frame.name] = List<Uint8List?>.filled(frame.total, null);
    }
    _partialIcons[frame.name]![frame.index] = frame.payload;

    if (_partialIcons[frame.name]!.any((slot) => slot == null)) return;

    final builder = BytesBuilder();
    for (final slot in _partialIcons.remove(frame.name)!) {
      builder.add(slot!);
    }
    final icon = builder.toBytes();
    _icons[frame.name] = icon;
    unawaited(IconCache.write(hostId, frame.name, icon));
    _append('icon for ${frame.name} (${icon.length} bytes)', inbound: true);
    _finishIconFetch(frame.name);
    notifyListeners();
  }

  /// Fetches [appName]'s icon if it is not already known, preferring the disk
  /// cache. Requests are queued one at a time so a deck full of new buttons
  /// does not flood the notification queue.
  Future<void> ensureIcon(String appName) async {
    if (_icons.containsKey(appName)) return;
    if (!_requestedIcons.add(appName)) return;

    // Reading the disk cache costs nothing on the link, so it is not held
    // back by the catalogue.
    final cached = await IconCache.read(hostId, appName);
    if (cached != null) {
      _icons[appName] = cached;
      notifyListeners();
      return;
    }

    _iconQueue.add(appName);
    unawaited(_drainIconQueue());
  }

  Future<void> _drainIconQueue() async {
    // The catalogue comes first. Icons are large and many; interleaving them
    // with ~100 catalogue notifications would leave the deck without labels
    // for far longer than it leaves it without pictures.
    if (_loadingApps) return;
    if (_fetchingIcon || _iconQueue.isEmpty || !ready) return;
    _fetchingIcon = true;
    final appName = _iconQueue.removeAt(0);
    await _send(RequestIcon(name: appName));
    // The host answers with frames; _finishIconFetch releases the queue. A
    // host that never answers must not wedge it, hence the timeout.
    _iconTimeout = Timer(const Duration(seconds: 10), () {
      _finishIconFetch(appName);
    });
  }

  Timer? _iconTimeout;

  void _finishIconFetch(String appName) {
    _iconTimeout?.cancel();
    _iconTimeout = null;
    _fetchingIcon = false;
    unawaited(_drainIconQueue());
  }

  void _append(String text, {required bool inbound}) {
    _log.add(LinkMessage(text: text, inbound: inbound));
    if (_log.length > 200) _log.removeAt(0);
  }

  /// Backs off so a host that is off for the evening is not polled every
  /// second, while a host that is merely restarting is picked up quickly.
  static int _backoffSeconds(int attempt) => switch (attempt) {
    0 => 1,
    1 => 2,
    2 => 5,
    3 => 10,
    _ => 30,
  };

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _countdownTimer?.cancel();

    final delay = _backoffSeconds(_reconnectAttempt);
    _reconnectAttempt += 1;
    _reconnectIn = delay;
    notifyListeners();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _reconnectIn;
      if (remaining == null || remaining <= 0) return;
      _reconnectIn = remaining - 1;
      notifyListeners();
    });
    _reconnectTimer = Timer(Duration(seconds: delay), _reconnectNow);
  }

  void _reconnectNow() {
    _reconnectTimer?.cancel();
    _countdownTimer?.cancel();
    _reconnectIn = null;
    connect();
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _countdownTimer?.cancel();
    _reconnectTimer = null;
    _countdownTimer = null;
    _reconnectIn = null;
  }

  Future<void> connect() async {
    final reconnecting =
        _stage == LinkStage.disconnected || _stage == LinkStage.failed;
    _cancelReconnect();
    _stage = LinkStage.connecting;
    _error = null;
    // A drop mid-catalogue leaves this set; clear it so the retry can ask.
    _loadingApps = false;
    notifyListeners();
    try {
      // Reconnecting straight after a drop fails on Android with
      // "Write descriptor failed with status: 1" (GATT_INVALID_HANDLE): the
      // stack is still tearing the old link down when the new descriptor
      // write arrives. Close it explicitly and give the stack a moment.
      if (reconnecting) {
        try {
          await _central.disconnect(peripheral);
        } catch (_) {
          // Already gone is the expected case here.
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

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
      _reconnectAttempt = 0;
      notifyListeners();

      await requestLayout();
    } catch (error) {
      _stage = LinkStage.failed;
      _error = '$error';
      _append('connect failed: $error', inbound: true);
      notifyListeners();
      // A device that does not speak BTLink will not start doing so; only
      // transient failures are worth retrying.
      if (error is! StateError) _scheduleReconnect();
    }
  }

  /// The first line of [error], capped. Platform exceptions arrive with a
  /// full Java stack trace attached, which is debug-console material — it
  /// would otherwise push every button off the screen.
  String? get errorSummary {
    final error = _error;
    if (error == null) return null;
    final firstLine = error.split('\n').first.trim();
    return firstLine.length > 160
        ? '${firstLine.substring(0, 160)}…'
        : firstLine;
  }

  Future<void> _loadLayout() async {
    final cached = await DeckStore.load(hostId);
    if (cached == null || _layout != null) return;
    _layout = cached;
    notifyListeners();
  }

  /// Asks the host for the current layout. The host pushes it again whenever
  /// it is edited, so this is only needed on connect.
  Future<void> requestLayout() async {
    if (!ready) return;
    _loadingLayout = true;
    notifyListeners();
    await _send(const RequestLayout());
  }

  Future<void> runAction(DeckAction action) async {
    _append(action.label, inbound: false);
    notifyListeners();
    await _send(RunAction(action: action));
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
    _cancelReconnect();
    _lifecycle?.dispose();
    _iconTimeout?.cancel();
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
