import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'background_fit.dart';
import 'debug_page.dart';
import 'edge_bar.dart';
import 'link_target.dart';
import 'safe_insets.dart';
import 'deck_icons.dart';
import 'package:bt_link_protocol/bt_link_protocol.dart';
import 'session.dart';

/// The app's home. Finds a host by itself rather than making the user pick
/// one: there is normally exactly one Mac to talk to, and choosing it from a
/// list of every radio in the room is a chore, not a feature.
class DeckPage extends StatefulWidget {
  const DeckPage({super.key, required this.onTheme});

  /// Reports the appearance the host asked for, so the app can apply it.
  final ValueChanged<DeckTheme> onTheme;

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  final _pages = PageController();
  int _page = 0;

  CentralManager? _central;
  BtLinkSession? _session;
  StreamSubscription? _discovery;
  StreamSubscription? _stateChanges;
  var _state = BluetoothLowEnergyState.unknown;
  bool _askedForPermission = false;
  Timer? _searchTimeout;
  Object? _searchError;
  bool _searching = false;

  /// WiFi's own discovery, alongside Bluetooth's — bound independently of
  /// [_central]/[_state] since WiFi needs neither an adapter nor a runtime
  /// permission, so it must not be gated behind Bluetooth's own state
  /// machine below; see [_startWifiDiscovery].
  RawDatagramSocket? _wifiDiscovery;

