import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
// Flutter's own ConnectionState (used by StreamBuilder) collides with the BLE one.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import 'app_launcher.dart';
import 'background_image_store.dart';
import 'client_trust_store.dart';
import 'command_runner.dart';
import 'custom_icon_store.dart';
import 'glyph_icon_store.dart';
import 'host_identity.dart';
import 'layout_page.dart';
import 'layout_store.dart';
import 'locale_store.dart';
import 'media_control.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'settings_store.dart';
import 'unsupported_page.dart';
import 'update_checker.dart';
import 'update_store.dart';
import 'wifi_server.dart';

/// What running one action came to — every `AppLauncher.open`-style helper
/// already returns this shape, so a combo step and a top-level press report
/// the same way.
typedef ActionResult = ({bool ok, String message});

/// Runs [steps] in order, waiting each step's declared delay first, and
/// stopping at the first failure rather than plowing through the rest of a
/// broken sequence.
///
/// [run] and [delay] are injected — normally [_HostPageState._runItem] and
/// `Future.delayed` — so this can be tested without touching
/// AppLauncher/CommandRunner or waiting on a real clock.
Future<ActionResult> runComboSteps(
  List<ComboStep> steps, {
  required Future<ActionResult> Function(DeckItem item) run,
  required Future<void> Function(Duration duration) delay,
}) async {
  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    if (step.delayMs > 0) {
      await delay(Duration(milliseconds: step.delayMs));
    }
    final result = await run(step.action);
    if (!result.ok) {
      return (ok: false, message: 'Step ${index + 1}: ${result.message}');
    }
  }
  return (ok: true, message: 'Ran ${steps.length} steps');
}

/// Whether a press from [clientId] should actually run.
///
/// There is no "accept anyone" state: a null [lockedClientId] means no
/// device has been picked yet (nothing connected, or more than one
/// candidate and the host has not chosen between them — see
/// [_HostPageState._autoLockIfSingleClient]), and every press is rejected
/// until it is one specific device's turn.
///
/// A pure function of the two ids specifically so it can be tested without
/// a real transport — the same reason [runComboSteps] takes its
/// dependencies as parameters instead of reaching for them itself. The id
/// itself is transport-agnostic (a BLE central's uuid or a WiFi client's
/// `wifi:address:port`), so first-connected-wins already applies across
/// both without this needing to know which is which.
bool isPressAllowed({
  required String clientId,
  required String? lockedClientId,
}) => lockedClientId == clientId;

/// What the device lock should become after the connected-client list
/// changes.
///
/// An existing explicit choice is always kept, even once it stops being
/// the only client — picking a device is a deliberate act the client list
/// changing should not undo. The one case this fills in on its own is
/// exactly one connected client with nothing chosen yet: that client is
/// unambiguously "the" device, so a single-phone setup — the common case —
/// never needs an explicit pick. Zero or two-or-more candidates with
/// nothing chosen stays unpicked; see [isPressAllowed].
String? nextLockedClientId({
  required String? currentLockedClientId,
  required List<String> connectedClientIds,
}) {
  if (currentLockedClientId != null) return currentLockedClientId;
  return connectedClientIds.length == 1 ? connectedClientIds.single : null;
}

/// Whether an incoming message from a not-yet-trusted BLE central should
/// be dropped outright, without even looking at whether it is a fresh
/// [Hello] — pulled out of [_HostPageState._routeMessage] for the same
/// reason [isPressAllowed] is its own function.
///
/// True only once this central has already used its one PIN attempt (or
/// was blocked outright) on this very connection — see
/// [_HostPageState._rejectBleCentral]'s own doc comment for why that
/// central cannot simply be disconnected and made to reconnect for a
/// fresh one on most platforms. WiFi never reaches this check: a rejected
/// WiFi socket is actually closed, so there is no later message from it
/// to drop.
bool bleAttemptExhausted({
  required LinkTransport transport,
  required bool alreadyRejected,
}) => transport == LinkTransport.bluetooth && alreadyRejected;

/// What a client should count as subscribed the moment it is first
/// touched into `_clients` — pulled out of [_HostPageState._onHello]/
/// [_HostPageState._verifyPin] for the same reason [isPressAllowed] is
/// its own function.
///
/// Always true for WiFi: a raw socket has no subscribe step of its own,
/// so it always receives whatever is sent once it is trusted (see the
/// long-form comment this replaced, still worth reading in git history).
/// For BLE, whatever [bleSubscribed] says — a real GATT subscribe/
/// unsubscribe the central may well have already done before trust was
/// even decided, since a client's own connect sequence subscribes before
/// it ever sends [Hello].
bool? initialSubscribedFor({
  required LinkTransport transport,
  required bool? bleSubscribed,
}) => transport == LinkTransport.wifi ? true : bleSubscribed;

/// Everything needed to identify a client and talk to it, before it has
/// necessarily been seen — passed into [_HostPageState._touch] and
/// [_HostPageState._pressSlot], which create a [ConnectedClient] entry on
/// first use rather than requiring one to already exist. Bundled together
/// (rather than four separate parameters everywhere) since a caller always
/// has all four at once: a BLE `Central` or a [WifiClient] each map to
/// exactly one of these.
typedef ClientSource = ({
  String id,
  LinkTransport transport,
  Future<void> Function(Uint8List bytes) send,
  Future<int> Function() maxFrameSize,
});

/// A connection waiting on its [SubmitPin] — see
/// [_HostPageState._pendingPins]. Transport-agnostic: a WiFi socket and a
/// BLE central both reach this exact shape once an unrecognized [Hello]
/// arrives (see [_HostPageState._onHello]), so there is one PIN flow, not
/// one per transport.
typedef _PendingPin = ({
  ClientSource source,
  String pin,
  String clientId,
  String? name,

  /// Ends this connection on a wrong PIN or a blocked client, however
  /// that's actually done on this source's transport — see
  /// [_HostPageState._rejectBleCentral]'s own doc comment for why that is
  /// not a real disconnect on every platform.
  Future<void> Function() reject,
});

/// A client that the host has seen. A BLE central is only reported to us
/// when it does something — connect, subscribe, read or write — so the
/// list grows as clients interact rather than the moment they come into
/// range; a WiFi client is reported the moment its TCP connection is
/// accepted, since there is no equivalent "in range but not yet talking"
/// state for a socket.
class ConnectedClient {
  ConnectedClient({
    required this.id,
    required this.transport,
    required this.send,
    required this.maxFrameSize,
    required this.since,
    required this.subscribed,
    required this.lastActivity,
    this.name,
    this.portrait,
  });

  final String id;
  final LinkTransport transport;

  /// Sends already-encoded bytes to this client over whichever transport
  /// it connected with — a BLE notify or a WiFi socket write, hidden
  /// behind one shape (see [_HostPageState._send]/`_sendIcon`) so neither
  /// needs to know which transport it is talking to.
  final Future<void> Function(Uint8List bytes) send;

  /// The largest single frame this client can currently receive — a BLE
  /// central's negotiated MTU (queried fresh each time, since a
  /// reconnect can change it) or a large fixed constant for WiFi, which
  /// has no equivalent limit. Drives both the plain drop-if-too-big check
  /// in `_send` and the icon-chunking capacity in `_sendIcon`.
  final Future<int> Function() maxFrameSize;

