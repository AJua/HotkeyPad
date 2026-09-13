import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_launcher.dart';
import 'command_runner.dart';
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
    required this.onAppearanceChanged,
    required this.onShowService,
  });

  /// Called after every edit so the service can push the new layout to
  /// connected clients.
  final ValueChanged<DeckLayout> onChanged;

  /// Called when the appearance changes, so it can be applied here and
  /// pushed to the phone.
  final void Function(DeckTheme theme, bool showLabels) onAppearanceChanged;

  /// Opens the service view, which is reached from the settings dialog now
  /// that there are no tabs.
  final VoidCallback onShowService;

  @override
  State<LayoutPage> createState() => _LayoutPageState();
}

class _LayoutPageState extends State<LayoutPage> {
  DeckLayout _layout = DeckLayout.empty();
  DeckTheme _theme = DeckTheme.system;
  bool _showLabels = true;
  int _page = 0;
  var _apps = <({String name, String category, String path})>[];
  var _shortcuts = <String>[];
  final _icons = <String, Uint8List?>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final layout = await LayoutStore.load();
    final appearance = await SettingsStore.load();
    final apps = await AppLauncher.list();
    final shortcuts = await CommandRunner.listShortcuts();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _theme = appearance.theme;
      _showLabels = appearance.showLabels;
      _apps = apps;
      _shortcuts = shortcuts;
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

