import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'background_fit.dart';
import 'connection_method_store.dart';
import 'debug_page.dart';
import 'edge_bar.dart';
import 'host_history_store.dart';
import 'link_target.dart';
import 'locale_store.dart';
import 'qr_scan_page.dart';
import 'safe_insets.dart';
import 'scan_page.dart';
import 'deck_icons.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'session.dart';

/// Where the Settings dialog's "Report an issue" entry sends the user —
/// the issue tracker, so they can check whether theirs is already
/// reported before filing a new one.
const _githubIssuesUrl = 'https://github.com/AJua/HotkeyPad/issues';

/// Where the first-run connection-method screen's "Get it on GitHub" link
/// sends the user — the latest release directly, since a phone without the
/// host installed yet has nothing to pair with regardless of which
/// transport it picks below.
const _githubReleasesUrl = 'https://github.com/AJua/HotkeyPad/releases/latest';

/// What port a manually-entered host address should be dialed on: the
/// typed value if it parses to a positive integer, [WifiLink.tcpPort] (the
/// only port a real HotkeyPad host ever listens on) otherwise — so leaving
/// the field blank, or mistyping it, still gets you the one port that
/// could possibly work rather than a client-side error before the app
/// ever reaches the network.
///
/// A pure function of the raw field text so it is testable without a
/// widget.
int resolveManualPort(String input) {
  final parsed = int.tryParse(input.trim());
  return (parsed != null && parsed > 0) ? parsed : WifiLink.tcpPort;
}

/// Four dot-separated 1-3 digit groups — loose on purpose (it doesn't
/// reject an out-of-range octet like 999) since [_ManualHostDialog]'s
/// address field already keys a numeric-only keyboard; this exists to
/// catch what that keyboard can't prevent (pasted text) with a plain-
/// language error instead of a raw `SocketException` reaching the user.
/// A pure function of the trimmed field text so it is testable without a
/// widget, the same reason [resolveManualPort] is.
bool looksLikeIpv4(String input) =>
    RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(input);

/// The app's home. Finds a host by itself rather than making the user pick
/// one: there is normally exactly one Mac to talk to, and choosing it from a
/// list of every radio in the room is a chore, not a feature.
class DeckPage extends StatefulWidget {
  const DeckPage({
    super.key,
    required this.onTheme,
    required this.locale,
    required this.onLocale,
  });

  /// Reports the appearance the host asked for, so the app can apply it.
  final ValueChanged<DeckTheme> onTheme;

  /// The user's own manually-picked language, if any — see
  /// [HotkeyPadClientApp]'s field of the same name. Threaded down (rather
  /// than read fresh from [LocaleStore] wherever it's needed) so the
  /// language-picker button and [MaterialApp] always agree on what's
  /// currently selected without a second source of truth.
  final Locale? locale;
  final ValueChanged<Locale?> onLocale;

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  final _pages = PageController();
  int _page = 0;

  /// The gap between slots — shared with the host's own editor preview via
  /// [kDeckGridSpacing], so a button looks the same size relative to its
  /// neighbours on both.
  static const _slotSpacing = kDeckGridSpacing;

  /// The deck's own outer margin — see [_deck].
  static const _slotMargin = 12.0;

  /// The last [HotkeyPadSession.failureSeq] a SnackBar was already shown
  /// for — see its own use in [build] for why a sequence number rather
  /// than just checking [HotkeyPadSession.lastAck] for null.
  int _shownFailureSeq = 0;

  CentralManager? _central;
  HotkeyPadSession? _session;
  StreamSubscription? _discovery;
  StreamSubscription? _stateChanges;
  var _state = BluetoothLowEnergyState.unknown;
  bool _askedForPermission = false;
  Timer? _searchTimeout;
  Object? _searchError;
  bool _searching = false;

  /// The user's own chosen transport — see [ConnectionMethodStore]. Null
  /// means either "still loading from disk" ([_methodLoaded] false) or
  /// "never chosen" ([_methodLoaded] true), which is what tells [build]
  /// to show the choice screen instead of racing both transports the way
  /// this screen used to.
  ConnectionMethod? _method;
  bool _methodLoaded = false;

  /// WiFi's own discovery, alongside Bluetooth's — bound independently of
  /// [_central]/[_state] since WiFi needs neither an adapter nor a runtime
  /// permission, so it must not be gated behind Bluetooth's own state
  /// machine below; see [_startWifiDiscovery].
  RawDatagramSocket? _wifiDiscovery;

