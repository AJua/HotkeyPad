import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_launcher.dart';
import 'deck_icons.dart';
import 'layout_store.dart';
import 'protocol.dart';

/// Edits the grid the client will draw.
///
/// Lives on the host because a phone screen is a poor place to arrange a
/// grid, and the host is where the app list already is.
class LayoutPage extends StatefulWidget {
  const LayoutPage({super.key, required this.onChanged});

  /// Called after every edit so the service can push the new layout to
  /// connected clients.
  final ValueChanged<DeckLayout> onChanged;

  @override
  State<LayoutPage> createState() => _LayoutPageState();
}

class _LayoutPageState extends State<LayoutPage> {
  DeckLayout _layout = DeckLayout.empty();
  int _page = 0;
  var _apps = <({String name, String category, String path})>[];
  final _icons = <String, Uint8List?>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final layout = await LayoutStore.load();
    final apps = await AppLauncher.list();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _apps = apps;
      _loading = false;
    });
  }

  /// Icons are fetched lazily and kept, including the misses: an app with no
  /// icon should not be asked for again on every rebuild.
  Future<void> _ensureIcon(String appName) async {
    if (_icons.containsKey(appName)) return;
    _icons[appName] = null;
    final path = _apps
        .where((app) => app.name == appName)
        .map((app) => app.path)
        .firstOrNull;
    if (path == null) return;
    final bytes = await AppLauncher.icon(path, size: BtLink.iconSize);
    if (!mounted || bytes == null) return;
    setState(() => _icons[appName] = bytes);
  }

  Future<void> _apply(DeckLayout layout) async {
    setState(() {
      _layout = layout;
      _clampPage();
    });
    await LayoutStore.save(layout);
    widget.onChanged(layout);
  }

  /// Keeps the visible page valid when pages are removed.
  void _clampPage() {
    if (_page >= _layout.pages) _page = _layout.pages - 1;
  }

  Future<void> _pick(int index) async {
    final chosen = await showDialog<DeckItemChoice>(
      context: context,
      builder: (context) => _PickerDialog(
        apps: _apps,
        current: _layout.slots[index],
      ),
    );
    if (chosen == null) return;
    await _apply(_layout.withSlot(index, chosen.stored));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                'Deck layout',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              _SizeStepper(
                label: 'Columns',
                value: _layout.columns,
                onChanged: (value) =>
                    _apply(_layout.resized(columns: value)),
              ),
              const SizedBox(width: 16),
              _SizeStepper(
                label: 'Rows',
                value: _layout.rows,
                onChanged: (value) => _apply(_layout.resized(rows: value)),
              ),
              const SizedBox(width: 16),
              _SizeStepper(
                label: 'Pages',
                value: _layout.pages,
                max: DeckLayout.maxPages,
                onChanged: (value) => _apply(_layout.resized(pages: value)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Click a cell to choose what it does. Drag a button to move it, '
            'including onto another page.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_layout.pages > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                for (var page = 0; page < _layout.pages; page++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _PageTab(
                      index: page,
                      selected: page == _page,
                      onSelected: () => setState(() => _page = page),
                      // Dropping a button on a tab moves it to that page,
                      // which is the only way to reach a page that is not
                      // currently shown.
                      onDropped: (from) => _apply(
                        _layout.moved(
                          from,
                          _layout.indexOf(page: page, cell: 0),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                final cellWidth =
                    (constraints.maxWidth - spacing * (_layout.columns - 1)) /
                    _layout.columns;
                final cellHeight =
                    (constraints.maxHeight - spacing * (_layout.rows - 1)) /
                    _layout.rows;
                return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _layout.columns,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                // Mirrors what the phone will show.
                childAspectRatio: cellHeight <= 0 ? 1 : cellWidth / cellHeight,
              ),
              itemCount: _layout.pageCapacity,
              itemBuilder: (context, cell) {
                final index = _layout.indexOf(page: _page, cell: cell);
                final stored = _layout.slots[index];
                final item = stored == null ? null : DeckItem.parse(stored);
                if (item is AppItem) unawaited(_ensureIcon(item.name));
                return _Cell(
                  index: index,
                  item: item,
                  icon: item is AppItem ? _icons[item.name] : null,
                  onTap: () => _pick(index),
                  onClear: stored == null
                      ? null
                      : () => _apply(_layout.withSlot(index, null)),
                  onMoved: (from) => _apply(_layout.moved(from, index)),
                );
              },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.item,
    required this.icon,
    required this.onTap,
    required this.onClear,
    required this.onMoved,
  });

  final int index;
  final DeckItem? item;
  final Uint8List? icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final ValueChanged<int> onMoved;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onMoved(details.data),
      builder: (context, candidate, _) {
        final highlighted = candidate.isNotEmpty;
        final content = _content(context, highlighted);
        if (item == null) return content;
        return Draggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: SizedBox(width: 110, height: 120, child: content),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: content),
          child: content,
        );
      },
    );
  }

  Widget _content(BuildContext context, bool highlighted) {
    final theme = Theme.of(context);
    final filled = item != null;

    return Material(
      color: highlighted
          ? theme.colorScheme.primaryContainer
          : filled
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (!filled)
              Center(
                child: Icon(
                  Icons.add,
                  color: theme.colorScheme.outline,
                ),
              )
            else
              Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: icon != null
                          ? Image.memory(icon!, fit: BoxFit.contain)
                          : Center(
                              child: FittedBox(
                                child: item is ActionItem
                                    ? Icon(deckFallbackIcon(item!), size: 36)
                                    : Text(
                                        item!.label.characters.first
                                            .toUpperCase(),
                                        style: theme.textTheme.headlineMedium,
                                      ),
                              ),
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                    child: Text(
                      item!.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            if (onClear != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  tooltip: 'Clear',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SizeStepper extends StatelessWidget {
  const _SizeStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 8,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        IconButton(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          visualDensity: VisualDensity.compact,
        ),
        Text('$value'),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// What the picker returns.
class DeckItemChoice {
  const DeckItemChoice(this.stored);
  final String stored;
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({required this.apps, required this.current});

  final List<({String name, String category, String path})> apps;
  final String? current;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
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

  @override
  Widget build(BuildContext context) {
    final needle = _query.toLowerCase();
    final apps = _query.isEmpty
        ? widget.apps
        : widget.apps
              .where((app) => app.name.toLowerCase().contains(needle))
              .toList();

    return AlertDialog(
      title: const Text('Choose a button'),
      content: SizedBox(
        width: 420,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search apps',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (_query.isEmpty) ...[
                    const _SectionLabel('Media controls'),
                    for (final action in DeckAction.values)
                      ListTile(
                        leading: Icon(deckFallbackIcon(ActionItem(action))),
                        title: Text(action.label),
                        selected:
                            widget.current == ActionItem(action).stored,
                        onTap: () => Navigator.of(context).pop(
                          DeckItemChoice(ActionItem(action).stored),
                        ),
                      ),
                  ],
                  const _SectionLabel('Applications'),
                  for (final app in apps)
                    ListTile(
                      leading: const Icon(Icons.apps),
                      title: Text(app.name),
                      subtitle: Text(app.category),
                      selected: widget.current == AppItem(app.name).stored,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(DeckItemChoice(AppItem(app.name).stored)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/// A page selector that is also a drop target, so a button can be dragged to
/// a page that is not currently shown.
class _PageTab extends StatelessWidget {
  const _PageTab({
    required this.index,
    required this.selected,
    required this.onSelected,
    required this.onDropped,
  });

  final int index;
  final bool selected;
  final VoidCallback onSelected;
  final ValueChanged<int> onDropped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<int>(
      onAcceptWithDetails: (details) => onDropped(details.data),
      builder: (context, candidate, _) => InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: candidate.isNotEmpty
                ? theme.colorScheme.primaryContainer
                : selected
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.surfaceContainerLow,
          ),
          child: Text('Page ${index + 1}'),
        ),
      ),
    );
  }
}