  /// Grid size, appearance and the service view all live behind the gear,
  /// so the window is the deck and nothing else.
  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SegmentedButton<DeckTheme>(
                  segments: [
                    for (final theme in DeckTheme.values)
                      ButtonSegment(value: theme, label: Text(theme.label)),
                  ],
                  selected: {_theme},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setDialogState(() {});
                    _setAppearance(theme: selection.first);
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _showLabels,
                  onChanged: (value) {
                    setDialogState(() {});
                    _setAppearance(showLabels: value);
                  },
                  title: const Text('Button labels'),
                  subtitle: const Text(
                    'Off makes cells square and lets the icon fill them',
                  ),
                ),
                const SizedBox(height: 12),
                Text('Grid', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                _SizeStepper(
                  label: 'Columns',
                  value: _layout.columns,
                  onChanged: (value) {
                    setDialogState(() {});
                    _apply(_layout.resized(columns: value));
                  },
                ),
                _SizeStepper(
                  label: 'Rows',
                  value: _layout.rows,
                  onChanged: (value) {
                    setDialogState(() {});
                    _apply(_layout.resized(rows: value));
                  },
                ),
                _SizeStepper(
                  label: 'Pages',
                  value: _layout.pages,
                  max: DeckLayout.maxPages,
                  onChanged: (value) {
                    setDialogState(() {});
                    _apply(_layout.resized(pages: value));
                  },
                ),
                const Divider(height: 32),
                // A diagnostic, like the client's debug console: for
                // working out why the deck is misbehaving, not for daily use.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Service details'),
                  subtitle: const Text(
                    'Advertising state, connected clients, activity log',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onShowService();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAppearance({DeckTheme? theme, bool? showLabels}) async {
    setState(() {
      _theme = theme ?? _theme;
      _showLabels = showLabels ?? _showLabels;
    });
    await SettingsStore.save(theme: _theme, showLabels: _showLabels);
    widget.onAppearanceChanged(_theme, _showLabels);
  }

  Future<void> _pick(int index) async {
    final chosen = await showDialog<DeckItemChoice>(
      context: context,
      builder: (context) => _PickerDialog(
        apps: _apps,
        shortcuts: _shortcuts,
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
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Text(
                'Deck layout',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Settings',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
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
                  icon: item is AppItem && item.emoji == null
                      ? iconFor(item.name)
                      : null,
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
                        child: item!.emoji != null
                            // Sized explicitly: an emoji's advance box is
                            // wider than its glyph, so fitting the box
                            // leaves it small and off centre.
                            ? Center(
                                child: Text(
                                  item!.emoji!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: iconSize * 0.78,
                                    height: 1,
                                  ),
                                ),
                              )
                            : icon != null
                            ? Image.memory(icon!, fit: BoxFit.contain)
                            : FittedBox(
                                child: item is AppItem
                                    ? Text(
                                        item!.label.characters.first
                                            .toUpperCase(),
                                        style: theme.textTheme.headlineMedium,
                                      )
                                    : Icon(deckFallbackIcon(item!)),
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
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
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
  const _PickerDialog({
    required this.apps,
    required this.shortcuts,
    required this.current,
  });

  final List<({String name, String category, String path})> apps;
  final List<String> shortcuts;
  final String? current;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  final _search = TextEditingController();
  final _emoji = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text.trim()));
    // Prefill with whatever this slot already shows, so reopening the picker
    // does not silently drop a custom icon.
    final existing = widget.current == null
        ? null
        : DeckItem.parse(widget.current!);
    _emoji.text = existing?.emoji ?? '';
  }

  @override
  void dispose() {
    _search.dispose();
    _emoji.dispose();
    super.dispose();
  }

  /// The emoji field applies to whatever is picked; blank means "use the
  /// app's own icon or the built-in glyph".
  String? get _chosenEmoji {
    final text = _emoji.text.trim();
    return text.isEmpty ? null : text;
  }

  void _choose(DeckItem item) =>
      Navigator.of(context).pop(DeckItemChoice(item.stored));

  Future<void> _composeKeyCombo() async {
    final existing = widget.current == null
        ? null
        : DeckItem.parse(widget.current!);
    final item = await showDialog<KeyComboItem>(
      context: context,
      builder: (context) => _KeyComboDialog(
        existing: existing is KeyComboItem ? existing : null,
        emoji: _chosenEmoji,
      ),
    );
    if (item == null || !mounted) return;
    _choose(item);
  }

  Future<void> _composeShell() async {
    final existing = widget.current == null
        ? null
        : DeckItem.parse(widget.current!);
    final item = await showDialog<ShellItem>(
      context: context,
      builder: (context) => _ShellDialog(
        existing: existing is ShellItem ? existing : null,
        emoji: _chosenEmoji,
      ),
    );
    if (item == null || !mounted) return;
    _choose(item);
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.toLowerCase();
    final apps = _query.isEmpty
        ? widget.apps
        : widget.apps
              .where((app) => app.name.toLowerCase().contains(needle))
              .toList();
    final shortcuts = _query.isEmpty
        ? widget.shortcuts
        : widget.shortcuts
              .where((name) => name.toLowerCase().contains(needle))
              .toList();

    return AlertDialog(
      title: const Text('Choose a button'),
      content: SizedBox(
        width: 440,
        height: 560,
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _emoji,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22),
                    decoration: const InputDecoration(
                      hintText: '🙂',
                      labelText: 'Emoji',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: 'optional',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search apps and shortcuts',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (_query.isEmpty) ...[
                    const _SectionLabel('Command'),
                    ListTile(
                      leading: const Icon(Icons.terminal),
                      title: const Text('Shell command...'),
                      subtitle: const Text('Runs on this Mac'),
                      onTap: _composeShell,
                    ),
                    ListTile(
                      leading: const Icon(Icons.keyboard),
                      title: const Text('Key combination...'),
                      subtitle: const Text('Sent to whatever is frontmost'),
                      onTap: _composeKeyCombo,
                    ),
                    const _SectionLabel('Media controls'),
                    for (final action in DeckAction.values)
                      ListTile(
                        leading: Icon(deckFallbackIcon(ActionItem(action))),
                        title: Text(action.label),
                        selected:
                            widget.current == ActionItem(action).stored,
                        onTap: () =>
                            _choose(ActionItem(action, emoji: _chosenEmoji)),
                      ),
                  ],
                  if (shortcuts.isNotEmpty) ...[
                    const _SectionLabel('Shortcuts'),
                    for (final name in shortcuts)
                      ListTile(
                        leading: const Icon(Icons.bolt),
                        title: Text(name),
                        onTap: () => _choose(
                          ShortcutItem(name: name, emoji: _chosenEmoji),
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
                      onTap: () =>
                          _choose(AppItem(app.name, emoji: _chosenEmoji)),
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

/// Composes a shell button: the command, what to call it, and an optional
/// emoji carried over from the picker.
class _ShellDialog extends StatefulWidget {
  const _ShellDialog({required this.existing, required this.emoji});

  final ShellItem? existing;
  final String? emoji;

  @override
  State<_ShellDialog> createState() => _ShellDialogState();
}

class _ShellDialogState extends State<_ShellDialog> {
  late final _command = TextEditingController(
    text: widget.existing?.command ?? '',
  );
  late final _label = TextEditingController(
    text: widget.existing?.label ?? '',
  );

  @override
  void dispose() {
    _command.dispose();
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final command = _command.text.trim();
    if (command.isEmpty) return;
    final label = _label.text.trim();
    Navigator.of(context).pop(
      ShellItem(
        command: command,
        // Falling back to the command keeps the button identifiable when
        // the user cannot think of a name.
        label: label.isEmpty ? command : label,
        emoji: widget.emoji ?? widget.existing?.emoji,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Shell command'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _command,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'Command',
                hintText: 'osascript -e \'display notification "hi"\'',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Button label',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Runs with /bin/sh on this Mac. Phones can only press the '
              'button, never send a command.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add')),
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

/// Composes a keyboard combination: modifiers, a key, and what to call it.
class _KeyComboDialog extends StatefulWidget {
  const _KeyComboDialog({required this.existing, required this.emoji});

  final KeyComboItem? existing;
  final String? emoji;

  @override
  State<_KeyComboDialog> createState() => _KeyComboDialogState();
}

class _KeyComboDialogState extends State<_KeyComboDialog> {
  late final Set<KeyModifier> _modifiers = {
    ...?widget.existing?.modifiers,
  };
  late final _character = TextEditingController(
    text: widget.existing?.key ?? '',
  );
  late final _label = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  late SpecialKey? _special = widget.existing?.special;

  @override
  void dispose() {
    _character.dispose();
    _label.dispose();
    super.dispose();
  }

  /// Live preview of what will be sent, so the symbols are not a guess.
  String get _preview => KeyComboItem(
    modifiers: _modifiers.toList(),
    key: _character.text.trim().isEmpty ? null : _character.text.trim(),
    special: _special,
  ).combination;

  bool get _valid =>
      _special != null || _character.text.trim().isNotEmpty;

  void _save() {
    if (!_valid) return;
    final label = _label.text.trim();
    Navigator.of(context).pop(
      KeyComboItem(
        // Stored in enum order so the symbols always read ⌃⌥⇧⌘-style.
        modifiers: KeyModifier.values
            .where(_modifiers.contains)
            .toList(),
        key: _special == null ? _character.text.trim() : null,
        special: _special,
        label: label.isEmpty ? null : label,
        emoji: widget.emoji ?? widget.existing?.emoji,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Key combination'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final modifier in KeyModifier.values)
                  FilterChip(
                    label: Text('${modifier.symbol} ${modifier.name}'),
                    selected: _modifiers.contains(modifier),
                    onSelected: (on) => setState(() {
                      on
                          ? _modifiers.add(modifier)
                          : _modifiers.remove(modifier);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _character,
                    enabled: _special == null,
                    maxLength: 1,
                    textAlign: TextAlign.center,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Key',
                      hintText: 'c',
                      border: OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<SpecialKey?>(
                    initialValue: _special,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'or a special key',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(child: Text('None')),
                      for (final key in SpecialKey.values)
                        DropdownMenuItem(value: key, child: Text(key.label)),
                    ],
                    onChanged: (key) => setState(() {
                      _special = key;
                      if (key != null) _character.clear();
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Button label',
                hintText: 'defaults to the combination',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Sends', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 8),
                Text(
                  _valid ? _preview : '—',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Needs Accessibility permission, the same as the media keys.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _save : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
