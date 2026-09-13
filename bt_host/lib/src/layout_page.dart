import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_launcher.dart';
import 'deck_icons.dart';
import 'layout_store.dart';
import 'settings_store.dart';
import 'protocol.dart';

/// Edits the grid the client will draw.
///
/// Lives on the host because a phone screen is a poor place to arrange a
/// grid, and the host is where the app list already is.
class LayoutPage extends StatefulWidget {
  const LayoutPage({
    super.key,
    required this.onChanged,
    required this.onThemeChanged,
  });

  /// Called after every edit so the service can push the new layout to
  /// connected clients.
  final ValueChanged<DeckLayout> onChanged;

  /// Called when the appearance is changed, so it can be applied here and
  /// pushed to the phone.
  final ValueChanged<DeckTheme> onThemeChanged;

  @override
  State<LayoutPage> createState() => _LayoutPageState();
}

class _LayoutPageState extends State<LayoutPage> {
  DeckLayout _layout = DeckLayout.empty();
  DeckTheme _theme = DeckTheme.system;
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
    final theme = await SettingsStore.loadTheme();
    final apps = await AppLauncher.list();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _theme = theme;
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

  Future<void> _setTheme(DeckTheme theme) async {
    setState(() => _theme = theme);
    await SettingsStore.saveTheme(theme);
    widget.onThemeChanged(theme);
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
              const SizedBox(width: 24),
              SegmentedButton<DeckTheme>(
                segments: [
                  for (final theme in DeckTheme.values)
                    ButtonSegment(value: theme, label: Text(theme.label)),
                ],
                selected: {_theme},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _setTheme(selection.first),
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
            child: LayoutGrid(
              layout: _layout,
              page: _page,
              iconFor: (appName) {
                unawaited(_ensureIcon(appName));
                return _icons[appName];
              },
              onPick: _pick,
              onClear: (index) => _apply(_layout.withSlot(index, null)),
              onMove: (from, to) => _apply(_layout.moved(from, to)),
            ),
          ),
        ),
      ],
    );
  }
}

/// The editable grid for one page.
///
/// Deliberately free of storage and platform channels: it takes a layout and
/// reports edits, which is what makes the drag behaviour testable.
class LayoutGrid extends StatelessWidget {
  const LayoutGrid({
    super.key,
    required this.layout,
    required this.page,
    required this.iconFor,
    required this.onPick,
    required this.onClear,
    required this.onMove,
  });

  final DeckLayout layout;
  final int page;
  final Uint8List? Function(String appName) iconFor;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onClear;

  /// Called with the source and destination slot indices.
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        // Same proportions the phone draws, so this previews rather than
        // approximates.
        const cellRatio = 0.86;
        final cellWidth = math.min(
          (constraints.maxWidth - spacing * (layout.columns - 1)) /
              layout.columns,
          (constraints.maxHeight - spacing * (layout.rows - 1)) /
              layout.rows *
              cellRatio,
        );
        final cellHeight = cellWidth / cellRatio;
        return Center(
          child: SizedBox(
            width: cellWidth * layout.columns + spacing * (layout.columns - 1),
            height: cellHeight * layout.rows + spacing * (layout.rows - 1),
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
              itemBuilder: (context, cellIndex) {
                final index = layout.indexOf(page: page, cell: cellIndex);
                final stored = layout.slots[index];
                final item = stored == null ? null : DeckItem.parse(stored);
                return _Cell(
                  index: index,
                  item: item,
                  icon: item is AppItem ? iconFor(item.name) : null,
                  onTap: () => onPick(index),
                  onClear: stored == null ? null : () => onClear(index),
                  onMoved: (from) => onMove(from, index),
                );
              },
            ),
          ),
        );
      },
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
      key: ValueKey('cell-$index'),
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
        // Same reason as the client: a bare Stack aligns its non-positioned
        // child to topStart, leaving the icon off centre.
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!filled)
              Center(
                child: Icon(
                  Icons.add,
                  color: theme.colorScheme.outline,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final iconSize = width * 0.72;
                  final margin = (width - iconSize) / 2;
                  return Column(
                    children: [
                      SizedBox(height: margin),
                      SizedBox(
                        width: iconSize,
                        height: iconSize,
                        child: icon != null
                            ? Image.memory(icon!, fit: BoxFit.contain)
                            : FittedBox(
                                child: item is ActionItem
                                    ? Icon(deckFallbackIcon(item!))
                                    : Text(
                                        item!.label.characters.first
                                            .toUpperCase(),
                                        style:
                                            theme.textTheme.headlineMedium,
                                      ),
                              ),
                      ),
                      SizedBox(height: margin * 0.05),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          item!.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            height: 1.1,
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  );
                },
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
