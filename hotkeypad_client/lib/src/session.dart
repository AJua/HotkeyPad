import 'dart:async';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
// Flutter's ConnectionState (StreamBuilder) collides with the BLE one.
import 'package:flutter/widgets.dart' hide ConnectionState;

import 'dart:typed_data';

import 'client_identity.dart';
import 'deck_store.dart';
import 'device_info.dart';
import 'host_history_store.dart';
import 'icon_cache.dart';
import 'link_target.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Where the link is in the connect -> discover -> subscribe sequence.
enum LinkStage {
  connecting('Connecting'),
  discovering('Discovering services'),
  subscribing('Subscribing'),

  /// WiFi only: the host does not recognize this install yet and is
  /// waiting on [HotkeyPadSession.submitPin] — see [RequestPin]. Bluetooth
  /// never enters this stage.
  awaitingPin('Enter the code shown on the host'),
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

/// What the icon-fetch queue should send next, given its current state —
/// pulled out of [HotkeyPadSession._drainIconQueue] as a pure function purely
/// so the priority rule can be tested without a real BLE link: every
/// ordinary icon in [queue] is always sent before [pendingBackground],
/// regardless of which was asked for first, since a background image can
/// be a hundred times an icon's size and must never make the deck's own
/// buttons wait behind it. Null means there is nothing to fetch right now.
({String name, bool lowPriority})? nextIconFetch({
  required List<String> queue,
  required String? pendingBackground,
}) {
  if (queue.isNotEmpty) return (name: queue.first, lowPriority: false);
  if (pendingBackground != null) {
    return (name: pendingBackground, lowPriority: true);
  }
  return null;
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
class HotkeyPadSession extends ChangeNotifier {
  HotkeyPadSession({required this.target, required this.name});

  final LinkTarget target;
  final String name;

  final _central = CentralManager();
  final _subscriptions = <StreamSubscription>[];

  LinkStage _stage = LinkStage.connecting;
  String? _error;

  /// Set only after a wrong [PinResult] arrives during [LinkStage.awaitingPin]
  /// — cleared by the next [RequestPin] (a fresh attempt) or a successful
  /// [PinResult].
  String? _pinError;
  GATTCharacteristic? _notifyCharacteristic;
  GATTCharacteristic? _writeCharacteristic;

  /// The WiFi transport's equivalent of [_notifyCharacteristic]/
  /// [_writeCharacteristic] together — a bare socket carries both
  /// directions, so there is only one of these rather than two.
  Socket? _wifiSocket;
  StreamSubscription<Uint8List>? _wifiSubscription;

  /// The grid the host sent. Cached locally so the deck draws immediately
  /// on open rather than after the link comes up.
  /// The appearance the host asked for. Cached alongside the layout so the
  /// first frame after a restart is already the right one.
  DeckTheme _theme = DeckTheme.system;

  /// Labels off means icons alone, with square cells the icon fills.
  bool _showLabels = true;
  bool _showAppBar = true;
  bool _showPageDots = true;

  /// Names an image behind the deck's button grid — fetched the same way an
  /// app icon is (see [ensureIcon]), null meaning no custom background.
  String? _backgroundImageId;
  double _backgroundOpacity = 1.0;
  BackgroundFit _backgroundFit = BackgroundFit.cover;

  /// Notified when the host changes the appearance.
  ValueChanged<DeckTheme>? onTheme;

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

  /// The orientation last sent to the host, so a rebuild does not resend
  /// one it already knows — see [reportOrientation].
  bool? _reportedPortrait;
  final _iconQueue = <String>[];

  /// The background image, held separately from [_iconQueue] rather than
  /// appended to it: a background can be a hundred times the size of an
  /// app icon, and must never make the deck's own buttons wait behind it.
  /// Only drawn from once [_iconQueue] is empty — see [_drainIconQueue].
  String? _pendingBackgroundFetch;

  /// The name and priority of whichever fetch [_drainIconQueue] currently
  /// has outstanding, so a retry (see [_finishIconFetch]) can re-queue it
  /// at the same priority it started at instead of always promoting it.
  ({String name, bool lowPriority})? _fetching;
  bool _loadingApps = false;
  final _log = <LinkMessage>[];
  int? _mtu;
  String? _lastAck;

  /// The button waiting on an ack, and the outcome of the last one.
  ///
  /// Acks carry no correlation id, so this assumes one press is outstanding
  /// at a time — true of a finger on a deck. A second press before the first
  /// answers simply takes over the slot.
  String? _pressing;
  String? _feedbackFor;
  bool? _feedbackOk;
  Timer? _feedbackTimer;

  Timer? _reconnectTimer;
  Timer? _countdownTimer;
  int _reconnectAttempt = 0;
  int? _reconnectIn;
  AppLifecycleListener? _lifecycle;

  LinkStage get stage => _stage;
  String? get error => _error;
  String? get pinError => _pinError;
  bool get ready => _stage == LinkStage.ready;
  List<DeckApp> get apps => List.unmodifiable(_apps);
  DeckTheme get theme => _theme;
  bool get showLabels => _showLabels;

  bool get showAppBar => _showAppBar;
  bool get showPageDots => _showPageDots;
  DeckLayout? get layout => _layout;

  /// Null when the host has no custom background set, or its bytes have
  /// not arrived yet — either way the deck falls back to its ordinary
  /// theme-derived background.
  Uint8List? get backgroundImage =>
      _backgroundImageId == null ? null : _icons[_backgroundImageId];
  double get backgroundOpacity => _backgroundOpacity;
  BackgroundFit get backgroundFit => _backgroundFit;

  /// True while this button's command is in flight.
  bool isPressing(DeckItem item) => _pressing == item.stored;

  /// The outcome of this button's last command, briefly, or null.
  bool? feedbackFor(DeckItem item) =>
      _feedbackFor == item.stored ? _feedbackOk : null;
  bool get loadingLayout => _loadingLayout;
  Uint8List? iconFor(String appName) => _icons[appName];

  /// True while the host is actively pushing something — a fresh layout,
  /// or an icon/background image the deck doesn't have cached yet — so
  /// the deck can show a quiet "syncing" hint rather than an update
  /// (a moved button, a new background) just silently appearing with no
  /// feedback that anything happened. Deliberately not the same as
  /// [loadingLayout] alone: a background image change arrives as its own
  /// [SetAppearance] message once the layout has already finished
  /// loading, and is fetched the same way an icon is (see [ensureIcon]).
  bool get isSyncing => _loadingLayout || _fetching != null;

  /// Identifies this host's layout in storage.
  /// BLE keeps today's bare peripheral uuid, unprefixed — changing its
  /// shape would silently orphan every existing user's cached layout and
  /// icons. WiFi has no such history, so it gets its own namespace: the
  /// two transports share no identity, so the same Mac reached over
  /// either one is (harmlessly) cached twice.
  String get hostId => switch (target) {
    BleTarget(:final peripheral) => peripheral.uuid.toString(),
    WifiTarget(:final hostId) => 'wifi:$hostId',
  };
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

    // WiFi needs neither of these: a dropped socket reports itself
    // directly via its own onDone/onError (see _connectWifi), scoped to
    // this one connection, unlike CentralManager's streams which are a
    // process-wide singleton every session must filter by uuid itself.
    if (target case BleTarget(:final peripheral)) {
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
          if (event.characteristic.uuid != HotkeyPad.notifyCharacteristicUuid) {
            return;
          }
          _receive(event.value);
        }),
      );
    }

    connect();
  }

  void _receive(List<int> bytes) {
    if (IconFrame.looksLikeFrame(bytes)) {
      _receiveIconFrame(bytes);
      return;
    }
    final message = HotkeyPadMessage.decode(bytes);
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
        _settlePress(ok);
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
          _append(
            'layout: ${incoming.columns}x${incoming.rows}',
            inbound: true,
          );
        }
      case SetAppearance(
        :final theme,
        :final showLabels,
        :final showAppBar,
        :final showPageDots,
        :final backgroundImageId,
        :final backgroundOpacity,
        :final backgroundFit,
      ):
        _theme = theme;
        _showLabels = showLabels;
        _showAppBar = showAppBar;
        _showPageDots = showPageDots;
        _backgroundImageId = backgroundImageId;
        _backgroundOpacity = backgroundOpacity;
        _backgroundFit = backgroundFit;
        unawaited(
          DeckStore.saveAppearance(
            hostId,
            theme,
            showLabels,
            showAppBar: showAppBar,
            showPageDots: showPageDots,
            backgroundImageId: backgroundImageId,
            backgroundOpacity: backgroundOpacity,
            backgroundFit: backgroundFit,
          ),
        );
        if (backgroundImageId != null) {
          unawaited(ensureIcon(backgroundImageId, lowPriority: true));
        }
        onTheme?.call(theme);
        _append(
          'appearance: ${theme.label.toLowerCase()}, '
          'labels ${showLabels ? 'on' : 'off'}',
          inbound: true,
        );
      case IconUnavailable(:final name):
        _append('no icon for $name', inbound: true);
        _finishIconFetch(name);
      case RequestPin():
        _stage = LinkStage.awaitingPin;
        _pinError = null;
        _append('host asked for a pairing PIN', inbound: true);
      case PinResult(:final ok):
        if (ok) {
          _stage = LinkStage.ready;
          _pinError = null;
          _recordWifiHistory();
          _append('PIN accepted', inbound: true);
          // Whatever this session's own connect() sent right after Hello
          // was ignored by the host while this connection was still
          // unrecognized — ask again now that it is trusted.
          unawaited(requestLayout());
        } else {
          _pinError = 'Incorrect PIN';
          _append('PIN rejected', inbound: true);
          // The host closes the connection shortly; the existing
          // reconnect flow (a fresh attempt, a fresh PIN) takes it from
          // here rather than this offering its own retry path.
        }
      case Hello() ||
          SetOrientation() ||
          ListApps() ||
          PressSlot() ||
          RequestIcon() ||
          RequestLayout() ||
          SubmitPin():
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

  /// Tells the host this device's current orientation, so its own editor
  /// can show the grid turned the same way — a no-op once the host already
  /// knows it, so this is cheap to call from every build.
  Future<void> reportOrientation(bool portrait) async {
    if (_reportedPortrait == portrait) return;
    _reportedPortrait = portrait;
    await _send(SetOrientation(portrait: portrait));
  }

  /// Fetches [appName]'s icon if it is not already known, preferring the disk
  /// cache. Requests are queued one at a time so a deck full of new buttons
  /// does not flood the notification queue.
  ///
  /// [lowPriority] is for the background image alone: it is fetched only
  /// once every ordinary icon already queued has had its turn (see
  /// [_pendingBackgroundFetch]), so a background that is a hundred times an
  /// icon's size — or simply slow to arrive — can never make the deck's own
  /// buttons wait behind it.
  Future<void> ensureIcon(String appName, {bool lowPriority = false}) async {
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

    if (lowPriority) {
      _pendingBackgroundFetch = appName;
    } else {
      _iconQueue.add(appName);
    }
    unawaited(_drainIconQueue());
  }

  /// Retries every deck icon that never arrived.
  ///
  /// A timed-out fetch already retries itself (see [_finishIconFetch]), but
  /// only after its own 10-second wait; pulling to refresh is the
  /// impatient — or manual — way to ask again right away rather than
  /// living with a fallback glyph until it comes back around on its own.
  Future<void> refreshIcons() async {
    final layout = _layout;
    if (layout == null) return;
    final missing = <String>{
      for (final slot in layout.slots)
        if (slot != null)
          if (DeckItem.parse(slot.value) case AppItem(:final name))
            if (!_icons.containsKey(name)) name,
    };
    // Clear the "already asked" guard first so ensureIcon does not just see
    // itself as already having tried and skip straight past.
    missing.forEach(_requestedIcons.remove);
    for (final name in missing) {
      unawaited(ensureIcon(name));
    }
    // The background isn't a layout slot, so it needs its own "never
    // arrived" check alongside the loop above.
    final backgroundId = _backgroundImageId;
    if (backgroundId != null && !_icons.containsKey(backgroundId)) {
      _requestedIcons.remove(backgroundId);
      unawaited(ensureIcon(backgroundId, lowPriority: true));
    }
  }

  Future<void> _drainIconQueue() async {
    // The catalogue comes first. Icons are large and many; interleaving them
    // with ~100 catalogue notifications would leave the deck without labels
    // for far longer than it leaves it without pictures.
    if (_loadingApps) return;
    if (_fetching != null || !ready) return;
    final next = nextIconFetch(
      queue: _iconQueue,
      pendingBackground: _pendingBackgroundFetch,
    );
    if (next == null) return;
    final appName = next.name;
    if (next.lowPriority) {
      _pendingBackgroundFetch = null;
    } else {
      _iconQueue.removeAt(0);
    }
    _fetching = next;
    // Only reason this needs its own notify: nothing else in this call
    // path changes anything else the UI reads (see isSyncing), so without
    // it the badge would wait for some unrelated rebuild to catch up.
    notifyListeners();
    await _send(RequestIcon(name: appName));
    // The host answers with frames; _finishIconFetch releases the queue. A
    // host that never answers must not wedge it, hence the timeout.
    _iconTimeout = Timer(const Duration(seconds: 10), () {
      _finishIconFetch(appName, retryable: true);
    });
  }

  Timer? _iconTimeout;

  /// Ends whichever fetch is outstanding for [appName].
  ///
  /// [retryable] is only true when the 10-second timeout is what ended it
  /// — the host may simply still be busy (a large background image can
  /// take far longer than any app icon), not permanently unable to answer,
  /// so unlike [IconUnavailable] or a completed transfer this asks for it
  /// again rather than giving up on it for the rest of the session; see
  /// [refreshIcons] for the manual, immediate equivalent.
  void _finishIconFetch(String appName, {bool retryable = false}) {
    _iconTimeout?.cancel();
    _iconTimeout = null;
    final lowPriority = _fetching?.lowPriority ?? false;
    _fetching = null;
    if (retryable) {
      _requestedIcons.remove(appName);
      unawaited(ensureIcon(appName, lowPriority: lowPriority));
    } else {
      unawaited(_drainIconQueue());
    }
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

  /// Distinguishes connection attempts so a superseded one cannot report
  /// back. A timed-out attempt is abandoned, not cancelled — CoreBluetooth
  /// keeps working on it — so without this an old attempt could later
  /// declare itself ready over a newer one.
  int _attempt = 0;

  /// Long enough for a slow link, short enough that a host which never comes
  /// back does not strand the deck.
  static const _connectTimeout = Duration(seconds: 20);

  Future<void> connect() async {
    final attempt = ++_attempt;
    final reconnecting =
        _stage == LinkStage.disconnected || _stage == LinkStage.failed;
    _cancelReconnect();
    _stage = LinkStage.connecting;
    _error = null;
    _pinError = null;
    // A drop mid-catalogue leaves this set; clear it so the retry can ask.
    _loadingApps = false;
    // A fresh link is a host that knows nothing about this device yet,
    // even if the last one was told — reportOrientation's own "already
    // sent" guard must not skip announcing it again on the new link.
    _reportedPortrait = null;
    notifyListeners();
    try {
      switch (target) {
        case BleTarget(:final peripheral):
          await _connectBle(peripheral, reconnecting: reconnecting);
        case WifiTarget(:final address, :final port):
          await _connectWifi(address, port, attempt: attempt);
      }

      if (attempt != _attempt) return;
      _stage = LinkStage.ready;
      _reconnectAttempt = 0;
      _recordWifiHistory();
      notifyListeners();

      // So the host can tell this device apart from any other connected at
      // the same time — see its device lock. clientId is what a WiFi
      // host's PIN-pairing remembers across reconnects; see RequestPin.
      await _send(
        Hello(
          name: await DeviceInfo.name(),
          clientId: await ClientIdentity.id(),
        ),
      );
      await requestLayout();
    } catch (error) {
      // A newer attempt owns the state now; this one just goes quiet.
      if (attempt != _attempt) return;
      _stage = LinkStage.failed;
      _error = '$error';
      _append('connect failed: $error', inbound: true);
      notifyListeners();
      // A device that does not speak HotkeyPad will not start doing so; only
      // transient failures are worth retrying. A timeout is transient.
      if (error is! StateError) _scheduleReconnect();
    }
  }

  /// Remembers a WiFi host reached over TCP, so a future manual reconnect
  /// on a network discovery can't cross (AP client isolation, a different
  /// subnet) is a tap instead of retyping an IP.
  ///
  /// Recorded as soon as the TCP handshake and protocol round-trip prove
  /// this is a real HotkeyPad host — the same point [LinkStage.ready] is
  /// reached from either path (never needing a PIN, or a PIN just
  /// accepted). A host that goes on to demand a PIN the user then cancels
  /// still gets remembered: it's still demonstrably a real host at this
  /// address, which is exactly what a "connect again" shortcut needs to
  /// know, independent of the host's own trust decision. [upsertHistory]
  /// makes the second call site's re-record after a PIN a harmless no-op
  /// beyond refreshing the timestamp.
  void _recordWifiHistory() {
    final target = this.target;
    if (target is! WifiTarget) return;
    unawaited(
      HostHistoryStore.recordConnected(
        hostId: target.hostId,
        address: target.address,
        port: target.port,
        name: name,
      ),
    );
  }

  Future<void> _connectBle(
    Peripheral peripheral, {
    required bool reconnecting,
  }) async {
    // The whole sequence is bounded, not just one step of it. iOS never
    // gives up on a connect: CoreBluetooth waits indefinitely for a
    // peripheral to reappear, so a host restarted at the wrong moment
    // leaves connect() hanging forever. Since connect() has already
    // cancelled the backoff, nothing would ever retry — the deck simply
    // stops reconnecting. Android's GATT layer times out on its own,
    // which is why this only ever showed up on iPhone.
    // Reconnecting straight after a drop fails on Android with
    // "Write descriptor failed with status: 1" (GATT_INVALID_HANDLE): the
    // stack is still tearing the old link down when the new descriptor
    // write arrives. Close it explicitly and give the stack a moment.
    if (reconnecting) {
      try {
        await _central.disconnect(peripheral).timeout(_connectTimeout);
      } catch (_) {
        // Already gone is the expected case here.
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    // Scanning while connecting slows the connection down and on some
    // platforms blocks it outright.
    await _central.stopDiscovery();
    await _central.connect(peripheral).timeout(_connectTimeout);

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

    final services = await _central
        .discoverGATT(peripheral)
        .timeout(_connectTimeout);
    final service = services
        .where((s) => s.uuid == HotkeyPad.serviceUuid)
        .firstOrNull;
    if (service == null) {
      throw StateError(
        'This device does not expose the HotkeyPad service '
        '(${HotkeyPad.serviceUuid}).',
      );
    }

    final notify = service.characteristics
        .where((c) => c.uuid == HotkeyPad.notifyCharacteristicUuid)
        .firstOrNull;
    final write = service.characteristics
        .where((c) => c.uuid == HotkeyPad.writeCharacteristicUuid)
        .firstOrNull;
    if (notify == null || write == null) {
      throw StateError(
        'The HotkeyPad service is missing its notify or write characteristic.',
      );
    }

    _stage = LinkStage.subscribing;
    _notifyCharacteristic = notify;
    _writeCharacteristic = write;
    notifyListeners();

    await _central
        .setCharacteristicNotifyState(peripheral, notify, state: true)
        .timeout(_connectTimeout);
  }

  /// WiFi's whole connect sequence in one step — there is no service
  /// discovery or subscribe handshake the way BLE has; a TCP connection is
  /// either open or it isn't.
  Future<void> _connectWifi(
    String address,
    int port, {
    required int attempt,
  }) async {
    _stage = LinkStage.discovering;
    notifyListeners();

    // A reconnect must not leave the previous attempt's socket dangling.
    await _wifiSocket?.close();
    final socket = await Socket.connect(address, port).timeout(_connectTimeout);
    if (attempt != _attempt) {
      // A newer attempt already started while this one was still
      // connecting — same "abandoned, not cancelled" situation _connectBle
      // guards against with its own attempt check up in connect().
      unawaited(socket.close());
      return;
    }

    _wifiSocket = socket;
    final reassembler = FrameReassembler();
    _wifiSubscription = socket.listen(
      (chunk) {
        for (final frame in reassembler.add(chunk)) {
          _receive(frame);
        }
      },
      onDone: () => _onWifiClosed(attempt),
      onError: (_) => _onWifiClosed(attempt),
      cancelOnError: true,
    );

    _stage = LinkStage.subscribing;
    notifyListeners();
  }

  /// The WiFi equivalent of the BLE `connectionStateChanged` handling in
  /// [start] — unlike that process-wide stream, a socket's own onDone/
  /// onError is already scoped to this one connection, so there is no uuid
  /// filtering to do here.
  void _onWifiClosed(int attempt) {
    if (attempt != _attempt) return;
    if (_stage == LinkStage.disconnected || _stage == LinkStage.failed) {
      return;
    }
    _stage = LinkStage.disconnected;
    _wifiSocket = null;
    _wifiSubscription = null;
    notifyListeners();
    _scheduleReconnect();
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
    final cached = await DeckStore.loadAppearance(hostId);
    _showLabels = cached.showLabels;
    _showAppBar = cached.showAppBar;
    _showPageDots = cached.showPageDots;
    _backgroundImageId = cached.backgroundImageId;
    _backgroundOpacity = cached.backgroundOpacity;
    _backgroundFit = cached.backgroundFit;
    if (cached.theme != _theme) {
      _theme = cached.theme;
      onTheme?.call(cached.theme);
    }
    // Prefer the disk-cached bytes so the background is already there on
    // the first frame; ensureIcon only reaches for the link when the cache
    // misses.
    final backgroundId = _backgroundImageId;
    if (backgroundId != null) {
      unawaited(ensureIcon(backgroundId, lowPriority: true));
    }
    final cachedLayout = await DeckStore.load(hostId);
    if (cachedLayout == null || _layout != null) return;
    _layout = cachedLayout;
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

  /// Answers a [RequestPin] — see [LinkStage.awaitingPin]. Whether it was
  /// right or wrong arrives later as a [PinResult].
  Future<void> submitPin(String pin) async {
    if (_stage != LinkStage.awaitingPin) return;
    await _send(SubmitPin(pin: pin));
  }

  /// Reports which slot was pressed and tracks it for feedback.
  ///
  /// The id, not the contents: the host looks the slot up in its own
  /// layout, so a button holding a shell command cannot be conjured from
  /// this end of the link.
  Future<void> press(int id, DeckItem item) async {
    _feedbackTimer?.cancel();
    _feedbackFor = null;
    _feedbackOk = null;
    _pressing = item.stored;
    _append(item.label, inbound: false);
    notifyListeners();

    await _send(PressSlot(id: id));

    // A host that never answers must not leave the button spinning.
    _feedbackTimer = Timer(const Duration(seconds: 12), () {
      if (_pressing != null) _settlePress(false);
    });
  }

  void _settlePress(bool ok) {
    final pressed = _pressing;
    if (pressed == null) return;
    _feedbackTimer?.cancel();
    _pressing = null;
    _feedbackFor = pressed;
    _feedbackOk = ok;
    notifyListeners();
    // Long enough to notice, short enough not to linger on the button.
    _feedbackTimer = Timer(const Duration(milliseconds: 1400), () {
      _feedbackFor = null;
      _feedbackOk = null;
      notifyListeners();
    });
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

  Future<void> sendDebugText(String text) async {
    _append(text, inbound: false);
    notifyListeners();
    await _send(DebugText(text: text));
  }

  Future<void> _send(HotkeyPadMessage message) async {
    try {
      switch (target) {
        case BleTarget(:final peripheral):
          final characteristic = _writeCharacteristic;
          if (characteristic == null) return;
          await _central.writeCharacteristic(
            peripheral,
            characteristic,
            value: message.encode(),
            type: GATTCharacteristicWriteType.withResponse,
          );
        case WifiTarget():
          final socket = _wifiSocket;
          if (socket == null) return;
          socket.add(FrameCodec.encode(message.encode()));
          await socket.flush();
      }
    } catch (error) {
      _append('send failed: $error', inbound: true);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
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
      switch (target) {
        case BleTarget(:final peripheral):
          final notify = _notifyCharacteristic;
          if (notify != null && _stage == LinkStage.ready) {
            await _central.setCharacteristicNotifyState(
              peripheral,
              notify,
              state: false,
            );
          }
          await _central.disconnect(peripheral);
        case WifiTarget():
          await _wifiSubscription?.cancel();
          await _wifiSocket?.close();
      }
    } catch (_) {
      // Tearing down a link that is already gone is not worth reporting.
    }
  }
}