  /// WiFi hosts this app has connected to before — see [HostHistoryStore].
  /// Loaded once at startup and refreshed whenever the search screen comes
  /// back (a fresh connection may have just been added to it).
  List<HostHistoryEntry> _history = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadMethod());
  }

  Future<void> _loadMethod() async {
    final method = await ConnectionMethodStore.load();
    if (!mounted) return;
    setState(() {
      _method = method;
      _methodLoaded = true;
    });
    if (method != null) _startForMethod(method);
  }

  /// Called once the user picks a method for the first time (from
  /// [_methodChoiceScaffold]) or switches it later (from
  /// [_showConnectionMethodSettings]) — either way, persist it before
  /// starting so a crash mid-connect does not lose the choice.
  Future<void> _chooseMethod(ConnectionMethod method) async {
    await ConnectionMethodStore.save(method);
    if (!mounted) return;
    setState(() => _method = method);
    _startForMethod(method);
  }

  /// Tears down whatever the previous method had running before starting
  /// the new one — the settings sheet is the only caller that can reach
  /// this with something already in flight; [_chooseMethod] on a fresh
  /// launch has nothing to stop.
  Future<void> _switchMethod(ConnectionMethod method) async {
    _stopSearch();
    _stopWifiDiscovery();
    _session?.dispose();
    await ConnectionMethodStore.save(method);
    if (!mounted) return;
    setState(() {
      _session = null;
      _searchError = null;
      _method = method;
    });
    _startForMethod(method);
  }

  void _startForMethod(ConnectionMethod method) {
    switch (method) {
      case ConnectionMethod.bluetooth:
        // Re-entering Bluetooth after a switch away from it: the manager
        // and its state-change listener are still alive (see the guard in
        // that listener below), so there is nothing to recreate — just
        // resume from whatever state it last reported.
        if (_central == null) {
          _initBluetooth();
        } else {
          _onState(_state);
        }
      case ConnectionMethod.wifi:
        unawaited(_startWifiDiscovery());
        unawaited(_loadHistory());
    }
  }

  /// Bluetooth's own setup, split out of [_startForMethod] so switching to
  /// WiFi and back does not pay for a second [CentralManager] — see that
  /// method's bluetooth case.
  void _initBluetooth() {
    try {
      final central = CentralManager();
      _central = central;
      _state = central.state;
      _stateChanges = central.stateChanged.listen((event) {
        // A stray adapter event while the user is on WiFi must not resume
        // scanning behind their back — the manager stays alive across a
        // switch (see [_startForMethod]), only this guard does.
        if (!mounted || _method != ConnectionMethod.bluetooth) return;
        setState(() => _state = event.state);
        _onState(event.state);
      });
    } catch (error) {
      // No Bluetooth implementation on this platform.
      _searchError = error;
    }
    // After the first frame: authorize() goes through the plugin's Activity,
    // which is not attached yet during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_central != null) _onState(_state);
    });
  }

  Future<void> _loadHistory() async {
    final history = await HostHistoryStore.load();
    if (mounted) setState(() => _history = history);
  }

  @override
  void dispose() {
    _searchTimeout?.cancel();
    _stateChanges?.cancel();
    _discovery?.cancel();
    if (_searching) _stopDiscoverySafely();
    _stopWifiDiscovery();
    _pages.dispose();
    _session?.dispose();
    super.dispose();
  }

  /// Best-effort, fire-and-forget stop — a device with no BLE radio at
  /// all throws the same `getBluetoothLeScanner(...) must not be null`
  /// from *every* [CentralManager] call, [stopDiscovery] included, not
  /// just [startDiscovery]. Confirmed against a real crash: [_search]'s
  /// own catch already handles the first throw and calls [_stopSearch],
  /// but that then hit this same call unguarded and threw a second,
  /// truly unhandled exception.
  void _stopDiscoverySafely() {
    unawaited(_central?.stopDiscovery().catchError((_) {}));
  }

  /// Listens for the host's UDP beacon (see `hotkeypad_host`'s `WifiServer`) —
  /// WiFi's equivalent of Bluetooth's `central.discovered` stream. Silent
  /// on any failure to bind: an unsupported platform or a denied local-
  /// network permission just leaves Bluetooth discovery to work alone,
  /// the same as a Bluetooth-side failure never blocks WiFi.
  Future<void> _startWifiDiscovery() async {
    if (_wifiDiscovery != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        WifiLink.discoveryPort,
        reuseAddress: true,
      );
      if (_session != null) {
        // Adopted over Bluetooth while this was still binding.
        socket.close();
        return;
      }
      _wifiDiscovery = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final beacon = WifiBeacon.tryParse(datagram.data);
        if (beacon == null) return;
        _adoptWifi(beacon, datagram.address.address);
      });
    } catch (_) {
      // No WiFi discovery this run; Bluetooth above still works on its own.
    }
  }

  void _stopWifiDiscovery() {
    _wifiDiscovery?.close();
    _wifiDiscovery = null;
  }

  /// The adapter's state decides what happens next. Requesting permission
  /// unconditionally was wrong: `authorize()` re-requests through the
  /// plugin's Activity even when the permission is already held, and on a
  /// cold start that call can simply never return.
  void _onState(BluetoothLowEnergyState state) {
    switch (state) {
      case BluetoothLowEnergyState.poweredOn:
        _search();
      case BluetoothLowEnergyState.unauthorized:
        _requestPermission();
      case BluetoothLowEnergyState.poweredOff:
        _fail('Bluetooth is turned off.');
      case BluetoothLowEnergyState.unsupported:
        _fail('This device does not support Bluetooth Low Energy.');
      case BluetoothLowEnergyState.unknown:
        // The plugin has not reported yet; the next event will arrive.
        break;
    }
  }

  void _fail(String message) {
    _stopSearch();
    if (mounted) setState(() => _searchError = StateError(message));
  }

  Future<void> _requestPermission() async {
    final central = _central;
    // Once per run: a denied prompt should not loop.
    if (central == null || _askedForPermission) return;
    _askedForPermission = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      // Granting arrives as a state change, which re-enters _onState.
      await central.authorize();
    } catch (error) {
      if (mounted) setState(() => _searchError = error);
    }
  }

  Future<void> _search() async {
    final central = _central;
    if (central == null || _searching || _session != null) return;

    setState(() {
      _searching = true;
      _searchError = null;
    });

    // Armed before anything that can await: Android throttles an app that
    // scans repeatedly, and startDiscovery can then never return. A timeout
    // set afterwards would never be set at all.
    _searchTimeout = Timer(const Duration(seconds: 20), _giveUp);

    try {
      // Deliberately not filtering the scan on the service UUID: a host
      // whose advertisement puts it in the scan response would be missed
      // entirely, and the check below costs nothing.
      _discovery = central.discovered.listen((event) {
        if (!event.advertisement.serviceUUIDs.contains(HotkeyPad.serviceUuid)) {
          return;
        }
        _adopt(event.peripheral, _nameOf(event.advertisement));
      });

      await central.startDiscovery();
    } catch (error) {
      _stopSearch();
      if (mounted) setState(() => _searchError = error);
    }
  }

  void _giveUp() {
    if (_session != null) return;
    _stopSearch();
    if (!mounted) return;
    setState(() {
      _searchError = StateError(
        'No HotkeyPad host is advertising nearby. Check that the host is '
        'running on your Mac. Scanning repeatedly in a short time can also '
        'make Android stop reporting results for a minute.',
      );
    });
  }

  String? _nameOf(Advertisement advertisement) {
    try {
      return advertisement.name;
    } on UnsupportedError {
      return null;
    }
  }

  void _stopSearch() {
    _searchTimeout?.cancel();
    _searchTimeout = null;
    _discovery?.cancel();
    _discovery = null;
    if (_searching) _stopDiscoverySafely();
    if (mounted) setState(() => _searching = false);
  }

  /// Takes the first host that answers, over either transport. With one
  /// Mac in the room there is nothing to choose between, and a picker
  /// would just be a step to dismiss.
  void _adopt(Peripheral peripheral, String? name) {
    if (_session != null) return;
    _stopSearch();
    _stopWifiDiscovery();
    if (!mounted) return;
    setState(() {
      _session =
          HotkeyPadSession(
              target: BleTarget(peripheral),
              name: name?.isNotEmpty == true ? name! : HotkeyPad.advertisedName,
            )
            ..onTheme = widget.onTheme
            ..start();
    });
  }

  /// WiFi's counterpart to [_adopt] — same "first to answer wins" rule,
  /// extended across both transports.
  void _adoptWifi(WifiBeacon beacon, String address) {
    if (_session != null) return;
    _stopSearch();
    _stopWifiDiscovery();
    if (!mounted) return;
    setState(() {
      _session =
          HotkeyPadSession(
              target: WifiTarget(
                hostId: beacon.hostId,
                address: address,
                port: beacon.port,
              ),
              name: beacon.name.isNotEmpty
                  ? beacon.name
                  : HotkeyPad.advertisedName,
            )
            ..onTheme = widget.onTheme
            ..start();
    });
  }

  /// The app's own icon, shown at the start of the bar in place of a
  /// generic leading widget — in landscape it is all the bar has room to
  /// show (see [EdgeBarScaffold]'s side bar), so it also doubles as the
  /// shortcut back to the first page that a launcher icon would otherwise
  /// have no equivalent for once you're already inside the deck.
  Widget _appIcon({VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Image.asset('assets/icon/app_icon.png', width: 32, height: 32),
        ),
      ),
    );
  }

  void _jumpToFirstPage() {
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  Future<void> _press(HotkeyPadSession session, int id, DeckItem item) async {
    // Fires before the round trip: the deck should feel like a button, not
    // like a form that submits.
    unawaited(HapticFeedback.selectionClick());
    await session.press(id, item);
  }

  /// Opens the GitHub issue tracker in the device's browser — the settings
  /// dialog itself stays open underneath, since this doesn't navigate
  /// anywhere inside the app the way Nearby devices/Debug console do.
  Future<void> _reportIssue() async {
    await launchUrl(
      Uri.parse(_githubIssuesUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Copies the host's GitHub releases URL to the clipboard — step 1 of
  /// the first-run screen. HotkeyPad Host runs on a computer, not this
  /// phone, so opening the link here would land in a mobile browser that
  /// can't do anything useful with it; what a first-time user actually
  /// needs is to get that address onto their computer, which pasting it
  /// into any browser there does regardless of platform.
  Future<void> _copyHostUrl() async {
    await Clipboard.setData(const ClipboardData(text: _githubReleasesUrl));
    unawaited(HapticFeedback.selectionClick());
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.urlCopiedMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      if (!_methodLoaded) return _loadingScaffold(context);
      if (_method == null) return _methodChoiceScaffold(context);
      // Without this, the system/gesture back button here falls straight
      // through to the OS and exits the app outright — this screen has
      // no pushed route of its own to pop back to, unlike the dialogs
      // launched from it. Stepping back to the choice screen instead
      // matches what a user expects "back" to do mid-setup, and mirrors
      // the settings gear's own "change this later" path.
      return PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() => _method = null);
        },
        child: _searchScaffold(context),
      );
    }

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        // A failed press already flashes the button red — that says a
        // press failed, not why. Surfacing the host's own reason (e.g.
        // "This host is locked to another device") here, once per fresh
        // failure, is what used to be visible only by opening the debug
        // console's raw message log. failureSeq — not feedbackFor, which
        // stays the same value for the 1.4s the flash is on screen and
        // would otherwise show this on every rebuild in that window —
        // is what makes this fire exactly once per failure.
        final failureSeq = session.failureSeq;
        if (failureSeq != _shownFailureSeq) {
          _shownFailureSeq = failureSeq;
          final reason = session.lastAck;
          if (reason != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(reason)));
            });
          }
        }
        final overlay = session.stage != LinkStage.ready
            ? _ConnectionOverlay(
                session: session,
                deviceName: session.name,
                onBack: _forget,
              )
            : null;
        // Off, the title and debug-console button disappear and the grid
        // takes the whole screen — see buildFullBleedDeck's own doc
        // comment for why that is its own composition rather than
        // buildDeckStack wrapped in a SafeArea.
        if (!session.showAppBar) {
          return buildFullBleedDeck(
            backgroundImage: session.backgroundImage,
            backgroundOpacity: session.backgroundOpacity,
            backgroundFit: session.backgroundFit,
            body: _body(session),
            overlay: overlay,
          );
        }
        final deck = buildDeckStack(
          backgroundImage: session.backgroundImage,
          backgroundOpacity: session.backgroundOpacity,
          backgroundFit: session.backgroundFit,
          body: _body(session),
          overlay: overlay,
        );
        return EdgeBarScaffold(
          side: barSideFor(context),
          title: 'HotkeyPad',
          // Which Mac this is, not what app it is — the brand name above
          // it already says that, the same as every other screen.
          subtitle: session.name,
          leading: _appIcon(onTap: _jumpToFirstPage),
          actions: [
            IconButton(
              tooltip: AppLocalizations.of(context)!.language,
              onPressed: () => _showLanguagePicker(context),
              icon: const Icon(Icons.language),
            ),
            IconButton(
              tooltip: AppLocalizations.of(context)!.settingsTitle,
              onPressed: () => _showSettingsMenu(context, session: session),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
          child: deck,
        );
      },
    );
  }

  /// Drops the current host and looks again — the only way back to a
  /// different Mac now that there is no picker.
  void _forget() {
    _session?.dispose();
    setState(() => _session = null);
    // Non-null: reaching a session at all means a method was already
    // chosen and started.
    _startForMethod(_method!);
  }

  /// The fallback for when discovery cannot reach the host at all — an
  /// emulator's isolated network, or AP client isolation on the real one
  /// (see [manualWifiHostId]'s doc comment) — typed in by hand instead of
  /// learned from a beacon.
  void _connectManually(String address, int port) {
    if (_session != null) return;
    _stopSearch();
    _stopWifiDiscovery();
    if (!mounted) return;
    setState(() {
      _session =
          HotkeyPadSession(
              target: WifiTarget(
                hostId: manualWifiHostId(address: address, port: port),
                address: address,
                port: port,
              ),
              name: HotkeyPad.advertisedName,
            )
            ..onTheme = widget.onTheme
            ..start();
    });
  }

  Future<void> _showManualEntryDialog() async {
    final result = await showDialog<({String address, int port})>(
      context: context,
      builder: (_) => const _ManualHostDialog(),
    );
    if (result != null) _connectManually(result.address, result.port);
  }

  /// A previously-connected host from [_history], or a freshly-scanned QR
  /// code — either way a full [WifiPairingQr]-equivalent identity is
  /// already known, unlike [_connectManually]'s synthetic
  /// [manualWifiHostId], so this lands in the same cache entry a beacon-
  /// discovered connection to the same host would use.
  void _connectKnownWifiHost({
    required String hostId,
    required String address,
    required int port,
    required String name,
  }) {
    if (_session != null) return;
    _stopSearch();
    _stopWifiDiscovery();
    if (!mounted) return;
    setState(() {
      _session =
          HotkeyPadSession(
              target: WifiTarget(hostId: hostId, address: address, port: port),
              name: name,
            )
            ..onTheme = widget.onTheme
            ..start();
    });
  }

  void _connectToHistoryEntry(HostHistoryEntry entry) => _connectKnownWifiHost(
    hostId: entry.hostId,
    address: entry.address,
    port: entry.port,
    name: entry.name,
  );

  Future<void> _forgetHistoryEntry(HostHistoryEntry entry) async {
    await HostHistoryStore.forget(entry.address, entry.port);
    await _loadHistory();
  }

  Future<void> _scanQrCode() async {
    final result = await Navigator.of(context).push<WifiPairingQr>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (result == null) return;
    _connectKnownWifiHost(
      hostId: result.hostId,
      address: result.address,
      port: result.port,
      name: result.name,
    );
  }

  /// Entirely client-side — see [HotkeyPadClientApp._locale]'s doc
  /// comment on why this is never sent to or learned from the host.
  /// Each option's own label is written in that language itself, not
  /// run through [AppLocalizations], so someone who can't read the
  /// app's *current* language can still recognize and pick their own —
  /// the one line in this sheet that *is* localized is "System default"
  /// itself, since that's a concept, not a language name.
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

  /// The gear button's popup, on every screen that has one — mirrors
  /// `hotkeypad_host`'s own settings dialog (`layout_page.dart`'s
  /// `openSettings`): one small dialog holds everything that would
  /// otherwise be a separate app bar icon of its own, the debug console
  /// included, rather than the bar accumulating one icon per setting.
  ///
  /// [session] is whatever the caller currently has — null from the
  /// pre-connection search screen, the live session once connected —
  /// and is only used to open the right [DebugPage].
  Future<void> _showSettingsMenu(
    BuildContext context, {
    required HotkeyPadSession? session,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    Widget option(ConnectionMethod method, IconData icon, String label) =>
        RadioListTile<ConnectionMethod>(
          contentPadding: EdgeInsets.zero,
          value: method,
          secondary: Icon(icon),
          title: Text(label),
        );
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(l10n.settingsTitle),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.connectionMethodSettingsTitle,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    RadioGroup<ConnectionMethod>(
                      groupValue: _method,
                      // _switchMethod persists and awaits before touching
                      // _method, so the dialog is told to redraw only
                      // after the field it reads has actually changed —
                      // calling setDialogState any earlier would just
                      // repaint the old selection.
                      onChanged: (value) async {
                        if (value == null || value == _method) return;
                        await _switchMethod(value);
                        setDialogState(() {});
                      },
                      child: Column(
                        children: [
                          option(
                            ConnectionMethod.bluetooth,
                            Icons.bluetooth,
                            l10n.connectionMethodBluetooth,
                          ),
                          option(
                            ConnectionMethod.wifi,
                            Icons.wifi,
                            l10n.connectionMethodWifi,
                          ),
                        ],
                      ),
                    ),
                    // Developer diagnostics, like the host's own "Service
                    // details" — for working out why the deck is
                    // misbehaving, not for daily use. Debug-build only:
                    // a regular user has no use for a raw Bluetooth
                    // scanner or a protocol-level message log (one even
                    // has a "send raw text to the host" field), and
                    // showing them in a release build reads as
                    // developer tooling that leaked into the product
                    // rather than a real feature. Both are direct
                    // entries here rather than one nested inside the
                    // other (ScanPage used to be reachable only via an
                    // icon inside DebugPage) so reaching either is one
                    // tap from the gear, not two.
                    if (kDebugMode) ...[
                      const Divider(height: 32),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bluetooth_searching),
                        title: Text(l10n.nearbyDevices),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ScanPage()),
                          );
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bug_report_outlined),
                        title: Text(l10n.debugConsole),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DebugPage(session: session),
                            ),
                          );
                        },
                      ),
                    ],
                    const Divider(height: 32),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.feedback_outlined),
                      title: Text(l10n.reportIssueTitle),
                      subtitle: Text(l10n.reportIssueSubtitle),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: _reportIssue,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.done),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shown for as long as [ConnectionMethodStore.load] is still in
  /// flight — a plain-preferences read, so this is on screen for a few
  /// milliseconds at most, not worth its own chrome.
  Widget _loadingScaffold(BuildContext context) {
    return EdgeBarScaffold(
      side: barSideFor(context),
      title: 'HotkeyPad',
      leading: _appIcon(),
      actions: const [],
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  /// The first thing a fresh install sees: which transport to use, since
  /// nothing has been chosen yet. Shown exactly once per install (barring
  /// a deliberate change from [_showConnectionMethodSettings]) — see
  /// [_chooseMethod].
  Widget _methodChoiceScaffold(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return EdgeBarScaffold(
      side: barSideFor(context),
      title: 'HotkeyPad',
      leading: _appIcon(),
      actions: [
        IconButton(
          tooltip: l10n.language,
          onPressed: () => _showLanguagePicker(context),
          icon: const Icon(Icons.language),
        ),
      ],
      // A scroll view, not a bare Center — see _searchScaffold's own
      // comment on the same pattern: on a small phone in landscape, the
      // two full setup steps (heading, URL box, both method cards) can
      // be taller than the available height, which a bare Center only
      // clips silently in release builds while flagging a real
      // RenderFlex overflow in debug — confirmed on a real device.
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Where a purely decorative app icon used to sit —
                        // walking a fresh install through the two things it
                        // actually needs, in order, is more useful there
                        // than a logo: nothing below works until a host
                        // exists on a computer to pair with.
                        Text(
                          l10n.howToUseTitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 20),
                        _StepHeader(step: 1, title: l10n.step1Title),
                        const SizedBox(height: 8),
                        Text(
                          l10n.step1Body,
                          textAlign: TextAlign.left,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        _CopyableUrl(
                          url: _githubReleasesUrl,
                          onTap: _copyHostUrl,
                        ),
                        const SizedBox(height: 28),
                        _StepHeader(step: 2, title: l10n.connectionMethodTitle),
                        const SizedBox(height: 4),
                        Text(
                          l10n.connectionMethodSubtitle,
                          textAlign: TextAlign.left,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        _MethodCard(
                          icon: Icons.bluetooth,
                          title: l10n.connectionMethodBluetooth,
                          subtitle: l10n.connectionMethodBluetoothHint,
                          onTap: () =>
                              _chooseMethod(ConnectionMethod.bluetooth),
                        ),
                        const SizedBox(height: 12),
                        _MethodCard(
                          icon: Icons.wifi,
                          title: l10n.connectionMethodWifi,
                          subtitle: l10n.connectionMethodWifiHint,
                          onTap: () => _chooseMethod(ConnectionMethod.wifi),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _searchScaffold(BuildContext context) {
    final error = _searchError;
    final l10n = AppLocalizations.of(context)!;
    final method = _method!; // only reached once a method is chosen
    return EdgeBarScaffold(
      side: barSideFor(context),
      title: 'HotkeyPad',
      leading: _appIcon(),
      actions: [
        IconButton(
          tooltip: l10n.language,
          onPressed: () => _showLanguagePicker(context),
          icon: const Icon(Icons.language),
        ),
        IconButton(
          tooltip: l10n.settingsTitle,
          onPressed: () => _showSettingsMenu(context, session: null),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      // A scroll view, not a bare Center, because the previous-hosts list
      // below can grow past what a small phone in landscape has room for
      // — LayoutBuilder + a min-height ConstrainedBox keeps everything
      // centered when it fits and scrollable when it doesn't.
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (error == null) ...[
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.lookingForHost,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.startHostOnMac,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ] else ...[
                        Icon(
                          method == ConnectionMethod.bluetooth
                              ? Icons.bluetooth_disabled
                              : Icons.wifi_off,
                          size: 48,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.noHostFound,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error is StateError ? error.message : '$error',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 20),
                        // Only Bluetooth has a give-up timeout (_giveUp) to
                        // retry from — WiFi discovery just keeps listening,
                        // with the manual/QR fallbacks below always there.
                        if (method == ConnectionMethod.bluetooth)
                          FilledButton.icon(
                            onPressed: _search,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.searchAgain),
                          ),
                      ],
                      // WiFi-only: Bluetooth has no manual address or QR
                      // equivalent to fall back to — it either finds a
                      // host advertising nearby or it does not.
                      if (method == ConnectionMethod.wifi) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _showManualEntryDialog,
                              icon: const Icon(Icons.keyboard_outlined),
                              label: Text(l10n.enterHostIpManually),
                            ),
                            TextButton.icon(
                              onPressed: _scanQrCode,
                              icon: const Icon(Icons.qr_code_scanner_outlined),
                              label: Text(l10n.scanQrCode),
                            ),
                          ],
                        ),
                        if (_history.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          _PreviousHostsList(
                            entries: _history,
                            onSelect: _connectToHistoryEntry,
                            onForget: _forgetHistoryEntry,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(HotkeyPadSession session) {
    final stored = session.layout;
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    // The host edits one shape; the deck turns it to fit the screen it is
    // actually on, so a 5x3 landscape grid becomes 3x5 upright.
    final layout = stored?.orientedFor(portrait: portrait);
    // So the host's own editor can show the same turned shape while this
    // is the locked device — a no-op once it already knows, so calling it
    // on every build is fine (see ensureIcon, called the same way above).
    unawaited(session.reportOrientation(portrait));

    if (layout == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 56,
                color: Theme.of(context).disabledColor,
              ),
              const SizedBox(height: 12),
              Text(
                session.loadingLayout ? 'Loading the deck...' : 'No deck yet.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Arrange the buttons in the HotkeyPad host on your Mac.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    // A page count that shrank out from under a stale index (an edit on
    // the host, or a transient mismatch across an orientation change)
    // would otherwise hand _PageDots a "current" past the end of its own
    // dot row — clamped here, once, rather than in every reader of _page.
    if (_page >= layout.pages) _page = layout.pages - 1;

    // Every button visible at once is the point of a deck, so the grid is
    // sized to fit rather than scrolled. Cells stay square and the block is
    // centred: stretching them to fill would make buttons wide in landscape
    // and tall in portrait, and leave the margins uneven once the app bar
    // has taken one edge.
    //
    // Pulling down retries any icon that never arrived (see
    // HotkeyPadSession.refreshIcons) — a dropped frame otherwise has no way to
    // recover on its own. The grid itself never scrolls, so this needs its
    // own vertical scrollable to detect the pull. A Sliver-based
    // SliverFillRemaining did that once, but RenderSliverFillRemaining can
    // query its child's *intrinsic* height, and _deck's own LayoutBuilder
    // throws rather than answer that (a LayoutBuilder cannot run its builder
    // speculatively) — a crash that only some constraint shapes hit, which
    // is how it passed earlier Android testing but broke on iPhone.
    // SingleChildScrollView never asks for intrinsics, so it sidesteps the
    // conflict entirely; the outer LayoutBuilder just pins the child to
    // exactly the viewport height, since a scroll view otherwise hands its
    // child unbounded height and _deck needs a bounded one to size cells.
    // Vertical pull and the PageView's horizontal swipe are different axes,
    // so neither steals gestures from the other.
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, outer) {
              return RefreshIndicator(
                onRefresh: session.refreshIcons,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: outer.maxHeight,
                    child: _deck(session, layout),
                  ),
                ),
              );
            },
          ),
        ),
        // Bottom-right rather than blocking anything: a layout/appearance
        // edit already lands on the deck without asking (see
        // HotkeyPadSession.isSyncing's own doc comment on why this isn't
        // just loadingLayout) — this is only a quiet acknowledgement that
        // something changed, not a gate the user has to wait past. Only
        // shown once there's a layout to show it over; while there is
        // none yet, the "Loading the deck..." text above already says so.
        Positioned(
          right: 16,
          bottom: 16,
          child: _SyncingBadge(visible: session.isSyncing),
        ),
      ],
    );
  }

  Widget _deck(HotkeyPadSession session, DeckLayout layout) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = _slotSpacing;
        // Taller than wide when there are labels, since the text needs a
        // band of its own. Without labels there is nothing to leave room
        // for, so cells go square and the icon fills them.
        final labels = session.showLabels;
        final cellRatio = labels ? 0.86 : 1.0;
        final padding = safeScrollPadding(
          context,
          horizontal: _slotMargin,
          vertical: _slotMargin,
        );
        final dots = layout.pages > 1 && session.showPageDots ? 28.0 : 0.0;

        final metrics = deckGridMetrics(
          maxWidth: constraints.maxWidth - padding.horizontal,
          maxHeight: constraints.maxHeight - padding.vertical - dots,
          columns: layout.columns,
          rows: layout.rows,
          cellRatio: cellRatio,
          spacing: spacing,
        );

        return Padding(
          // Vertical only. The horizontal inset is already subtracted from
          // the grid's width above, so applying it here as well would just
          // narrow the swipe area — and the edges are exactly where a thumb
          // starts a swipe from.
          padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
          child: Column(
            children: [
              Expanded(
                // The PageView spans the whole area and each page centres
                // its own grid, rather than the PageView being sized to the
                // grid. In landscape the grid leaves wide margins, and a
                // swipe starting there has to turn the page too — it is
                // still the deck, just the empty part of it.
                child: PageView.builder(
                  controller: _pages,
                  itemCount: layout.pages,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, page) => DeckGridView(
                    layout: layout,
                    page: page,
                    metrics: metrics,
                    cellRatio: cellRatio,
                    spacing: spacing,
                    cellBuilder: (context, index) {
                      final slot = layout.slots[index];
                      final item = slot == null
                          ? null
                          : DeckItem.parse(slot.value);
                      if (item == null) return const _EmptyCell();
                      // Renders itself, live — not pressable, unlike every
                      // other item below: there is nothing to send the
                      // host for a Clock or Calendar.
                      if (item case final WidgetItem widgetItem) {
                        return _DeckWidgetTile(item: widgetItem);
                      }
                      final iconKey = iconKeyFor(item);
                      if (iconKey != null) {
                        unawaited(session.ensureIcon(iconKey));
                      }
                      return _DeckButton(
                        item: item,
                        icon: iconKey == null ? null : session.iconFor(iconKey),
                        hasCustomBackground: session.backgroundImage != null,
                        showLabel: labels,
                        pressing: session.isPressing(item),
                        outcome: session.feedbackFor(item),
                        // slot.id is the host's own index for this button,
                        // carried unchanged however the deck is turned to
                        // fit the screen — nothing here needs to translate
                        // it back.
                        onPressed: () => _press(session, slot!.id, item),
                      );
                    },
                  ),
                ),
              ),
              if (layout.pages > 1 && session.showPageDots)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _PageDots(count: layout.pages, current: _page),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A quiet "something is coming in" hint for the corner of the deck,
/// rather than a spinner or banner that would compete with the buttons
/// for attention — see [HotkeyPadSession.isSyncing]. [IgnorePointer]
/// because it sits directly over the button grid's own corner; without
/// it, this would steal the tap a button underneath was meant to get.
class _SyncingBadge extends StatelessWidget {
  const _SyncingBadge({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: visible ? 1 : 0,
        child: Material(
          elevation: 2,
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onInverseSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.syncing,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which page of the deck is showing. Only drawn when there is more than
/// one, so a single-page deck loses no room to it.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var page = 0; page < count; page++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: page == current ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: page == current
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
      ],
    );
  }
}

/// Builds the deck's own visual stack — background, body, and (while the
/// link isn't ready) the connection overlay — as a standalone function
/// rather than inlined in [_DeckPageState.build], so a test can pump
/// exactly what production does instead of a hand-copied stand-in that
/// could silently drift from it.
///
/// Every child is wrapped in [Positioned.fill], [DeckBackground] included:
/// a [Stack] sizes itself from its non-positioned children alone, and
/// [DeckBackground]'s own `build()` returns a zero-size `SizedBox` for as
/// long as it has no image — forever, if none is ever configured. Passing
/// it to the [Stack] un-positioned would size the *whole deck* — every
/// sibling in it, [body] included — down to zero instead of leaving the
/// [Stack] to size from whatever space its own parent gives it.
Widget buildDeckStack({
  required Uint8List? backgroundImage,
  required double backgroundOpacity,
  required BackgroundFit backgroundFit,
  required Widget body,
  Widget? overlay,
}) {
  return Stack(
    children: [
      // Drawn first so the grid and every overlay above it composite on
      // top; a null image renders nothing.
      Positioned.fill(
        child: DeckBackground(
          image: backgroundImage,
          opacity: backgroundOpacity,
          fit: backgroundFit,
        ),
      ),
      Positioned.fill(child: body),
      if (overlay != null) Positioned.fill(child: overlay),
    ],
  );
}

/// The composition used in place of [buildDeckStack] whenever there is no
/// app bar — see [HotkeyPadSession.showAppBar] — to consume the notch/home
/// indicator inset a hidden [EdgeBarScaffold] would otherwise have
/// absorbed on its own edge.
///
/// The background is built and positioned *outside* the [SafeArea] rather
/// than [buildDeckStack] wrapped in one: a landscape phone's notch/Dynamic
/// Island moves to a side edge, and a wallpaper-style background is
/// exactly the thing that should bleed behind it rather than stop short
/// and show the [Scaffold]'s own colour there — only [body] and [overlay]
/// (real content, not decoration) need to stay clear of it. Confirmed
/// against a real device: wrapping the whole stack (background included)
/// in a [SafeArea] left a visible bar of blank space on the notch's edge
/// in landscape.
///
/// Public, and its own top-level [Scaffold] rather than folded into
/// [buildDeckStack] with a flag, so this exact layout can be pumped and
/// measured in a test without a whole `DeckPage`/`HotkeyPadSession` behind
/// it.
Widget buildFullBleedDeck({
  required Uint8List? backgroundImage,
  required double backgroundOpacity,
  required BackgroundFit backgroundFit,
  required Widget body,
  Widget? overlay,
}) {
  return Builder(
    // Matches EdgeBarScaffold's own backgroundColor exactly — a plain
    // Scaffold with none set falls back to colorScheme.surface, a
    // different (if subtly so) Material 3 tone than surfaceContainer,
    // which otherwise made toggling the app bar visibly shift the
    // deck's own background color underneath everything else.
    builder: (context) => Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Stack(
        children: [
          Positioned.fill(
            child: DeckBackground(
              image: backgroundImage,
              opacity: backgroundOpacity,
              fit: backgroundFit,
            ),
          ),
          SafeArea(
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Positioned.fill(child: body),
                  if (overlay != null) Positioned.fill(child: overlay),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The host's chosen background image, drawn behind the whole deck.
///
/// Public, not a private implementation detail of [DeckPage], so it can be
/// pumped in isolation — the same reason [IconPicker]-style widgets
/// elsewhere in this codebase are public — to check that a null image, a
/// mid-range opacity, and each fit mode all build without throwing.
class DeckBackground extends StatelessWidget {
  const DeckBackground({
    super.key,
    required this.image,
    required this.opacity,
    required this.fit,
  });

  /// Null means no custom background is set, or its bytes have not arrived
  /// yet — either way there is nothing to draw, and the deck's ordinary
  /// theme-derived background (the Scaffold's own) shows through.
  final Uint8List? image;

  /// 0 (invisible) to 1 (fully opaque); values outside that range are
  /// clamped rather than trusted, since this rides over BLE from a host
  /// build that might disagree about the range in the future.
  final double opacity;

  final BackgroundFit fit;

  /// The caller wraps this in `Positioned.fill`, not this widget itself:
  /// a `Stack` sizes itself from its non-positioned children alone, so if
  /// this returned a plain `SizedBox.shrink()` as an un-positioned child
  /// (the null-image case, true for as long as no background has loaded —
  /// which, with none configured, is forever) it would collapse the whole
  /// deck's `Stack` to zero size instead of leaving it to size from
  /// whatever space the scaffold around it actually gives it.
  @override
  Widget build(BuildContext context) {
    final bytes = image;
    if (bytes == null) return const SizedBox.shrink();
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Image.memory(bytes, fit: boxFitFor(fit), gaplessPlayback: true),
    );
  }
}

/// A slot the host left empty. Kept as a plain gap rather than skipped so
/// the grid holds its shape and the filled buttons stay where the user put
/// them; it used to carry a grey background of its own, which just read as
/// a blank, unfinished-looking box next to real icons.
class _EmptyCell extends StatelessWidget {
  const _EmptyCell();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// A placed Clock or Calendar widget, filling whatever space its own
/// row/column span was given — see [WidgetItem] and [DeckGridView], which
/// is what actually sizes that space.
class _DeckWidgetTile extends StatelessWidget {
  const _DeckWidgetTile({required this.item});

  final WidgetItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      // A tap here does nothing — there's no press to send the host for a
      // Clock or Calendar — but a first touch with no ripple and no haptic
      // at all reads as "is this broken?", the same way any other dead
      // spot on screen would. This is the same acknowledgement _DeckButton
      // gives a real press, without pretending there's a real one here.
      child: InkWell(
        onTap: () => unawaited(HapticFeedback.selectionClick()),
        child: LayoutBuilder(
          builder: (context, constraints) => switch (item.kind) {
            DeckWidgetKind.clock => AnalogClock(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            ),
            DeckWidgetKind.calendar => MonthCalendar(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            ),
          },
        ),
      ),
    );
  }
}

class _DeckButton extends StatelessWidget {
  const _DeckButton({
    required this.item,
    required this.icon,
    required this.hasCustomBackground,
    required this.showLabel,
    required this.pressing,
    required this.outcome,
    required this.onPressed,
  });

  final DeckItem item;
  final Uint8List? icon;

  /// Whether the deck has a custom background image behind it right now —
  /// see [glyphIconColors], the only thing this affects: an action's SVG
  /// glyph icon needs a background scrim to stay legible against an
  /// arbitrary photo, where it needs none sitting on the deck's own
  /// themed background.
  final bool hasCustomBackground;
  final bool showLabel;
  final bool pressing;

  /// Result of the last press: true succeeded, false failed, null idle.
  final bool? outcome;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A stable colour per app so buttons stay recognisable by position and
    // hue rather than by reading every label.
    final hue = (item.label.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
    final tint = HSLColor.fromAHSL(
      1,
      hue.toDouble(),
      0.45,
      theme.brightness == Brightness.dark ? 0.3 : 0.85,
    ).toColor();

    // A real icon brings its own colour, shape, and often its own padding —
    // a filled neutral square behind it just showed through that padding as
    // a flat grey box. The tint is what makes a letter placeholder
    // distinguishable at a glance, so it stays until a real icon arrives —
    // behind just the icon, not the label below it.
    final showIconBackground = icon == null;

    // Only actually used if icon turns out to be an SVG glyph — computed
    // unconditionally anyway since it is cheap and keeps the ternary below
    // from recomputing it three times.
    final glyphColors = glyphIconColors(
      brightness: theme.brightness,
      hasCustomBackground: hasCustomBackground,
    );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        // Without expand, the Column is only as wide as its widest child and
        // Stack aligns it to topStart, which pulls the icon off centre.
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The icon always fills the slot's full width, flush with the
            // top — no margin is reserved around it for a label. A labelled
            // cell is already taller than it is wide (see cellRatio below
            // this widget), so the label has the leftover height to itself,
            // under the icon, rather than the icon shrinking to make room.
            LayoutBuilder(
              builder: (context, constraints) {
                final iconSize = constraints.maxWidth;
                return Column(
                  children: [
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: !showIconBackground
                          ? null
                          : BoxDecoration(
                              color: tint,
                              borderRadius: BorderRadius.circular(
                                iconSize * 0.22,
                              ),
                            ),
                      clipBehavior: showIconBackground
                          ? Clip.antiAlias
                          : Clip.none,
                      // Every icon — an app's, a custom image, an emoji, or
                      // an action's built-in glyph — is rendered by the
                      // host (see iconKeyFor/GlyphIconStore), so this only
                      // ever has to decide between real bytes and a
                      // placeholder, never what kind of icon it is — with
                      // one exception: an action's glyph arrives as SVG
                      // with color placeholders (see looksLikeSvgIcon),
                      // since only the client knows what colors it needs
                      // to stay legible against its own theme/background.
                      child: icon == null
                          ? FittedBox(
                              // Shown only until the real icon arrives, or
                              // permanently for an item with no icon key at
                              // all (see iconKeyFor).
                              child: Text(
                                item.label.characters.first.toUpperCase(),
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                            )
                          : looksLikeSvgIcon(icon!)
                          ? SvgPicture.string(
                              recolorGlyphSvg(
                                utf8.decode(icon!),
                                border: glyphColors.border,
                                glyph: glyphColors.glyph,
                                background: glyphColors.background,
                              ),
                              fit: BoxFit.contain,
                            )
                          : Image.memory(
                              icon!,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              gaplessPlayback: true,
                            ),
                    ),
                    // The label sits directly under the icon; the cell's
                    // extra height (see cellRatio) falls below the text
                    // instead, via the Spacer.
                    if (showLabel) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            // Trimmed so the label does not float away from
                            // the icon on its own leading.
                            height: 1.1,
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ],
                );
              },
            ),

            // Covers the button rather than sitting beside it: at deck sizes
            // there is no room for a badge, and the whole button is the
            // thing that was pressed.
            if (pressing || outcome != null)
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  color: switch (outcome) {
                    true => Colors.green.withValues(alpha: 0.82),
                    false => theme.colorScheme.error.withValues(alpha: 0.82),
                    null => theme.colorScheme.surface.withValues(alpha: 0.6),
                  },
                  child: Center(
                    child: switch (outcome) {
                      true => const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 34,
                      ),
                      false => const Icon(
                        Icons.priority_high,
                        color: Colors.white,
                        size: 34,
                      ),
                      null => const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Covers the deck while the link is not usable.
///
/// Driven by the session's stage rather than pushed with `showDialog`: connect
/// moves through several stages in about a second, and a pushed route would
/// have to be popped in lockstep with them.
class _ConnectionOverlay extends StatelessWidget {
  const _ConnectionOverlay({
    required this.session,
    required this.deviceName,
    required this.onBack,
  });

  final HotkeyPadSession session;
  final String deviceName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final stage = session.stage;
    final working =
        stage == LinkStage.connecting ||
        stage == LinkStage.discovering ||
        stage == LinkStage.subscribing;
    final awaitingPin = stage == LinkStage.awaitingPin;
    final waiting = session.reconnectIn;

    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 360,
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: Card(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  // Scrollable rather than a bare Column: the maxHeight
                  // above is a soft cap for the common case, but the PIN
                  // form plus the keyboard it pops up together can still
                  // exceed it on a short screen — confirmed against a
                  // real overflow there. A plain Column would just clip
                  // silently in a release build; this instead lets the
                  // card scroll the few extra pixels instead of losing
                  // content off the bottom.
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (working)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        else if (awaitingPin)
                          Icon(
                            Icons.pin_outlined,
                            size: 32,
                            color: theme.colorScheme.primary,
                          )
                        else
                          Icon(
                            stage == LinkStage.failed
                                ? Icons.error_outline
                                : Icons.link_off,
                            size: 32,
                            color: stage == LinkStage.failed
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        const SizedBox(height: 16),
                        Text(
                          switch (stage) {
                            LinkStage.connecting =>
                              session.reconnectAttempt > 0
                                  ? l10n.reconnectingTo(deviceName)
                                  : l10n.connectingTo(deviceName),
                            LinkStage.discovering => l10n.discoveringServices,
                            LinkStage.subscribing => l10n.subscribingStage,
                            LinkStage.awaitingPin => l10n.enterCodeShownOn(
                              deviceName,
                            ),
                            LinkStage.disconnected => l10n.disconnectedStage,
                            LinkStage.failed => l10n.couldNotConnect,
                            LinkStage.ready => '',
                          },
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (awaitingPin) ...[
                          const SizedBox(height: 16),
                          _PinEntryForm(session: session),
                        ] else if (!working) ...[
                          const SizedBox(height: 8),
                          // No Flexible/SingleChildScrollView of its own
                          // here — the whole card scrolls now (see above),
                          // and a Flexible nested inside that outer scroll
                          // view would have nothing bounded to flex against.
                          Text(
                            // Both of these know exactly what went wrong
                            // and say so plainly — a wrong PIN and a
                            // typo'd address would otherwise look
                            // identical to any other dropped link (see
                            // pinRejectedDisconnect's own doc comment).
                            session.pinRejectedDisconnect
                                ? l10n.incorrectPinRetrying
                                : session.unresolvableHostError
                                ? l10n.couldNotFindAddress
                                : session.errorSummary ??
                                      l10n.linkLostTo(deviceName),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                          if (waiting != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              waiting == 0
                                  ? l10n.retryingNow
                                  : l10n.retryingInSeconds(
                                      waiting,
                                      session.reconnectAttempt,
                                    ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: onBack,
                                child: Text(l10n.back),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: session.connect,
                                icon: const Icon(Icons.refresh),
                                label: Text(
                                  waiting == null ? l10n.retry : l10n.retryNow,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Every WiFi host [HostHistoryStore] remembers, offered as a one-tap
/// reconnect — see [_DeckPageState._connectToHistoryEntry]. Most recent
/// first, matching the order [HostHistoryStore.load] already returns.
class _PreviousHostsList extends StatelessWidget {
  const _PreviousHostsList({
    required this.entries,
    required this.onSelect,
    required this.onForget,
  });

  final List<HostHistoryEntry> entries;
  final ValueChanged<HostHistoryEntry> onSelect;
  final ValueChanged<HostHistoryEntry> onForget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.previousHosts,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in entries)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(entry.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${entry.address}:${entry.port}'),
                    onTap: () => onSelect(entry),
                    trailing: IconButton(
                      tooltip: l10n.forgetHost,
                      icon: const Icon(Icons.close),
                      onPressed: () => onForget(entry),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A numbered heading for one step of
/// [_DeckPageState._methodChoiceScaffold] — a small badge instead of a
/// literal "1." in the translated string, so the wording stays a plain
/// sentence in every locale rather than something that has to embed a
/// digit correctly.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.title});

  final int step;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary,
          child: Text(
            '$step',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            textAlign: TextAlign.left,
            style: theme.textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

/// Step 1's address, shown as plain text rather than a link: HotkeyPad
/// Host runs on a computer, not this phone, so what a first-time user
/// needs is to get this address onto that other device — tapping it
/// copies it to the clipboard for pasting into a browser there, rather
/// than opening it in a browser here where it wouldn't help.
class _CopyableUrl extends StatelessWidget {
  const _CopyableUrl({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.copy_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option on [_DeckPageState._methodChoiceScaffold] — a big enough
/// tap target that picking a transport reads as a deliberate, considered
/// choice rather than a compact settings row.
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fallback for when discovery cannot reach the host — see
/// [_DeckPageState._connectManually]'s doc comment. Asks for just the
/// address; the port is a collapsed "Advanced" field defaulting to the
/// one real port ([WifiLink.tcpPort]) so the common case is one line.
class _ManualHostDialog extends StatefulWidget {
  const _ManualHostDialog();

  @override
  State<_ManualHostDialog> createState() => _ManualHostDialogState();
}

class _ManualHostDialogState extends State<_ManualHostDialog> {
  final _address = TextEditingController();
  final _port = TextEditingController();
  bool _showPort = false;

  /// Set on a failed [_submit], cleared as soon as the field changes
  /// again — a stale error sitting under text the user has already
  /// fixed reads as "still wrong" even after it no longer is.
  String? _addressError;

  @override
  void initState() {
    super.initState();
    _address.addListener(() {
      if (_addressError != null) setState(() => _addressError = null);
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    final address = _address.text.trim();
    if (!looksLikeIpv4(address)) {
      setState(
        () => _addressError = AppLocalizations.of(context)!.invalidHostAddress,
      );
      return;
    }
    Navigator.of(
      context,
    ).pop((address: address, port: resolveManualPort(_port.text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.enterHostIpTitle),
      // Scrollable rather than a bare Column: on a short screen the
      // on-screen keyboard alone can take up half the height, and once
      // the port field and an error line are both showing there is not
      // enough room left for a fixed-height column — confirmed against
      // a real overflow (the dialog's own buttons overlapping the
      // "Advanced" toggle) on a small phone profile.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.enterHostIpHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _address,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.ipAddressLabel,
                // A helper line rather than a realistic-looking hint
                // value (the previous "192.168.1.23" hint) — a hint sits
                // inside the field looking exactly like a typed value,
                // which is easy to mistake for one already filled in; a
                // helper line underneath can't be confused with real
                // input.
                helperText: l10n.ipAddressExample,
                errorText: _addressError,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_showPort) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.portLabel,
                  hintText: '${WifiLink.tcpPort}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showPort = true),
                  child: Text(l10n.advancedCustomPort),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.connectAction)),
      ],
    );
  }
}

/// The PIN entry box shown while [LinkStage.awaitingPin] — its own small
/// [StatefulWidget] purely to own a [TextEditingController]; everything it
/// actually needs to know (whether the last attempt was wrong) comes
/// straight from [session] rather than being duplicated in local state.
class _PinEntryForm extends StatefulWidget {
  const _PinEntryForm({required this.session});

  final HotkeyPadSession session;

  @override
  State<_PinEntryForm> createState() => _PinEntryFormState();
}

class _PinEntryFormState extends State<_PinEntryForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _controller.text.trim();
    if (pin.isEmpty) return;
    unawaited(widget.session.submitPin(pin));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: '000000',
            errorText: widget.session.pinError,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _submit, child: const Text('Connect')),
        ),
      ],
    );
  }
}
