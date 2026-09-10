import 'dart:async';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/material.dart';

import 'debug_page.dart';
import 'safe_insets.dart';
import 'settings_page.dart';
import 'session.dart';

class DeckPage extends StatefulWidget {
  const DeckPage({super.key, required this.peripheral, required this.name});

  final Peripheral peripheral;
  final String name;

  @override
  State<DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<DeckPage> {
  late final BtLinkSession _session;

  @override
  void initState() {
    super.initState();
    _session = BtLinkSession(peripheral: widget.peripheral, name: widget.name)
      ..start();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsPage(session: _session)),
    );
  }

  Future<void> _press(String appName) async {
    await _session.openApp(appName);
    if (!mounted) return;
    // The ack lands asynchronously; show whatever the host last said.
    final ack = _session.lastAck;
    if (ack != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ack), duration: const Duration(seconds: 2)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.name),
            actions: [
              IconButton(
                tooltip: 'Deck settings',
                onPressed: _openSettings,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: 'Debug console',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DebugPage(session: _session),
                  ),
                ),
                icon: const Icon(Icons.bug_report_outlined),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(child: _body()),
              // Built only while the link is unusable, so a connected deck
              // has nothing layered over it to absorb taps.
              if (_session.stage != LinkStage.ready)
                Positioned.fill(
                  child: _ConnectionOverlay(
                    session: _session,
                    deviceName: widget.name,
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _body() {
    final selected = _session.selected;

    if (selected.isEmpty) {
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
                'Your deck is empty.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Choose the apps you want one tap away.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune),
                label: const Text('Set up deck'),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: safeScrollPadding(context, horizontal: 12, vertical: 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Slightly taller than wide: the label strip takes the difference,
        // leaving the icon area square.
        childAspectRatio: 0.85,
      ),
      itemCount: selected.length,
      itemBuilder: (context, index) {
        final appName = selected[index];
        // Fills from the disk cache, or the host for anything new. Safe to
        // call on every build: the session ignores repeats.
        unawaited(_session.ensureIcon(appName));
        return _DeckButton(
          appName: appName,
          icon: _session.iconFor(appName),
          onPressed: () => _press(appName),
        );
      },
    );
  }
}

class _DeckButton extends StatelessWidget {
  const _DeckButton({
    required this.appName,
    required this.icon,
    required this.onPressed,
  });

  final String appName;
  final Uint8List? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A stable colour per app so buttons stay recognisable by position and
    // hue rather than by reading every label.
    final hue = (appName.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
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
        child: Column(
          children: [
            // The icon claims everything the label does not, so the whole
            // button reads as the app rather than as a chip with a picture.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: icon != null
                    ? Image.memory(
                        icon!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      )
                    : Center(
                        child: FittedBox(
                          child: Text(
                            appName.characters.first.toUpperCase(),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(
                appName,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
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