  final DateTime since;
  final bool subscribed;
  final String lastActivity;

  /// The device's own name, from its [Hello] — null until that arrives,
  /// which is briefly true for every client right after it connects.
  final String? name;

  /// This device's current orientation, from its [SetOrientation] — null
  /// until the first one arrives, same as [name].
  final bool? portrait;

  ConnectedClient copyWith({
    bool? subscribed,
    String? lastActivity,
    String? name,
    bool? portrait,
  }) {
    return ConnectedClient(
      id: id,
      transport: transport,
      send: send,
      maxFrameSize: maxFrameSize,
      since: since,
      subscribed: subscribed ?? this.subscribed,
      lastActivity: lastActivity ?? this.lastActivity,
      name: name ?? this.name,
      portrait: portrait ?? this.portrait,
    );
  }
}

class HostPage extends StatefulWidget {
  const HostPage({
    super.key,
    required this.onThemeChanged,
    required this.locale,
    required this.onLocale,
  });

  /// Lets the app above re-dress itself when the theme is changed here.
  final ValueChanged<DeckTheme> onThemeChanged;

  /// The user's own manually-picked language, if any — see
  /// [LocaleStore]'s doc comment. Threaded down rather than read fresh
  /// from the store wherever it's needed, so the language-picker button
  /// and [MaterialApp] always agree on what's currently selected.
  final Locale? locale;
  final ValueChanged<Locale?> onLocale;

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  PeripheralManager? _peripheral;
  Object? _initError;

  /// Lets the app bar's gear button reach into [LayoutPage], which owns the
  /// settings dialog and the state it edits.
  final _layoutPageKey = GlobalKey<LayoutPageState>();

  final _wifiServer = WifiServer();

  /// WiFi has no MTU negotiation the way BLE does — a TCP write simply
  /// carries however many bytes it is given — so this is not a hardware
  /// limit, just a generous cap far above any real message (the catalogue
  /// and layout are small JSON; even an unprocessed background photo
  /// downscaled by `BackgroundImageStore` tops out in the low megabytes),
  /// kept mainly so `_send`'s "message too big" guard means something for
  /// this transport too rather than never firing at all.
  static const _wifiMaxFrameSize = 8 * 1024 * 1024;

  String? _wifiError;

  /// Shown in the status card so a client that cannot discover the host
  /// automatically (AP client isolation, an emulator's isolated network)
  /// has something to type into its own manual-entry field. Fetched once
  /// when WiFi starts rather than on every build — interfaces essentially
  /// never change mid-run, same reasoning as [WifiServer]'s own
  /// broadcast-target list.
  List<String> _localAddresses = [];

  /// This Mac's own persistent id — see [HostIdentity] — cached from
  /// [_startWifi] so the QR-pairing card can use it without an async gap
  /// of its own every time it builds.
  String? _hostId;

  /// Every client id the host has ever decided about, on either transport —
  /// loaded once at startup, kept in memory, and written through to
  /// [ClientTrustStore] on every decision so it never falls out of sync
  /// with the file. See [trustFor]/[_routeMessage].
  var _trust = <String, bool>{};

  /// A connection mid PIN challenge, keyed by [ClientSource.id] — the
  /// [SubmitPin] this is waiting on has nowhere else to be routed to yet,
  /// since [_clients] does not get an entry for it until the PIN is right.
  final _pendingPins = <String, _PendingPin>{};

  /// Whether a BLE central has subscribed to notifications, keyed by its
  /// central uuid — tracked independently of [_clients] because a client's
  /// own connect sequence subscribes before it ever sends [Hello] (see
  /// `HotkeyPadSession._connectBle`), so this often has to be read back
  /// later, once [_onHello]/[_verifyPin] decide the central is trusted and
  /// actually create its [ConnectedClient] entry.
  final _bleSubscribed = <String, bool>{};

  /// BLE central uuids that have already used their one PIN attempt on
  /// this connection and failed, or were blocked outright — see
  /// [_rejectBleCentral]. Checked by [_routeMessage] so a central that
  /// cannot actually be disconnected does not just send a fresh [Hello]
  /// and get another guess on the same link.
  final _bleRejected = <String>{};

  final _clients = <String, ConnectedClient>{};
  final _log = <String>[];
  final _composer = TextEditingController();
  final _subscriptions = <StreamSubscription>[];

  /// When set, only this client's presses are run — see [isPressAllowed].
  /// Null means any connected client is accepted, which is also what a
  /// single-client setup normally looks like.
  String? _lockedClientId;

  BluetoothLowEnergyState _state = BluetoothLowEnergyState.unknown;
  bool _advertising = false;
  bool _busy = false;
  bool _autoStarted = false;

  /// The service view is a detour from the deck, reached from settings,
  /// rather than a tab competing with it for attention.
  bool _showingService = false;
  int _appCount = 0;

  /// Whether the media keys and key combinations can actually reach macOS.
  /// Re-checked when the window regains focus, since granting it happens in
  /// System Settings rather than here.
  bool _accessibility = true;

  /// Set once [_checkForUpdate] finds a release newer than this build and
  /// not already dismissed — see [_updateBanner]. Null the rest of the
  /// time, including while a check is still in flight.
  LatestRelease? _updateAvailable;

  /// App name -> bundle path, filled when the catalogue is built so an icon
  /// request does not have to rescan the disk.
  final _appPaths = <String, String>{};

  /// Serialises the multi-notification transfers. Two of them running at once
  /// would interleave their frames on one characteristic and stall both.
  Future<void> _transfers = Future<void>.value();

  /// Value served on the notify characteristic until real data flows.
  final _notifyCharacteristic = GATTCharacteristic.mutable(
    uuid: HotkeyPad.notifyCharacteristicUuid,
    properties: [
      GATTCharacteristicProperty.read,
      GATTCharacteristicProperty.notify,
    ],
    permissions: [GATTCharacteristicPermission.read],
    descriptors: [],
  );

  final _writeCharacteristic = GATTCharacteristic.mutable(
    uuid: HotkeyPad.writeCharacteristicUuid,
    properties: [
      GATTCharacteristicProperty.write,
      GATTCharacteristicProperty.writeWithoutResponse,
    ],
    permissions: [GATTCharacteristicPermission.write],
    descriptors: [],
  );

