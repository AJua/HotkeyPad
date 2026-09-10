import 'package:flutter/material.dart';

import 'session.dart';

/// Chooses which of the host's apps appear on the deck, and in what order.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.session});

  final BtLinkSession session;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text.trim()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DeckApp> _catalogue(BtLinkSession session) {
    if (_query.isEmpty) return session.apps;
    final needle = _query.toLowerCase();
    return session.apps
        .where((app) => app.name.toLowerCase().contains(needle))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final session = widget.session;
        final selected = session.selected;
        final catalogue = _catalogue(session);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Deck settings'),
            actions: [
              IconButton(
                tooltip: 'Reload apps from host',
                onPressed: session.ready ? session.refreshApps : null,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              _header(context, 'On the deck (${selected.length})'),
              if (selected.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Nothing chosen yet. Tick apps below to add them.',
                    ),
                  ),
                )
              else
                SliverReorderableList(
                  itemCount: selected.length,
                  onReorder: session.reorderSelection,
                  itemBuilder: (context, index) {
                    final name = selected[index];
                    final onHost =
                        session.apps.isEmpty ||
                        session.apps.any((app) => app.name == name);
                    return Material(
                      key: ValueKey('selected:$name'),
                      child: ListTile(
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        title: Text(name),
                        subtitle: onHost
                            ? null
                            : const Text('not found on the host'),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          onPressed: () => session.toggleSelection(name),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ),
                    );
                  },
                ),
              _header(context, 'All apps on the host'),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: session.apps.isEmpty
                          ? 'Waiting for the catalogue...'
                          : 'Search ${session.apps.length} apps',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
              ),
              if (session.loadingApps)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (catalogue.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        session.apps.isEmpty
                            ? 'The host has not sent its app list yet.'
                            : 'No app matches "$_query".',
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: catalogue.length,
                  itemBuilder: (context, index) {
                    final app = catalogue[index];
                    return CheckboxListTile(
                      value: session.isSelected(app.name),
                      onChanged: (_) => session.toggleSelection(app.name),
                      title: Text(app.name),
                      subtitle: Text(app.category),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
