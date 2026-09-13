import 'dart:async';
import 'dart:math' as math;

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debug_page.dart';
import 'edge_bar.dart';
import 'safe_insets.dart';
import 'deck_icons.dart';
import 'protocol.dart';
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
  }

  @override
  void dispose() {
    _searchTimeout?.cancel();
    _stateChanges?.cancel();
    _discovery?.cancel();
    if (_searching) _central?.stopDiscovery();
    _pages.dispose();
    _session?.dispose();
    super.dispose();
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

  /// Takes the first host that answers. With one Mac in the room there is
  /// nothing to choose between, and a picker would just be a step to dismiss.
  void _adopt(Peripheral peripheral, String? name) {
    if (_session != null) return;
    _stopSearch();
    if (!mounted) return;
    setState(() {
      _session = BtLinkSession(
        peripheral: peripheral,
        name: name?.isNotEmpty == true ? name! : BtLink.advertisedName,
      )
        ..onTheme = widget.onTheme
        ..start();
    });
  }

  Future<void> _press(BtLinkSession session, int index, DeckItem item) async {
    // Fires before the round trip: the deck should feel like a button, not
    // like a form that submits.
    unawaited(HapticFeedback.selectionClick());
    await session.press(index, item);
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
          child: Stack(
            children: [
              Positioned.fill(child: _body(session)),
              // Built only while the link is unusable, so a connected deck
              // has nothing layered over it to absorb taps.
              if (session.stage != LinkStage.ready)
                Positioned.fill(
                  child: _ConnectionOverlay(
                    session: session,
                    deviceName: session.name,
                    onBack: _forget,
                  ),
                ),
            ],
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
    // The host edits one shape; the deck turns it to fit the screen it is
    // actually on, so a 5x3 landscape grid becomes 3x5 upright.
    final layout = stored?.orientedFor(
      portrait: MediaQuery.orientationOf(context) == Orientation.portrait,
    );

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
                session.loadingLayout
                    ? 'Loading the deck...'
                    : 'No deck yet.',
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
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
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
          padding: EdgeInsets.only(
            top: padding.top,
            bottom: padding.bottom,
          ),
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
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: layout.columns,
                              mainAxisSpacing: spacing,
                              crossAxisSpacing: spacing,
                              childAspectRatio: cellRatio,
                            ),
                        itemCount: layout.pageCapacity,
                        itemBuilder: (context, cell) {
                          final index = layout.indexOf(page: page, cell: cell);
                          final stored = layout.slots[index];
                          final item = stored == null
                              ? null
                              : DeckItem.parse(stored);
                          if (item == null) return const _EmptyCell();
                          if (item is AppItem && item.emoji == null) {
                            unawaited(session.ensureIcon(item.name));
                          }
                          return _DeckButton(
                            item: item,
                            icon: item is AppItem
                                ? session.iconFor(item.name)
                                : null,
                            showLabel: labels,
                            pressing: session.isPressing(item),
                            outcome: session.feedbackFor(item),
                            onPressed: () => _press(session, index, item),
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

/// A slot the host left empty. Drawn rather than skipped so the grid keeps
/// its shape and buttons stay where the user put them.
class _EmptyCell extends StatelessWidget {
  const _EmptyCell();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(
          alpha: 0.4,
        ),
      ),
    );
  }
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
      // A real icon brings its own colour and shape, so it sits on a neutral
      // surface. The tint is what makes a letter placeholder distinguishable
      // at a glance, so it stays until the icon arrives.
      color: icon != null ? theme.colorScheme.surfaceContainerHighest : tint,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        // Without expand, the Column is only as wide as its widest child and
        // Stack aligns it to topStart, which pulls the icon off centre.
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The icon is sized so the space above it matches the space at
            // its sides, which is what makes the padding read as even. Filling
            // the cell instead left a wide gap above the icon and a cramped
            // one between it and the label.
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                // With a label the icon leaves room for it and for even
                // margins; without one it takes the whole cell.
                final iconSize = showLabel ? width * 0.72 : width;
                final margin = (width - iconSize) / 2;
                return Column(
                  children: [
                    SizedBox(height: margin),
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
                                  fontSize: iconSize * 0.78,
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
                    // The label belongs to the icon, so it sits directly
                    // under it; the leftover height falls below the text
                    // instead, where it matches the margin at the icon's
                    // sides. The gap is nearly nothing because the text's
                    // own line height already provides the visible space.
                    if (showLabel) ...[
                      SizedBox(height: margin * 0.05),
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