  @override
  void initState() {
    super.initState();
    try {
      final central = CentralManager();
      _central = central;
      _state = central.state;
      _stateChanges = central.stateChanged.listen((event) {
        if (!mounted) return;
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
    // Independent of the Bluetooth branch above — WiFi races Bluetooth for
    // the same host, so it starts regardless of whether this platform even
    // has a Bluetooth implementation.
    unawaited(_startWifiDiscovery());
  }

  @override
  void dispose() {
    _searchTimeout?.cancel();
    _stateChanges?.cancel();
    _discovery?.cancel();
    if (_searching) _central?.stopDiscovery();
    _stopWifiDiscovery();
    _pages.dispose();
    _session?.dispose();
    super.dispose();
  }

  /// Listens for the host's UDP beacon (see `bt_host`'s `WifiServer`) —
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
        if (!event.advertisement.serviceUUIDs.contains(BtLink.serviceUuid)) {
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
        'No BTLink host is advertising nearby. Check that the host is '
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
    if (_searching) _central?.stopDiscovery();
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
          BtLinkSession(
              target: BleTarget(peripheral),
              name: name?.isNotEmpty == true ? name! : BtLink.advertisedName,
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
          BtLinkSession(
              target: WifiTarget(
                hostId: beacon.hostId,
                address: address,
                port: beacon.port,
              ),
              name: beacon.name.isNotEmpty ? beacon.name : BtLink.advertisedName,
            )
            ..onTheme = widget.onTheme
            ..start();
    });
  }

  Future<void> _press(BtLinkSession session, int id, DeckItem item) async {
    // Fires before the round trip: the deck should feel like a button, not
    // like a form that submits.
    unawaited(HapticFeedback.selectionClick());
    await session.press(id, item);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) return _searchScaffold(context);

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return EdgeBarScaffold(
          side: barSideFor(context),
          title: session.name,
          actions: [
            IconButton(
              tooltip: 'Debug console',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DebugPage(session: session)),
              ),
              icon: const Icon(Icons.bug_report_outlined),
            ),
          ],
          child: buildDeckStack(
            backgroundImage: session.backgroundImage,
            backgroundOpacity: session.backgroundOpacity,
            backgroundFit: session.backgroundFit,
            body: _body(session),
            // Built only while the link is unusable, so a connected deck
            // has nothing layered over it to absorb taps.
            overlay: session.stage != LinkStage.ready
                ? _ConnectionOverlay(
                    session: session,
                    deviceName: session.name,
                    onBack: _forget,
                  )
                : null,
          ),
        );
      },
    );
  }

  /// Drops the current host and looks again — the only way back to a
  /// different Mac now that there is no picker.
  void _forget() {
    _session?.dispose();
    setState(() => _session = null);
    _search();
  }

  Widget _searchScaffold(BuildContext context) {
    final error = _searchError;
    return EdgeBarScaffold(
      side: barSideFor(context),
      title: 'BTLink',
      actions: [
        IconButton(
          tooltip: 'Debug console',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DebugPage(session: null)),
          ),
          icon: const Icon(Icons.bug_report_outlined),
        ),
      ],
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
                  'Looking for a host',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Start the BTLink host on your Mac.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ] else ...[
                Icon(
                  Icons.bluetooth_disabled,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'No host found',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error is StateError ? error.message : '$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Search again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BtLinkSession session) {
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
                'Arrange the buttons in the BTLink host on your Mac.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    // Every button visible at once is the point of a deck, so the grid is
    // sized to fit rather than scrolled. Cells stay square and the block is
    // centred: stretching them to fill would make buttons wide in landscape
    // and tall in portrait, and leave the margins uneven once the app bar
    // has taken one edge.
    //
    // Pulling down retries any icon that never arrived (see
    // BtLinkSession.refreshIcons) — a dropped frame otherwise has no way to
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
    return LayoutBuilder(
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
    );
  }

  Widget _deck(BtLinkSession session, DeckLayout layout) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        const margin = 12.0;
        // Taller than wide when there are labels, since the text needs a
        // band of its own. Without labels there is nothing to leave room
        // for, so cells go square and the icon fills them.
        final labels = session.showLabels;
        final cellRatio = labels ? 0.86 : 1.0;
        final padding = safeScrollPadding(
          context,
          horizontal: margin,
          vertical: margin,
        );
        final dots = layout.pages > 1 ? 28.0 : 0.0;

        final freeWidth =
            constraints.maxWidth -
            padding.horizontal -
            spacing * (layout.columns - 1);
        final freeHeight =
            constraints.maxHeight -
            padding.vertical -
            dots -
            spacing * (layout.rows - 1);

        // Whichever axis runs out first decides the cell width; the other
        // axis keeps its spare room as even margin on both sides.
        final cellWidth = math.min(
          freeWidth / layout.columns,
          freeHeight / layout.rows * cellRatio,
        );
        final cellHeight = cellWidth / cellRatio;
        final gridWidth =
            cellWidth * layout.columns + spacing * (layout.columns - 1);
        final gridHeight =
            cellHeight * layout.rows + spacing * (layout.rows - 1);

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
                  itemBuilder: (context, page) => Center(
                    child: SizedBox(
                      width: gridWidth.isFinite && gridWidth > 0
                          ? gridWidth
                          : null,
                      height: gridHeight.isFinite && gridHeight > 0
                          ? gridHeight
                          : null,
                      child: GridView.builder(
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: layout.columns,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: cellRatio,
                        ),
                        itemCount: layout.pageCapacity,
                        itemBuilder: (context, cell) {
                          final index = layout.indexOf(page: page, cell: cell);
                          final slot = layout.slots[index];
                          final item = slot == null
                              ? null
                              : DeckItem.parse(slot.value);
                          if (item == null) return const _EmptyCell();
                          final iconKey = item.emoji == null
                              ? iconKeyFor(item)
                              : null;
                          if (iconKey != null) {
                            unawaited(session.ensureIcon(iconKey));
                          }
                          return _DeckButton(
                            item: item,
                            icon: iconKey == null
                                ? null
                                : session.iconFor(iconKey),
                            showLabel: labels,
                            pressing: session.isPressing(item),
                            outcome: session.feedbackFor(item),
                            // slot.id is the host's own index for this
                            // button, carried unchanged however the deck is
                            // turned to fit the screen — nothing here needs
                            // to translate it back.
                            onPressed: () => _press(session, slot!.id, item),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (layout.pages > 1)
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

class _DeckButton extends StatelessWidget {
  const _DeckButton({
    required this.item,
    required this.icon,
    required this.showLabel,
    required this.pressing,
    required this.outcome,
    required this.onPressed,
  });

  final DeckItem item;
  final Uint8List? icon;
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

    return Material(
      // A real icon brings its own colour, shape, and often its own
      // padding — a filled neutral square behind it just showed through
      // that padding as a flat grey box. The tint is what makes a letter
      // placeholder distinguishable at a glance, so it stays until a real
      // icon arrives.
      color: icon != null ? Colors.transparent : tint,
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
                    SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: item.emoji != null
                          // Sized explicitly rather than with a FittedBox:
                          // an emoji's advance box is wider than its glyph,
                          // so fitting the box leaves the glyph small and
                          // off to one side.
                          ? Center(
                              child: Text(
                                item.emoji!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: iconSize * 0.82,
                                  height: 1,
                                ),
                              ),
                            )
                          : icon != null
                          ? Image.memory(
                              icon!,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              gaplessPlayback: true,
                            )
                          : FittedBox(
                              // An action has a meaningful glyph; an app that
                              // has not sent its icon yet only has its initial.
                              child: item is ActionItem
                                  ? Icon(
                                      deckFallbackIcon(item),
                                      color: theme.colorScheme.onSurface,
                                    )
                                  : Text(
                                      item.label.characters.first.toUpperCase(),
                                      style: theme.textTheme.displaySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.55),
                                          ),
                                    ),
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

  final BtLinkSession session;
  final String deviceName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = session.stage;
    final working =
        stage == LinkStage.connecting ||
        stage == LinkStage.discovering ||
        stage == LinkStage.subscribing;
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (working)
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
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
                                ? 'Reconnecting to $deviceName'
                                : 'Connecting to $deviceName',
                          LinkStage.discovering => 'Discovering services',
                          LinkStage.subscribing => 'Subscribing',
                          LinkStage.disconnected => 'Disconnected',
                          LinkStage.failed => 'Could not connect',
                          LinkStage.ready => '',
                        },
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (!working) ...[
                        const SizedBox(height: 8),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Text(
                              session.errorSummary ??
                                  'The link to $deviceName was lost.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                        if (waiting != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            waiting == 0
                                ? 'Retrying now...'
                                : 'Retrying in ${waiting}s'
                                      ' · attempt ${session.reconnectAttempt}',
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
                              child: const Text('Back'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: session.connect,
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                waiting == null ? 'Retry' : 'Retry now',
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
      ],
    );
  }
}
