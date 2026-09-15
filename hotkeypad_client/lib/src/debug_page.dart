import 'package:flutter/material.dart';

import 'safe_insets.dart';
import 'scan_page.dart';
import 'session.dart';

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
    final session = widget.session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Debug console'),
          actions: [_scanAction(context)],
        ),
        body: const Center(child: Text('Not connected to a host yet.')),
      );
    }

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final log = session.log;
        final ready = session.ready;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Debug console'),
            actions: [_scanAction(context)],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(24),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${session.stage.label}'
                  '${session.mtu != null ? ' · MTU ${session.mtu}' : ''}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: log.isEmpty
                    ? const Center(child: Text('No traffic yet.'))
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
                          decoration: const InputDecoration(
                            hintText: 'Send raw text to the host',
                            border: OutlineInputBorder(),
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

  Widget _scanAction(BuildContext context) {
    return IconButton(
      tooltip: 'Nearby devices',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ScanPage())),
      icon: const Icon(Icons.bluetooth_searching),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final LinkMessage message;

  @override
  Widget build(BuildContext context) {
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
              '${message.inbound ? 'host' : 'sent'} · '
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