  @override
  void initState() {
    super.initState();
    _setUp();
    // Same reason as the client: on Android the advertise button would
    // otherwise be gated on a state only the permission can unlock.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_peripheral != null && _state != BluetoothLowEnergyState.poweredOn) {
        _ensureAuthorized();
      }
      _autoStart();
      _refreshAccessibility();
      _checkForUpdate();
    });
  }

  /// Brings the service up by itself once the adapter is ready, once per
  /// run. Stopping it manually is respected — this does not restart it.
  void _autoStart() {
    if (_autoStarted || _advertising || _busy) return;
    if (_state != BluetoothLowEnergyState.poweredOn) return;
    _autoStarted = true;
    _toggleAdvertising();
  }

  /// Best-effort, non-blocking check against GitHub Releases — see
  /// `UpdateChecker`'s doc comment for why a failure here is always
  /// silent. Reuses a cached result instead of hitting the network again
  /// when [shouldCheckNow] says the last real check is still fresh.
  Future<void> _checkForUpdate() async {
    final state = await UpdateStore.load();
    var latest = state.latest;
    if (shouldCheckNow(state.lastCheckedAt, DateTime.now())) {
      latest = await UpdateChecker.fetchLatest();
      await UpdateStore.recordCheck(DateTime.now(), latest);
    }
    if (latest == null || !mounted) return;
    final current = (await PackageInfo.fromPlatform()).version;
    if (!isNewerVersion(current, latest.version)) return;
    if (!shouldShowBanner(state.dismissedVersion, latest.version)) return;
    if (mounted) setState(() => _updateAvailable = latest);
  }

  Future<void> _dismissUpdate(LatestRelease release) async {
    await UpdateStore.dismiss(release.version);
    if (mounted) setState(() => _updateAvailable = null);
  }

  /// Entirely host-side — see [LocaleStore]'s doc comment on why this is
  /// never synced with the client's own language setting. Each option's
  /// own label is written in that language itself, not run through
  /// [AppLocalizations], so someone who can't read the app's *current*
  /// language can still recognize and pick their own — the one line in
  /// this sheet that *is* localized is "System default" itself, since
  /// that's a concept, not a language name.
  Future<void> _showLanguagePicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final current = widget.locale;
    Widget option(Locale? locale, String label) =>
        RadioListTile<Locale?>(value: locale, title: Text(label));
    final result = await showModalBottomSheet<({bool picked, Locale? locale})>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: RadioGroup<Locale?>(
          groupValue: current,
          onChanged: (value) =>
              Navigator.of(context).pop((picked: true, locale: value)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(null, l10n.systemDefaultLanguage),
              option(const Locale('en'), 'English'),
              option(
                const Locale.fromSubtags(
                  languageCode: 'zh',
                  scriptCode: 'Hant',
                ),
                '繁體中文',
              ),
              option(const Locale('ja'), '日本語'),
            ],
          ),
        ),
      ),
    );
    if (result != null && result.picked) widget.onLocale(result.locale);
  }

  Future<void> _refreshAccessibility() async {
    final trusted = await MediaControl.trusted;
    if (mounted && trusted != _accessibility) {
      setState(() => _accessibility = trusted);
    }
  }

  /// Returns whether the app may use Bluetooth. Only Android has a runtime
  /// permission to ask for; elsewhere authorization is implied.
  Future<bool> _ensureAuthorized() async {
    final peripheral = _peripheral;
    if (peripheral == null) return false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await peripheral.authorize();
    } catch (error) {
      _showMessage('$error');
      return false;
    }
  }

  void _setUp() {
    try {
      final peripheral = PeripheralManager();
      _peripheral = peripheral;
      _state = peripheral.state;

      _subscriptions.add(
        peripheral.stateChanged.listen((event) {
          if (!mounted) return;
          setState(() {
            _state = event.state;
            if (event.state != BluetoothLowEnergyState.poweredOn) {
              _advertising = false;
            }
          });
          _autoStart();
        }),
      );

      // Android reports connect/disconnect directly. Apple and the desktop
      // platforms do not, so the streams below are what keeps the list honest
      // there.
      _listenSafely(() => peripheral.connectionStateChanged, (
        CentralConnectionStateChangedEventArgs event,
      ) {
        if (event.state == ConnectionState.connected) {
          // Not touched into _clients here — a raw GATT connection is not
          // trust, only a correct PIN is (see _onHello/_routeMessage), the
          // same reasoning WiFi's own onConnected already followed below.
          if (mounted) {
            setState(
              () => _addLog(
                'BLE central connected — '
                '${_short(event.central.uuid.toString())}',
              ),
            );
          }
        } else {
          final id = event.central.uuid.toString();
          _pendingPins.remove(id);
          _bleSubscribed.remove(id);
          _bleRejected.remove(id);
          _remove(id, 'disconnected');
        }
      }, 'connection events');

      _listenSafely(() => peripheral.characteristicNotifyStateChanged, (
        GATTCharacteristicNotifyStateChangedEventArgs event,
      ) {
        final id = event.central.uuid.toString();
        // Recorded regardless of trust — see _bleSubscribed's own doc
        // comment for why the subscribe can arrive before there is a
        // _clients entry to update at all.
        _bleSubscribed[id] = event.state;
        if (_clients.containsKey(id)) {
          _touch(
            _bleSource(event.central),
            event.state ? 'subscribed' : 'unsubscribed',
            subscribed: event.state,
          );
        }
      }, 'subscription events');

      _listenSafely(() => peripheral.characteristicReadRequested, (
        GATTCharacteristicReadRequestedEventArgs event,
      ) async {
        // Bookkeeping only for a central already trusted in — touching an
        // unidentified one here would let a bare GATT read stand in for
        // the PIN challenge every write already goes through.
        if (_clients.containsKey(event.central.uuid.toString())) {
          _touch(_bleSource(event.central), 'read');
        }
        await peripheral.respondReadRequestWithValue(
          event.request,
          value: const Ack(ok: true, message: 'ready').encode(),
        );
      }, 'read requests');

      _listenSafely(() => peripheral.characteristicWriteRequested, (
        GATTCharacteristicWriteRequestedEventArgs event,
      ) async {
        // Respond first: the client is blocked on the ATT response, and
        // launching an app takes far longer than the ATT timeout allows.
        await peripheral.respondWriteRequest(event.request);
        _routeMessage(
          _bleSource(event.central),
          event.request.value,
          reject: () => _rejectBleCentral(event.central),
        );
      }, 'write requests');
    } catch (error) {
      // On web there is no `bluetooth_low_energy` platform implementation
      // at all — PeripheralManager() itself throws — but nothing else on
      // this page actually needs one: WiFi is a real, independent
      // transport, and every BLE-touching call below already checks
      // `_peripheral` for null first (see _startService's own comment).
      // Gating the whole page behind UnsupportedPage here would hide the
      // deck editor and settings from a browser entirely for no reason;
      // reserve that page for a real, unexpected failure on a platform
      // that is supposed to have Bluetooth.
      if (kIsWeb) {
        _peripheral = null;
      } else {
        _initError = error;
      }
    }
  }

  /// Wraps a BLE `Central` as the transport-agnostic shape [_touch] and
  /// [_handleCommand] actually work with — see [ClientSource].
  ClientSource _bleSource(Central central) => (
    id: central.uuid.toString(),
    transport: LinkTransport.bluetooth,
    send: (bytes) => _peripheral!.notifyCharacteristic(
      central,
      _notifyCharacteristic,
      value: bytes,
    ),
    maxFrameSize: () => _peripheral!.getMaximumNotifyLength(central),
  );

  /// The WiFi counterpart of [_bleSource] — a [WifiClient] already carries
  /// everything [ClientSource] needs, so this only supplies the constant
  /// frame-size cap BLE gets from MTU negotiation instead.
  ClientSource _wifiSource(WifiClient client) => (
    id: client.id,
    transport: LinkTransport.wifi,
    send: client.send,
    maxFrameSize: () async => _wifiMaxFrameSize,
  );

  Future<void> _startWifi() async {
    try {
      _trust = await ClientTrustStore.load();
      final hostId = await HostIdentity.id();
      await _wifiServer.start(
        hostId: hostId,
        hostName: Platform.localHostname,
        // Not touched into _clients here — same as a BLE central on
        // connect (see connectionStateChanged above), this waits for
        // Hello (see _routeMessage) to learn *which* client this is
        // before deciding whether it is already trusted or needs a PIN.
        onConnected: (_) {},
        onMessage: _onWifiMessage,
        onDisconnected: _onWifiDisconnected,
      );
      final addresses = await WifiServer.localAddresses();
      if (mounted) {
        setState(() {
          _wifiError = null;
          _localAddresses = addresses;
          _hostId = hostId;
          _addLog('WiFi listening on port ${WifiLink.tcpPort}');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _wifiError = '$error';
          _addLog('WiFi failed to start: $error');
        });
      }
    }
  }

  /// Wires a WiFi client's messages into [_routeMessage], supplying the
  /// WiFi-specific way to end a rejected connection: closing the socket.
  void _onWifiMessage(WifiClient client, Uint8List bytes) {
    _routeMessage(
      _wifiSource(client),
      bytes,
      reject: () => client.socket.close(),
    );
  }

  /// Routes a client's message depending on how far its connection has
  /// got: already trusted and fully connected (normal [_handleCommand]),
  /// mid PIN challenge (only a [SubmitPin] means anything), or not yet
  /// identified at all (only a [Hello] means anything — see [_onHello]).
  /// Security, not just bookkeeping, on both transports: anyone on the
  /// same WiFi network can open a connection, and — a deliberate change
  /// from this file's earlier behavior — merely being close enough to
  /// discover the host over Bluetooth is no longer treated as proof of
  /// anything either.
  void _routeMessage(
    ClientSource source,
    Uint8List bytes, {
    required Future<void> Function() reject,
  }) {
    if (_clients.containsKey(source.id)) {
      unawaited(_handleCommand(source, bytes));
      return;
    }
    final pending = _pendingPins[source.id];
    if (pending != null) {
      final message = HotkeyPadMessage.decode(bytes);
      if (message is SubmitPin) unawaited(_verifyPin(pending, message.pin));
      return;
    }
    if (bleAttemptExhausted(
      transport: source.transport,
      alreadyRejected: _bleRejected.contains(source.id),
    )) {
      return;
    }
    final message = HotkeyPadMessage.decode(bytes);
    if (message is Hello) unawaited(_onHello(source, message, reject: reject));
  }

  /// A first message from an unidentified connection is only ever
  /// meaningful if it is a [Hello] — everything else is silently ignored
  /// (see [_routeMessage]) — and [Hello.clientId] is what decides what
  /// happens next.
  Future<void> _onHello(
    ClientSource source,
    Hello hello, {
    required Future<void> Function() reject,
  }) async {
    final clientId = hello.clientId;
    if (clientId.isEmpty) {
      // An old client build, or a malformed one — either way there is no
      // id to remember a decision against, so this fails closed rather
      // than treating it as trusted.
      if (mounted) {
        setState(
          () =>
              _addLog('${source.transport.label} client sent no id; rejected'),
        );
      }
      await reject();
      return;
    }
    switch (trustFor(clientId, _trust)) {
      case ClientTrust.trusted:
        _touch(
          source,
          'said hello as ${hello.name}',
          subscribed: _initialSubscribed(source),
          name: hello.name,
        );
      case ClientTrust.blocked:
        if (mounted) {
          setState(
            () => _addLog(
              '${source.transport.label} client $clientId rejected (blocked)',
            ),
          );
        }
        await reject();
      case ClientTrust.unknown:
        final pin = _generatePin();
        if (mounted) {
          setState(() {
            _pendingPins[source.id] = (
              source: source,
              pin: pin,
              clientId: clientId,
              name: hello.name,
              reject: reject,
            );
            _addLog('${hello.name} needs a PIN: $pin');
          });
        }
        await source.send(const RequestPin().encode());
    }
  }

  /// Thin wrapper around [initialSubscribedFor] supplying this instance's
  /// own [_bleSubscribed] bookkeeping.
  bool? _initialSubscribed(ClientSource source) => initialSubscribedFor(
    transport: source.transport,
    bleSubscribed: _bleSubscribed[source.id],
  );

  /// Six digits — enough that guessing is not practical over the handful
  /// of tries a connection allows before a wrong PIN ends it (see
  /// [_verifyPin] and [_rejectBleCentral]), short enough to comfortably
  /// read off a screen and type into a phone.
  String _generatePin() => (Random().nextInt(900000) + 100000).toString();

  Future<void> _verifyPin(_PendingPin pending, String submitted) async {
    _pendingPins.remove(pending.source.id);
    final ok = submitted.trim() == pending.pin;
    await pending.source.send(PinResult(ok: ok).encode());
    if (!ok) {
      if (mounted) {
        setState(() => _addLog('PIN rejected for ${pending.clientId}'));
      }
      await pending.reject();
      return;
    }
    // _touch (synchronous) runs before the trust file write, not after: the
    // client receives PinResult(ok:true) the instant it's flushed above and
    // immediately re-sends RequestLayout — see HotkeyPadSession's PinResult
    // handler. That can easily beat a disk write back to the host. Until
    // _touch adds this client to _clients, _routeMessage has nowhere to
    // route that RequestLayout (its _pendingPins entry is already gone,
    // removed above) and silently drops it — the client was then stuck on
    // "Loading the deck..." with nothing to prompt a retry, only fixed by
    // whatever next happened to reconnect it. Confirmed against a real
    // WiFi client hitting exactly this on first pairing; BLE shares the
    // same ordering for the same reason.
    if (mounted) setState(() => _trust[pending.clientId] = true);
    _touch(
      pending.source,
      'said hello as ${pending.name}',
      subscribed: _initialSubscribed(pending.source),
      name: pending.name,
    );
    await ClientTrustStore.setDecision(pending.clientId, true);
  }

  /// Ends a rejected BLE connection (a wrong PIN, or an already-blocked
  /// client) the same way [WifiClient.socket]'s `close()` ends a rejected
  /// WiFi one.
  ///
  /// `PeripheralManager.disconnect` is the obvious candidate, but it only
  /// works on Android — it throws [UnsupportedError] on Darwin and
  /// Windows, the two platforms this app actually ships as a host on
  /// (confirmed against the `bluetooth_low_energy` plugin's own platform
  /// implementations). There is no other API to force a central off a
  /// GATT connection it initiated. So this falls back to marking the
  /// connection rejected instead: [_routeMessage] then silently drops
  /// everything else this central sends — no further [RequestPin], no
  /// further [Ack] — until it actually disconnects and reconnects, rather
  /// than letting it just send a fresh [Hello] and get another guess on
  /// the same link. That reconnect is real friction (a fresh GATT
  /// connection, not just another ATT write), the same brute-force
  /// mitigation a fresh TCP connection gives WiFi.
  Future<void> _rejectBleCentral(Central central) async {
    _bleRejected.add(central.uuid.toString());
    try {
      await _peripheral?.disconnect(central);
    } on UnsupportedError {
      // Expected on Darwin/Windows — see this method's own doc comment.
    } catch (error) {
      if (mounted) setState(() => _addLog('BLE disconnect failed: $error'));
    }
  }

  void _onWifiDisconnected(WifiClient client) {
    // _remove's own setState below covers this mutation too.
    _pendingPins.remove(client.id);
    _remove(client.id, 'disconnected');
  }

  /// Subscribes to a stream that some platforms refuse to provide, recording
  /// the gap in the log instead of taking the app down.
  void _listenSafely<T>(
    Stream<T> Function() stream,
    void Function(T event) onEvent,
    String label,
  ) {
    try {
      _subscriptions.add(stream().listen(onEvent));
    } on UnsupportedError {
      _log.add('$label are not reported on this platform');
    }
  }

  void _touch(
    ClientSource source,
    String activity, {
    bool? subscribed,
    String? name,
    bool? portrait,
  }) {
    if (!mounted) return;
    final id = source.id;
    setState(() {
      final existing = _clients[id];
      _clients[id] =
          existing?.copyWith(
            subscribed: subscribed,
            lastActivity: activity,
            name: name,
            portrait: portrait,
          ) ??
          ConnectedClient(
            id: id,
            transport: source.transport,
            send: source.send,
            maxFrameSize: source.maxFrameSize,
            since: DateTime.now(),
            subscribed: subscribed ?? false,
            lastActivity: activity,
            name: name,
            portrait: portrait,
          );
      _autoLockIfSingleClient();
      _addLog('$activity — ${_short(id)}');
    });
  }

  /// Re-derives the device lock after the connected-client list changes —
  /// pulled out so [nextLockedClientId]'s actual decision can be tested
  /// without a real transport.
  void _autoLockIfSingleClient() {
    _lockedClientId = nextLockedClientId(
      currentLockedClientId: _lockedClientId,
      connectedClientIds: _clients.keys.toList(),
    );
  }

  void _remove(String id, String activity) {
    if (!mounted) return;
    setState(() {
      _clients.remove(id);
      // Locking to a device that just left would otherwise silently block
      // every press from whoever remains.
      if (_lockedClientId == id) _lockedClientId = null;
      _autoLockIfSingleClient();
      _addLog('$activity — ${_short(id)}');
    });
  }

  void _addLog(String message) {
    // Mirrored to the console so the service can be diagnosed over
    // `flutter run` without reading the window.
    debugPrint('[HotkeyPad] $message');
    final now = TimeOfDay.fromDateTime(DateTime.now());
    _log.insert(
      0,
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}  $message',
    );
    if (_log.length > 50) _log.removeLast();
  }

  Future<void> _handleCommand(ClientSource source, List<int> bytes) async {
    final message = HotkeyPadMessage.decode(bytes);
    if (message == null) {
      _touch(source, 'unknown command (${bytes.length} bytes)');
      return;
    }
    switch (message) {
      case Hello(:final name):
        _touch(source, 'said hello as $name', name: name);
      case SetOrientation(:final portrait):
        _touch(
          source,
          'reported orientation: ${portrait ? 'portrait' : 'landscape'}',
          portrait: portrait,
        );
      case ListApps():
        _touch(source, 'requested the app list');
        await _queueTransfer(() => _sendCatalogue(source.id));
      // Every button arrives the same way: a slot id the host resolves
      // against its own layout.
      case PressSlot(:final id):
        await _pressSlot(source, id);
      case RequestLayout():
        _touch(source, 'requested the layout');
        await _queueTransfer(() => _sendLayout(source.id));
      case RequestIcon(:final name):
        _touch(source, 'icon for $name');
        await _queueTransfer(() => _sendIcon(source.id, name));
      case DebugText(:final text):
        _touch(source, 'said: $text');
      case SubmitPin():
        // Only meaningful from a connection _routeMessage still has
        // pending — one that has already reached _handleCommand (this
        // method) is, by definition, already trusted and has nothing
        // left to submit a PIN for.
        _touch(source, 'submitted a PIN after already being trusted');
      case Ack() ||
          SetAppearance() ||
          PressSlot() ||
          AppEntry() ||
          ListEnd() ||
          IconUnavailable() ||
          LayoutStart() ||
          LayoutSlot() ||
          LayoutEnd() ||
          RequestPin() ||
          PinResult():
        // Host-to-client shapes; a client has no business sending them.
        _touch(source, 'ignored a ${message.runtimeType}');
    }
  }

  /// Streams the installed apps one message at a time. There is no
  /// reassembly on this link, so the catalogue is many small notifications
  /// rather than one large payload.
  /// Runs [work] after every transfer already queued, so a catalogue in
  /// flight finishes before an icon starts.
  Future<void> _queueTransfer(Future<void> Function() work) {
    final completer = Completer<void>();
    _transfers = _transfers.then((_) async {
      try {
        await work();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _ensureAppPaths() async {
    if (_appPaths.isNotEmpty) return;
    final apps = await AppLauncher.list();
    _appPaths.addEntries(apps.map((app) => MapEntry(app.name, app.path)));
    if (mounted) setState(() => _appCount = apps.length);
  }

  Future<void> _sendCatalogue(String clientId) async {
    final apps = await AppLauncher.list();
    _appPaths
      ..clear()
      ..addEntries(apps.map((app) => MapEntry(app.name, app.path)));
    if (mounted) setState(() => _appCount = apps.length);
    for (final app in apps) {
      await _send(clientId, AppEntry(name: app.name, category: app.category));
      // Notifications queue in the controller and are silently dropped once
      // it fills; pacing them is cheaper than detecting the loss.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _send(clientId, ListEnd(count: apps.length));
    if (mounted) {
      setState(
        () => _addLog('sent ${apps.length} apps to ${_short(clientId)}'),
      );
    }
  }

  /// Acts on the button [id] names, whatever the host's own layout says is
  /// there. The client sent only a number, so a shell command cannot be
  /// injected from the other end of the link.
  Future<void> _pressSlot(ClientSource source, int id) async {
    if (!isPressAllowed(clientId: source.id, lockedClientId: _lockedClientId)) {
      final message = _lockedClientId == null
          ? 'No device is selected on the host yet'
          : 'This host is locked to another device';
      _touch(source, 'slot $id ignored — $message');
      await _send(source.id, Ack(ok: false, message: message));
      return;
    }
    final layout = await LayoutStore.load();
    if (id < 0 || id >= layout.slots.length) {
      _touch(source, 'slot $id is outside the layout');
      await _send(source.id, const Ack(ok: false, message: 'No such button'));
      return;
    }
    final stored = layout.slots[id]?.value;
    final item = stored == null ? null : DeckItem.parse(stored);
    if (item == null) {
      _touch(source, 'slot $id is empty');
      await _send(source.id, const Ack(ok: false, message: 'Empty button'));
      return;
    }

    // Names the slot as well as what was in it: the client sends only a
    // number, and the log should not read as though it sent the action.
    _touch(source, 'slot $id -> ${item.label}');
    final result = await _runItem(item);
    if (mounted) setState(() => _addLog(result.message));
    await _send(source.id, Ack(ok: result.ok, message: result.message));
  }

  /// Runs whatever a single [DeckItem] means to run. Pulled out of
  /// [_pressSlot] so a [ComboItem]'s steps can call back into it — a combo
  /// step is never itself a combo (see [ComboStep.fromJson]), so this never
  /// recurses more than one level deep.
  Future<ActionResult> _runItem(DeckItem item) => switch (item) {
    AppItem(:final name) => AppLauncher.open(name),
    ActionItem(:final action) => MediaControl.run(action),
    ShellItem(:final command) => CommandRunner.shell(command),
    ShortcutItem(:final name) => CommandRunner.shortcut(name),
    KeyComboItem() => CommandRunner.keyCombo(
      modifiers: item.modifiers,
      key: item.key,
      special: item.special,
      label: item.combination,
    ),
    ComboItem(:final steps) => runComboSteps(
      steps,
      run: _runItem,
      delay: (duration) => Future<void>.delayed(duration),
    ),
    // Nothing to run: a WidgetItem is display-only, and the client never
    // sends a press for one of its own slots — this only guards against a
    // stale or misbehaving client naming it directly.
    WidgetItem() => Future.value((ok: false, message: 'Not a button')),
  };

  /// Streams the layout: a header, one message per occupied cell, then an
  /// end marker. Empty cells are not sent — the header's dimensions are
  /// enough to place the rest.
  Future<void> _sendLayout(String clientId) async {
    final layout = await LayoutStore.load();
    await _send(
      clientId,
      LayoutStart(
        columns: layout.columns,
        rows: layout.rows,
        pages: layout.pages,
      ),
    );
    for (var index = 0; index < layout.slots.length; index++) {
      final value = layout.slots[index]?.value;
      if (value == null) continue;
      await _send(clientId, LayoutSlot(index: index, value: value));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _send(clientId, const LayoutEnd());
    // The appearance rides along with the layout so a fresh client is
    // dressed correctly before it draws anything.
    final appearance = await SettingsStore.load();
    await _send(
      clientId,
      SetAppearance(
        theme: appearance.theme,
        showLabels: appearance.showLabels,
        showAppBar: appearance.showAppBar,
        showPageDots: appearance.showPageDots,
        backgroundImageId: appearance.backgroundImageId,
        backgroundOpacity: appearance.backgroundOpacity,
        backgroundFit: appearance.backgroundFit,
      ),
    );
    if (mounted) {
      setState(() {
        _addLog(
          'sent layout ${layout.columns}x${layout.rows}'
          '${layout.pages > 1 ? ' x${layout.pages} pages' : ''} to '
          '${_short(clientId)}',
        );
      });
    }
  }

  /// Pushes the appearance to everyone subscribed, so the phone follows the
  /// Mac the moment it is changed here.
  ///
  /// Reloads the whole [SettingsStore] rather than taking the changed
  /// fields as parameters: [LayoutPage] already saves to the store before
  /// calling back here (both for a theme/label change and a background
  /// one), so re-reading it is simpler than plumbing five parameters
  /// through two different call sites for what is, on the wire, one
  /// message.
  Future<void> _broadcastAppearance() async {
    final appearance = await SettingsStore.load();
    final message = SetAppearance(
      theme: appearance.theme,
      showLabels: appearance.showLabels,
      showAppBar: appearance.showAppBar,
      showPageDots: appearance.showPageDots,
      backgroundImageId: appearance.backgroundImageId,
      backgroundOpacity: appearance.backgroundOpacity,
      backgroundFit: appearance.backgroundFit,
    );
    for (final client in _clients.values.where((c) => c.subscribed)) {
      await _queueTransfer(() => _send(client.id, message));
    }
  }

  /// Pushes an edited layout to everyone currently subscribed, so the deck
  /// on the phone changes as the grid is arranged here.
  Future<void> _broadcastLayout(DeckLayout layout) async {
    for (final client in _clients.values.where((c) => c.subscribed)) {
      await _queueTransfer(() => _sendLayout(client.id));
    }
  }

  /// Renders an app's icon, reads back a user-picked custom icon, reads
  /// back a custom background image, or renders an emoji or an action's
  /// built-in glyph (see [GlyphIconStore]) — every icon a deck button can
  /// show is one of these four, so the client never draws one itself —
  /// and streams it as binary frames sized to the client's own frame-size
  /// limit either way. The transfer itself does not care which [id]
  /// names, which store it came from, or which transport [clientId] is on.
  Future<void> _sendIcon(String clientId, String id) async {
    final client = _clients[clientId];
    if (client == null) return;

    // The client restores its deck from local storage and can ask for an
    // icon before it has asked for the catalogue.
    await _ensureAppPaths();
    final path = _appPaths[id];
    final png = path != null
        ? await AppLauncher.icon(path, size: HotkeyPad.iconSize)
        : await CustomIconStore.read(id) ??
              await BackgroundImageStore.read(id) ??
              await GlyphIconStore.render(id);
    if (png == null) {
      await _send(clientId, IconUnavailable(name: id));
      return;
    }

    final int maximum;
    try {
      maximum = await client.maxFrameSize();
    } catch (error) {
      if (mounted) setState(() => _addLog('icon aborted: $error'));
      return;
    }

    final capacity = IconFrame.payloadCapacity(maximum, id);
    if (capacity <= 0) {
      // A name long enough to fill the frame size on its own leaves
      // nowhere to put the image.
      await _send(clientId, IconUnavailable(name: id));
      return;
    }

    final total = (png.length / capacity).ceil();
    for (var index = 0; index < total; index++) {
      final start = index * capacity;
      final end = start + capacity < png.length ? start + capacity : png.length;
      try {
        await client.send(
          IconFrame.encode(
            name: id,
            index: index,
            total: total,
            payload: png.sublist(start, end),
          ),
        );
      } catch (error) {
        if (mounted) setState(() => _addLog('icon frame failed: $error'));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    if (mounted) {
      setState(() {
        _addLog('sent $id icon (${png.length}B in $total frames)');
      });
    }
  }

  /// Sends one message, refusing anything the client's own frame-size
  /// limit cannot carry.
  Future<void> _send(String clientId, HotkeyPadMessage message) async {
    final client = _clients[clientId];
    if (client == null) return;
    final value = message.encode();
    try {
      final maximum = await client.maxFrameSize();
      if (value.length > maximum) {
        if (mounted) {
          setState(() {
            _addLog('dropped ${value.length}B message, MTU allows $maximum');
          });
        }
        return;
      }
      await client.send(value);
    } catch (error) {
      if (mounted) setState(() => _addLog('notify failed: $error'));
    }
  }

  /// Pushes a value to every subscribed client, whichever transport each
  /// is on.
  Future<void> _broadcast() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;

    final targets = _clients.values.where((c) => c.subscribed).toList();
    if (targets.isEmpty) {
      _showMessage('No subscribed client to notify.');
      return;
    }

    for (final client in targets) {
      await _send(client.id, DebugText(text: text));
    }
    final delivered = targets.length;

    if (!mounted) return;
    setState(() {
      _addLog('sent "$text" to $delivered client(s)');
      _composer.clear();
    });
  }

  String _short(String uuid) =>
      uuid.length > 8 ? '${uuid.substring(0, 8)}…' : uuid;

  /// A connected client's label in the device-lock picker — its name plus
  /// which transport it is on, e.g. "iPhone(bluetooth)", so the same phone
  /// connected over both at once shows as two distinct, pickable entries
  /// rather than one that silently means either.
  String _labelFor(ConnectedClient client) =>
      '${client.name ?? _short(client.id)}(${client.transport.label})';

  /// Starts or stops both transports together as one "the service is on"
  /// toggle — Bluetooth and WiFi are best-effort independent of each
  /// other, so if one radio is off or fails, the other still comes up
  /// rather than either blocking the other.
  Future<void> _toggleAdvertising() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_advertising) {
        await _stopService();
      } else {
        await _startService();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopService() async {
    final peripheral = _peripheral;
    if (peripheral != null) {
      try {
        await peripheral.stopAdvertising();
        await peripheral.removeAllServices();
      } catch (error) {
        _showMessage('$error');
      }
    }
    await _wifiServer.stop();
    if (mounted) {
      setState(() {
        _advertising = false;
        _wifiError = null;
        _localAddresses = [];
        _clients.clear();
        _addLog('stopped');
      });
    }
  }

  Future<void> _startService() async {
    var bleStarted = false;
    final peripheral = _peripheral;
    if (peripheral == null) {
      // Nothing to show — the page itself falls back to UnsupportedPage
      // when there is no Bluetooth plugin at all, so getting here with a
      // null peripheral would mean the plugin threw during setup instead;
      // WiFi below still gets a chance to start regardless.
    } else if (_state == BluetoothLowEnergyState.poweredOff) {
      _showMessage('Turn Bluetooth on first.');
    } else if (!await _ensureAuthorized()) {
      _showMessage('Bluetooth permission denied.');
    } else {
      try {
        // A service can only be published once, so clear anything left
        // over from a previous run before re-adding.
        await peripheral.removeAllServices();
        await peripheral.addService(
          GATTService(
            uuid: HotkeyPad.serviceUuid,
            isPrimary: true,
            includedServices: [],
            characteristics: [_notifyCharacteristic, _writeCharacteristic],
          ),
        );
        await peripheral.startAdvertising(
          Advertisement(
            name: HotkeyPad.advertisedName,
            serviceUUIDs: [HotkeyPad.serviceUuid],
          ),
        );
        bleStarted = true;
        if (mounted) {
          setState(() => _addLog('advertising as ${HotkeyPad.advertisedName}'));
        }
      } catch (error) {
        _showMessage('$error');
      }
    }

    await _startWifi();

    if (mounted) {
      setState(() {
        // "Advertising" now means "the service is up," true once either
        // transport is — see this method's own doc comment.
        _advertising = bleStarted || _wifiServer.running;
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _composer.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_advertising) _peripheral?.stopAdvertising();
    unawaited(_wifiServer.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return UnsupportedPage(details: '$_initError');
    }

    final clients = _clients.values.toList()
      ..sort((a, b) => a.since.compareTo(b.since));
    final subscribedCount = clients.where((c) => c.subscribed).length;
    final l10n = AppLocalizations.of(context)!;

    if (_showingService) {
      return Scaffold(
        appBar: AppBar(
          // A tinted bar rather than the plain surface color it shares
          // with the body — see the deck app bar below for the same
          // treatment applied first.
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          title: Text(l10n.serviceTitle),
          leading: IconButton(
            tooltip: l10n.backToDeck,
            onPressed: () => setState(() => _showingService = false),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: Column(
          children: [
            _pinBanner(context),
            _updateBanner(context),
            Expanded(child: _serviceTab(context, clients, subscribedCount)),
          ],
        ),
      );
    }

    // The window is the deck. Everything else — grid size, appearance, the
    // service details — lives behind the gear. The language picker lives
    // in this app bar rather than the service screen's, since the deck is
    // what a user actually looks at day to day.
    final lockPickerClients = [
      for (final client in clients) (id: client.id, label: _labelFor(client)),
    ];
    return Scaffold(
      appBar: AppBar(
        // A step up from the plain surface color the bar used to share
        // with the window's own background, so it reads as its own
        // strip of chrome rather than blending into the deck — the
        // same contrast the client's app bar was given.
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        title: Text(l10n.deckLayoutTitle),
        actions: [
          if (lockPickerClients.isNotEmpty)
            DeviceLockPicker(
              compact: true,
              clients: lockPickerClients,
              lockedClientId: _lockedClientId,
              onChanged: (value) => setState(() => _lockedClientId = value),
            ),
          IconButton(
            tooltip: l10n.language,
            onPressed: () => _showLanguagePicker(context),
            icon: const Icon(Icons.language),
          ),
          IconButton(
            tooltip: l10n.settingsTitle,
            onPressed: () => _layoutPageKey.currentState?.openSettings(),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _pinBanner(context),
          _updateBanner(context),
          Expanded(
            child: LayoutPage(
              key: _layoutPageKey,
              onChanged: _broadcastLayout,
              onAppearanceChanged:
                  (theme, showLabels, showAppBar, showPageDots) {
                    widget.onThemeChanged(theme);
                    _broadcastAppearance();
                  },
              onShowService: () => setState(() => _showingService = true),
              // Only meaningful once a lock names one unambiguous device to
              // match — see LayoutPage's own doc comment on this field.
              lockedClientPortrait: _lockedClientId == null
                  ? null
                  : _clients[_lockedClientId]?.portrait,
            ),
          ),
        ],
      ),
    );
  }

  /// A device that has never connected before — over either transport —
  /// needs a PIN read off this screen and typed into it — see [_onHello].
  /// Shown above whichever screen the host is already looking at (the
  /// deck or the service tab) rather than as a blocking dialog, since
  /// there is no decision for the host user to make here beyond reading a
  /// number: the PIN itself is the security boundary, not a separate
  /// accept/reject click. The (X) is for a device the user does not
  /// recognize at all.
  Widget _pinBanner(BuildContext context) {
    if (_pendingPins.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            for (final pending in _pendingPins.values)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(Icons.pin_outlined, color: onContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(color: onContainer),
                          children: [
                            TextSpan(
                              text:
                                  '${l10n.pinChallengeNewDevice(pending.name?.isNotEmpty == true ? pending.name! : l10n.newDeviceFallback)} ',
                            ),
                            TextSpan(
                              text: pending.pin,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.pinChallengeReject,
                      icon: Icon(Icons.close, color: onContainer),
                      onPressed: () => _rejectPendingPin(pending),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A quiet notice that a newer host version is out — see
  /// [_checkForUpdate]. Below [_pinBanner] rather than above it: an
  /// unapproved connection is time-sensitive, a new release isn't.
  Widget _updateBanner(BuildContext context) {
    final release = _updateAvailable;
    if (release == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.new_releases_outlined, color: onContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.updateAvailable(release.version),
                  style: TextStyle(color: onContainer),
                ),
              ),
              TextButton(
                onPressed: () => Process.run('open', [release.htmlUrl]),
                child: Text(l10n.viewAction),
              ),
              IconButton(
                tooltip: l10n.dismiss,
                icon: Icon(Icons.close, color: onContainer),
                onPressed: () => _dismissUpdate(release),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ends a still-pending connection without recording a decision — the
  /// device is free to try again (and get a fresh PIN) rather than being
  /// permanently blocked, the same leniency a wrong PIN gets in
  /// [_verifyPin]. Goes through [_PendingPin.reject] so this works
  /// whether the pending connection is WiFi or BLE.
  void _rejectPendingPin(_PendingPin pending) {
    setState(() {
      _pendingPins.remove(pending.source.id);
      _addLog('${pending.clientId} rejected');
    });
    unawaited(pending.reject());
  }

  Widget _serviceTab(
    BuildContext context,
    List<ConnectedClient> clients,
    int subscribedCount,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_accessibility)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.accessibilityNotGranted),
              subtitle: Text(l10n.accessibilityNotGrantedBody),
              trailing: FilledButton(
                onPressed: () async {
                  await MediaControl.requestTrust();
                  await _refreshAccessibility();
                },
                child: Text(l10n.grant),
              ),
            ),
          ),
        _StatusCard(
          state: _state,
          appCount: _appCount,
          advertising: _advertising,
          busy: _busy,
          // Unlike Bluetooth, WiFi has no adapter-state gate that can
          // disable the button on its own — it is either bound or it
          // isn't, and _startService already surfaces a failure to bind
          // via _wifiError rather than needing this to pre-empt it.
          onToggle: _toggleAdvertising,
          wifiRunning: _wifiServer.running,
          wifiError: _wifiError,
          localAddresses: _localAddresses,
        ),
        if (_wifiServer.running &&
            _localAddresses.isNotEmpty &&
            _hostId != null) ...[
          const SizedBox(height: 12),
          _QrPairingCard(
            payload: WifiPairingQr(
              hostId: _hostId!,
              name: Platform.localHostname,
              address: _localAddresses.first,
              port: WifiLink.tcpPort,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          l10n.connectedClients(clients.length),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (clients.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(l10n.noClientConnected)),
          )
        else ...[
          // Meaningful the moment a second device shows up; kept visible
          // with just one connected too, so switching between them never
          // requires hunting for a control that only sometimes exists.
          // Same picker as the deck layout screen's copy — see
          // DeviceLockPicker.
          DeviceLockPicker(
            clients: [
              for (final client in clients)
                (id: client.id, label: _labelFor(client)),
            ],
            lockedClientId: _lockedClientId,
            onChanged: (value) => setState(() => _lockedClientId = value),
          ),
          const SizedBox(height: 12),
          ...clients.map(
            (client) => _ClientTile(
              client: client,
              locked: client.id == _lockedClientId,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                enabled: subscribedCount > 0,
                onSubmitted: (_) => _broadcast(),
                decoration: InputDecoration(
                  hintText: subscribedCount > 0
                      ? l10n.notifySubscribed(subscribedCount)
                      : l10n.noSubscribedClient,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: subscribedCount > 0 ? _broadcast : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(l10n.activity, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_log.isEmpty)
          Text(l10n.nothingYet)
        else
          ..._log.map(
            (line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

/// A button revealing a QR code a phone can scan instead of typing this
/// host's address in — see [WifiPairingQr]. Behind a tap rather than
/// shown outright mainly for a tidier status screen: it carries no more
/// than the plaintext address already visible above it, and scanning it
/// still goes through the exact same `Hello`/trust-on-first-use PIN
/// challenge any other connection does, WiFi or BLE (see `_onHello`) —
/// this only replaces typing the IP in, nothing about how the connection
/// is authorized.
class _QrPairingCard extends StatelessWidget {
  const _QrPairingCard({required this.payload});

  final WifiPairingQr payload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.qr_code_2_outlined),
        title: Text(l10n.pairViaQr),
        subtitle: Text(l10n.pairViaQrSubtitle),
        trailing: FilledButton.tonalIcon(
          onPressed: () => _showQr(context),
          icon: const Icon(Icons.qr_code_2),
          label: Text(l10n.show),
        ),
        onTap: () => _showQr(context),
      ),
    );
  }

  void _showQr(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.scanToConnect),
        content: SizedBox(
          width: 240,
          height: 240,
          child: QrImageView(
            data: payload.encode().toString(),
            version: QrVersions.auto,
            backgroundColor: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.done),
          ),
        ],
      ),
    );
  }
}

/// The fixed alias every Android emulator's virtual network maps to its
/// host machine — not a real address of this machine, but the one that
/// actually works from a manual WiFi entry inside an emulator, whose own
/// NAT'd network the discovery beacon cannot cross. See its one use in
/// [_StatusCard]'s "Emulator" row.
const androidEmulatorHostAlias = '10.0.2.2';

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.appCount,
    required this.advertising,
    required this.busy,
    required this.onToggle,
    required this.wifiRunning,
    required this.wifiError,
    required this.localAddresses,
  });

  final BluetoothLowEnergyState state;
  final int appCount;
  final bool advertising;
  final bool busy;
  final VoidCallback? onToggle;
  final bool wifiRunning;
  final String? wifiError;

  /// For a client whose own discovery cannot reach this host — see its use
  /// in the "WiFi" row below.
  final List<String> localAddresses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  advertising ? Icons.wifi_tethering : Icons.portable_wifi_off,
                  color: advertising ? Colors.green : theme.disabledColor,
                ),
                const SizedBox(width: 12),
                Text(
                  advertising ? 'Advertising' : 'Idle',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Adapter', state.name),
            _row('Local name', HotkeyPad.advertisedName),
            _row('Service', HotkeyPad.serviceUuid.toString()),
            _row(
              'Apps',
              AppLauncher.supported
                  ? (appCount == 0 ? 'not requested yet' : '$appCount found')
                  : 'launching unsupported on this platform',
            ),
            _row(
              'WiFi',
              wifiRunning
                  ? 'listening on port ${WifiLink.tcpPort}'
                  : wifiError ?? 'not running',
            ),
            if (wifiRunning) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 90, child: Text('Address')),
                    Expanded(
                      // Selectable rather than plain Text specifically so
                      // this can be copied straight into the client's
                      // manual-entry field — see WifiServer.localAddresses.
                      child: SelectableText(
                        localAddresses.isEmpty
                            ? 'none found'
                            : localAddresses.join(', '),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Not one of localAddresses because it is not a real address
              // of this machine — it is the fixed alias every Android
              // emulator maps to its host's loopback, the manual-entry
              // value that actually works there since the emulator's own
              // NAT'd network can neither be reached from this LAN nor
              // deliver the discovery beacon into it (see this file's
              // WiFi client tests / the client's manualWifiHostId doc
              // comment on that same gap). Listed here so a client
              // running in an emulator can read it straight off this
              // card instead of having to already know the trick.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 90, child: Text('Emulator')),
                    Expanded(
                      child: SelectableText(
                        '$androidEmulatorHostAlias (Android emulator only)',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onToggle,
                icon: Icon(advertising ? Icons.stop : Icons.play_arrow),
                label: Text(
                  advertising ? 'Stop advertising' : 'Start advertising',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client, required this.locked});

  final ConnectedClient client;

  /// Whether this is the one client the host is currently locked to.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: locked ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: client.subscribed
              ? Colors.green.withValues(alpha: 0.15)
              : Theme.of(context).disabledColor.withValues(alpha: 0.15),
          child: Icon(
            client.transport == LinkTransport.wifi
                ? Icons.wifi
                : Icons.bluetooth,
            color: client.subscribed ? Colors.green : null,
          ),
        ),
        title: Text(
          // Same "name(transport)" shape as the lock picker — see
          // _labelFor — so the same device connected twice at once (once
          // per transport) is still told apart here too.
          '${client.name ?? client.id}(${client.transport.label})',
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(client.lastActivity),
        trailing: locked ? const Icon(Icons.lock) : null,
      ),
    );
  }
}
