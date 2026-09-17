import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'safe_insets.dart';
import 'session.dart';

/// [LinkStage] itself carries only a fixed English label — this maps it to
/// the localized, compact form shown in the debug console's app bar
/// instead (the full-sentence, name-taking versions on `_ConnectionOverlay`
/// don't fit a one-line status bar).
String _stageLabel(AppLocalizations l10n, LinkStage stage) => switch (stage) {
  LinkStage.connecting => l10n.debugStageConnecting,
  LinkStage.discovering => l10n.debugStageDiscovering,
  LinkStage.subscribing => l10n.debugStageSubscribing,
  LinkStage.awaitingPin => l10n.debugStageAwaitingPin,
  LinkStage.ready => l10n.debugStageReady,
  LinkStage.disconnected => l10n.debugStageDisconnected,
  LinkStage.failed => l10n.debugStageFailed,
};

/// The old chat screen, kept as a diagnostic tool: it shows every message on
/// the link and can push free text at the host.
class DebugPage extends StatefulWidget {
  const DebugPage({super.key, required this.session});

  /// Null while the app is still looking for a host — the device scanner is
  /// useful precisely then.
  final HotkeyPadSession? session;

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  final _composer = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final session = widget.session;
    final text = _composer.text.trim();
    if (session == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await session.sendDebugText(text);
    if (!mounted) return;
    setState(() {
      _composer.clear();
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = widget.session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.debugConsole)),
        body: Center(child: Text(l10n.notConnectedToHostYet)),
      );
    }

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final log = session.log;
        final ready = session.ready;
        final mtu = session.mtu;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.debugConsole),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(24),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${_stageLabel(l10n, session.stage)}'
                  '${mtu != null ? ' · ${l10n.mtuLabel(mtu)}' : ''}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: log.isEmpty
                    ? Center(child: Text(l10n.noTrafficYet))
                    : ListView.builder(
                        padding: safeScrollPadding(
                          context,
                          horizontal: 12,
                          vertical: 12,
                        ),
                        itemCount: log.length,
                        itemBuilder: (context, index) =>
                            _Bubble(message: log[log.length - 1 - index]),
                        reverse: true,
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composer,
                          enabled: ready && !_sending,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: l10n.sendRawTextHint,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: ready && !_sending ? _send : null,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final LinkMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final time = TimeOfDay.fromDateTime(message.at);
    return Align(
      alignment: message.inbound
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: message.inbound
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 2),
            Text(
              '${message.inbound ? l10n.messageFromHost : l10n.messageSent} · '
              '${time.hour.toString().padLeft(2, '0')}:'
              '${time.minute.toString().padLeft(2, '0')}',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
