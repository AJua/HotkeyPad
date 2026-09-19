import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'app_launcher.dart';
import 'backup_store.dart';
import 'background_image_store.dart';
import 'command_runner.dart';
import 'custom_icon_store.dart';
import 'deck_icons.dart';
import 'layout_store.dart';
import 'settings_store.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Where the Settings dialog's "Report an issue" entry sends the user.
const _githubIssuesUrl = 'https://github.com/AJua/HotkeyPad/issues';

/// The buttons a resize to this shape would leave outside the grid.
///
/// A pure function of [layout] so a dry run costs nothing and can be
/// checked before anything is actually applied — shrinking is the only
/// direction that can delete a button, and there is no undo once it does.
/// Mirrors the bounds [DeckLayout.resized] keeps a cell within exactly, so
/// what this reports as dropped is what that would actually drop.
List<DeckItem> itemsDroppedByResize(
  DeckLayout layout, {
  int? columns,
  int? rows,
  int? pages,
}) {
  final newColumns = columns ?? layout.columns;
  final newRows = rows ?? layout.rows;
  final newPages = pages ?? layout.pages;
  final dropped = <DeckItem>[];
  for (var page = 0; page < layout.pages; page++) {
    for (var row = 0; row < layout.rows; row++) {
      for (var column = 0; column < layout.columns; column++) {
        if (page < newPages && row < newRows && column < newColumns) {
          continue;
        }
        final slot =
            layout.slots[layout.indexOf(
              page: page,
              cell: row * layout.columns + column,
            )];
        if (slot == null) continue;
        final item = DeckItem.parse(slot.value);
        if (item != null) dropped.add(item);
      }
    }
  }
  return dropped;
}

/// Asks before a shrink deletes [dropped]. Returns whether to proceed.
///
/// A standalone function, not a method on the editor, so it can be pumped
/// and tapped through in isolation — without dragging in the editor's own
/// state and the real disk I/O ([LayoutStore], [AppLauncher]) that loading
/// it would trigger.
Future<bool> confirmResizeDrop(
  BuildContext context,
  List<DeckItem> dropped,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        dropped.length == 1
            ? 'Remove 1 button?'
            : 'Remove ${dropped.length} buttons?',
      ),
      content: Text(
        'Shrinking the grid no longer has room for '
        '${dropped.map((item) => item.label).join(', ')}. '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Asks before an import overwrites the current appearance, layout, and
/// custom icons. Returns whether to proceed.
///
/// A standalone function, not a method on the editor, for the same reason
/// [confirmResizeDrop] is one: pumped and tapped through in isolation,
/// without the real file picker or disk I/O ([BackupStore]) that reaching
/// it for real would trigger.
Future<bool> confirmImportOverwrite(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Replace current settings?'),
      content: const Text(
        'Importing replaces the current appearance, deck layout, and '
        'custom icons with what is in the chosen file. This cannot be '
        'undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A human-readable read-out of what [stored] actually does — the command a
/// Shell or Key combination button runs, not just its label — so reopening
/// the picker answers "what is this?" without guessing from the icon alone
/// or clicking through to a sub-dialog. Null for an empty slot or a value
/// this build cannot parse.
String? currentButtonSummary(String? stored) {
  final item = stored == null ? null : DeckItem.parse(stored);
  return switch (item) {
    null => null,
    AppItem(:final name) => 'Opens $name',
    ActionItem(:final action) => 'Action: ${action.label}',
    ShellItem(:final command) => 'Runs: $command',
    KeyComboItem(:final combination) => 'Sends $combination',
    ShortcutItem(:final name) => 'Runs the "$name" Shortcut',
    ComboItem(:final steps) => 'Runs ${steps.length} steps',
    WidgetItem(:final kind, :final rowSpan, :final columnSpan) =>
      '${kind.label} widget (${rowSpan}x$columnSpan)',
  };
}

/// The largest row/column span a widget anchored at [index] could have
/// without running off [layout]'s own edge from that position — what
/// [_PickerDialogState]'s own Rows/Columns steppers are bounded to, so
/// every span they can actually produce is guaranteed to fit without
/// [DeckLayout.footprintFor]'s own clamping ever having to kick in for a
/// freshly-chosen size.
///
/// A pure function of [layout] and [index], for the same isolated-testing
/// reason as [itemsDroppedByResize].
({int rows, int columns}) maxWidgetSpanAt(DeckLayout layout, int index) {
  final cell = index % layout.pageCapacity;
  final anchorRow = cell ~/ layout.columns;
  final anchorColumn = cell % layout.columns;
  return (
    rows: layout.rows - anchorRow,
    columns: layout.columns - anchorColumn,
  );
}

/// The buttons placing [item] anchored at [index] in [layout] would clear —
/// every other cell in its own footprint, [index] itself excluded since
/// overwriting whatever was already at the tapped cell is what picking
/// anything for it always does, widget or not; only the cells the user did
/// *not* tap are collateral. Mirrors [DeckLayout.withWidget]'s own clearing
/// so a dry run reports exactly what that would actually drop.
List<DeckItem> itemsDroppedByWidget(
  DeckLayout layout,
  int index,
  WidgetItem item,
) {
  final footprint = layout.footprintFor(
    index,
    rowSpan: item.rowSpan,
    columnSpan: item.columnSpan,
  );
  final dropped = <DeckItem>[];
  for (final covered in footprint.indexes) {
    if (covered == index) continue;
    final slot = layout.slots[covered];
    if (slot == null) continue;
    final parsed = DeckItem.parse(slot.value);
    if (parsed != null) dropped.add(parsed);
  }
  return dropped;
}

/// Asks before placing a widget clears buttons already inside its
/// footprint. Returns whether to proceed. Standalone, not a method on the
/// editor, for the same pumped-and-tapped-in-isolation reason as
/// [confirmResizeDrop].
Future<bool> confirmWidgetOverwrite(
  BuildContext context,
  List<DeckItem> dropped,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        dropped.length == 1
            ? 'Remove 1 button?'
            : 'Remove ${dropped.length} buttons?',
      ),
      content: Text(
        'This widget covers where '
        '${dropped.map((item) => item.label).join(', ')} '
        'already ${dropped.length == 1 ? 'is' : 'are'}. This cannot be '
        'undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Undoes the transpose (if any) that produced a display-oriented view of
/// a layout, so an edit made through that view lands back in the host's
/// own canonical shape before it is saved or broadcast.
///
/// [DeckLayout.orientedFor]/[DeckLayout.transposed] only ever swap columns
/// and rows or no-op, so transposing an already-transposed shape again
/// exactly undoes it — see "transposing twice returns the original" in
/// protocol_test.dart. A pure function of the edited layout and whether it
/// was turned, specifically so it is testable without a real
/// [LayoutPage] — same reason as [itemsDroppedByResize].
DeckLayout displayEditToCanonical(
  DeckLayout edited, {
  required bool wasTransposed,
}) => wasTransposed ? edited.transposed() : edited;

/// A dropdown to pick which connected client's presses the host accepts —
/// shown identically on the deck layout screen and in the service tab, so
/// it lives here rather than in either one specifically.
///
/// Public, not a private implementation detail of [LayoutPage], so
/// host_page.dart's service tab can reuse it instead of duplicating the
/// same picker.
class DeviceLockPicker extends StatelessWidget {
  const DeviceLockPicker({
    super.key,
    required this.clients,
    required this.lockedClientId,
    required this.onChanged,
    this.compact = false,
  });

  final List<({String id, String label})> clients;
  final String? lockedClientId;
  final ValueChanged<String?> onChanged;

  /// A small tappable label instead of a full labelled row — for the deck
  /// layout title bar, next to the settings gear, rather than a row of its
  /// own. The service tab keeps the spelled-out version.
  final bool compact;

  /// There is no "any device" choice — every press is rejected until one
  /// specific device is picked, so a stand-in that says so doubles as a
  /// warning that presses are not going anywhere right now.
  static const _unpicked = 'Select a device';

  /// The locked client's own label, or [_unpicked] once it is no longer in
  /// [clients] (it just disconnected) or nothing has been chosen yet.
  String _labelFor(String? id) {
    if (id != null) {
      for (final client in clients) {
        if (client.id == id) return client.label;
      }
    }
    return _unpicked;
  }

  @override
  Widget build(BuildContext context) {
    final label = _labelFor(lockedClientId);
    final warn = label == _unpicked;
    final warnColor = Theme.of(context).colorScheme.error;

    if (compact) {
      return PopupMenuButton<String?>(
        tooltip: 'Accept commands from…',
        onSelected: onChanged,
        itemBuilder: (context) => [
          for (final client in clients)
            PopupMenuItem(value: client.id, child: Text(client.label)),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 16,
              color: warn ? warnColor : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: warn ? warnColor : null),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      );
    }

    return Row(
      children: [
        Icon(Icons.lock_outline, size: 16, color: warn ? warnColor : null),
        const SizedBox(width: 8),
        const Text('Accept commands from:'),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String?>(
            isDense: true,
            isExpanded: true,
            value: lockedClientId,
            hint: Text(_unpicked, style: TextStyle(color: warnColor)),
            items: [
              for (final client in clients)
                DropdownMenuItem(value: client.id, child: Text(client.label)),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

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
    required this.lockedClientPortrait,
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

  /// The locked client's own orientation, so the grid can be shown turned
  /// the same way that phone is actually displaying it — see
  /// [LayoutPageState._displayLayout]. Null whenever there is no single
  /// locked device to match (nothing picked, or its own [SetOrientation]
  /// has not arrived yet), in which case the canonical, un-turned shape is
  /// shown, same as before this existed.
  final bool? lockedClientPortrait;

  @override
  State<LayoutPage> createState() => LayoutPageState();
}

/// [DeckTheme.label] is a wire/debug string shared with the client and the
/// protocol tests, not UI copy, so the Settings dialog maps it to a
/// localized label here instead of showing it directly.
String _themeLabel(AppLocalizations l10n, DeckTheme theme) => switch (theme) {
  DeckTheme.system => l10n.themeSystem,
  DeckTheme.light => l10n.themeLight,
  DeckTheme.dark => l10n.themeDark,
};

/// Same reasoning as [_themeLabel], for [BackgroundFit.label].
String _backgroundFitLabel(AppLocalizations l10n, BackgroundFit fit) =>
    switch (fit) {
      BackgroundFit.cover => l10n.backgroundFitCover,
      BackgroundFit.contain => l10n.backgroundFitContain,
      BackgroundFit.stretch => l10n.backgroundFitStretch,
    };

/// Public so the host can hold a `GlobalKey<LayoutPageState>` and call
/// [openSettings] from the app bar's gear button, which lives a level above
/// this widget in the tree.
class LayoutPageState extends State<LayoutPage> {
  DeckLayout _layout = DeckLayout.empty();
  DeckTheme _theme = DeckTheme.system;
  bool _showLabels = true;
  String? _backgroundImageId;
  double _backgroundOpacity = 1.0;
  BackgroundFit _backgroundFit = BackgroundFit.cover;
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
      _backgroundImageId = appearance.backgroundImageId;
      _backgroundOpacity = appearance.backgroundOpacity;
      _backgroundFit = appearance.backgroundFit;
      _apps = apps;
      _shortcuts = shortcuts;
      _loading = false;
    });
  }

  /// Icons are fetched lazily and kept, including the misses: an app (or a
  /// custom image) with no icon should not be asked for again on every
  /// rebuild.
  Future<void> _ensureIcon(String key) async {
    if (_icons.containsKey(key)) return;
    _icons[key] = null;
    final path = _apps
        .where((app) => app.name == key)
        .map((app) => app.path)
        .firstOrNull;
    final bytes = path != null
        ? await AppLauncher.icon(path, size: HotkeyPad.iconSize)
        : await CustomIconStore.read(key);
    if (!mounted || bytes == null) return;
    setState(() => _icons[key] = bytes);
  }

  Future<void> _apply(DeckLayout layout) async {
    setState(() {
      _layout = layout;
      _clampPage();
    });
    await LayoutStore.save(layout);
    widget.onChanged(layout);
  }

  /// [_layout] turned to match the locked client's own orientation, when
  /// one is known — the grid, and only the grid, is shown and edited in
  /// this shape so the geometry on screen matches what that phone is
  /// actually displaying. Storage and broadcast are untouched: an edit
  /// made through this view is turned back via [_toCanonical] before
  /// [_apply] ever sees it.
  /// A manual portrait/landscape preview, used only when no real device is
  /// locked ([widget.lockedClientPortrait] is null) to say which shape to
  /// show — see [_toggleOrientationPreview]. Null means "whatever [_layout]
  /// is already saved as", same as before this existed.
  bool? _previewPortrait;

  DeckLayout get _displayLayout {
    final portrait = widget.lockedClientPortrait ?? _previewPortrait;
    return portrait == null ? _layout : _layout.orientedFor(portrait: portrait);
  }

  /// Whether [_displayLayout] is currently showing its portrait (taller
  /// than wide) shape — used to pick the preview frame's own aspect ratio
  /// and to flip [_previewPortrait] relative to whatever is on screen right
  /// now, rather than some fixed starting orientation.
  bool get _displayIsPortrait {
    final layout = _displayLayout;
    if (layout.columns == layout.rows) return true;
    return layout.rows > layout.columns;
  }

  /// Flips the preview between portrait and landscape — only reachable
  /// when nothing real is locked in, since a locked device's own
  /// orientation should always win over a guess made here.
  void _toggleOrientationPreview() {
    setState(() => _previewPortrait = !_displayIsPortrait);
  }

  /// Whether producing [_displayLayout] actually turned [_layout] — the
  /// two hold the exact same buttons either way, only the column/row
  /// shape (and therefore every index into `slots`) differs.
  bool get _isDisplayTransposed => _displayLayout.columns != _layout.columns;

  DeckLayout _toCanonical(DeckLayout edited) =>
      displayEditToCanonical(edited, wasTransposed: _isDisplayTransposed);

  /// Resizes to [columns]/[rows]/[pages], confirming first if a button would
  /// no longer fit. Shrinking is the only direction that can delete
  /// anything — growing only ever adds empty cells — and there is no undo,
  /// so this is a dry run: nothing is applied until the user says so.
  Future<void> _resize({int? columns, int? rows, int? pages}) async {
    final dropped = itemsDroppedByResize(
      _layout,
      columns: columns,
      rows: rows,
      pages: pages,
    );
    if (dropped.isNotEmpty && !await confirmResizeDrop(context, dropped)) {
      return;
    }
    await _apply(_layout.resized(columns: columns, rows: rows, pages: pages));
  }

  /// Keeps the visible page valid when pages are removed.
  void _clampPage() {
    if (_page >= _layout.pages) _page = _layout.pages - 1;
  }

  /// Grid size, appearance and the service view all live behind the gear,
  /// so the window is the deck and nothing else. Public: the gear button
  /// that calls this now lives in the host's app bar, not this widget.
  Future<void> openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final l10n = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(l10n.settingsTitle),
            // A short window (or a tall grid — many pages, custom icons, an
            // export/import section, the service-details link all stacked
            // in one Column) easily runs out of vertical room: the dialog
            // itself already caps its height to the screen, but a bare
            // Column can't shrink to fit inside that, so it silently
            // overflowed past "Done" instead — this scroll view is what
            // lets the content still fit, by scrolling, rather than
            // overflowing.
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                // Desktop draws the scrollbar over the trailing edge of the
                // content rather than reserving its own space for it, so
                // without this the thumb/track sits right on top of the
                // text — this padding is that reserved space instead.
                padding: const EdgeInsets.only(right: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.appearanceSectionHeader,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<DeckTheme>(
                      segments: [
                        for (final theme in DeckTheme.values)
                          ButtonSegment(
                            value: theme,
                            label: Text(_themeLabel(l10n, theme)),
                          ),
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
                      title: Text(l10n.buttonLabelsToggleTitle),
                      subtitle: Text(l10n.buttonLabelsToggleSubtitle),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.backgroundImageSectionHeader,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    BackgroundPicker(
                      imageId: _backgroundImageId,
                      onChanged: (id) {
                        setDialogState(() {});
                        _setBackgroundImage(id);
                      },
                    ),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: _backgroundImageId == null ? 0.5 : 1,
                      child: Row(
                        children: [
                          Text(l10n.opacityLabel),
                          Expanded(
                            child: Slider(
                              value: _backgroundOpacity,
                              divisions: 20,
                              label: '${(_backgroundOpacity * 100).round()}%',
                              onChanged: _backgroundImageId == null
                                  ? null
                                  : (value) {
                                      setDialogState(() {});
                                      _setBackgroundOpacity(value);
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Opacity(
                      opacity: _backgroundImageId == null ? 0.5 : 1,
                      child: SegmentedButton<BackgroundFit>(
                        segments: [
                          for (final fit in BackgroundFit.values)
                            ButtonSegment(
                              value: fit,
                              label: Text(_backgroundFitLabel(l10n, fit)),
                            ),
                        ],
                        selected: {_backgroundFit},
                        showSelectedIcon: false,
                        onSelectionChanged: _backgroundImageId == null
                            ? null
                            : (selection) {
                                setDialogState(() {});
                                _setBackgroundFit(selection.first);
                              },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.gridSectionHeader,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    _NumberStepper(
                      label: l10n.columnsLabel,
                      value: _layout.columns,
                      onChanged: (value) async {
                        await _resize(columns: value);
                        setDialogState(() {});
                      },
                    ),
                    _NumberStepper(
                      label: l10n.rowsLabel,
                      value: _layout.rows,
                      onChanged: (value) async {
                        await _resize(rows: value);
                        setDialogState(() {});
                      },
                    ),
                    _NumberStepper(
                      label: l10n.pagesLabel,
                      value: _layout.pages,
                      max: DeckLayout.maxPages,
                      onChanged: (value) async {
                        await _resize(pages: value);
                        setDialogState(() {});
                      },
                    ),
                    const Divider(height: 32),
                    Text(
                      l10n.backupSectionHeader,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    // Two entry points rather than one "Backup..." tile with a
                    // sub-choice: export is safe to tap on a whim and import is
                    // destructive, so keeping them visually distinct here
                    // matches that difference before either is even tapped.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.upload_outlined),
                      title: Text(l10n.exportSettingsTitle),
                      subtitle: Text(l10n.exportSettingsSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).pop();
                        _exportSettings();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.download_outlined),
                      title: Text(l10n.importSettingsTitle),
                      subtitle: Text(l10n.importSettingsSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).pop();
                        _importSettings();
                      },
                    ),
                    const Divider(height: 32),
                    // A diagnostic, like the client's debug console: for
                    // working out why the deck is misbehaving, not for daily use.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bug_report_outlined),
                      title: Text(l10n.serviceDetailsTitle),
                      subtitle: Text(l10n.serviceDetailsSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onShowService();
                      },
                    ),
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

  Future<void> _setAppearance({DeckTheme? theme, bool? showLabels}) async {
    setState(() {
      _theme = theme ?? _theme;
      _showLabels = showLabels ?? _showLabels;
    });
    await _saveAppearance();
  }

  /// Writes every appearance field at once and tells the host to push it —
  /// [SettingsStore] and [SetAppearance] both carry the background settings
  /// alongside the theme and labels as one unit, so a change to any one of
  /// them resaves and rebroadcasts all of them rather than only the field
  /// that changed.
  Future<void> _saveAppearance() async {
    await SettingsStore.save(
      theme: _theme,
      showLabels: _showLabels,
      backgroundImageId: _backgroundImageId,
      backgroundOpacity: _backgroundOpacity,
      backgroundFit: _backgroundFit,
    );
    widget.onAppearanceChanged(_theme, _showLabels);
  }

  /// Replaces the background image, deleting whatever file the previous id
  /// pointed to — mirroring how [IconPicker._pickImage] avoids orphaning a
  /// button's old custom icon when a new one is chosen. Passing null clears
  /// the background entirely.
  Future<void> _setBackgroundImage(String? imageId) async {
    final previous = _backgroundImageId;
    setState(() => _backgroundImageId = imageId);
    await _saveAppearance();
    if (previous != null && previous != imageId) {
      unawaited(BackgroundImageStore.delete(previous));
    }
  }

  Future<void> _setBackgroundOpacity(double opacity) async {
    setState(() => _backgroundOpacity = opacity);
    await _saveAppearance();
  }

  Future<void> _setBackgroundFit(BackgroundFit fit) async {
    setState(() => _backgroundFit = fit);
    await _saveAppearance();
  }

  /// Opens the GitHub issue tracker in the user's default browser — the
  /// dialog itself stays open underneath, unlike Export/Import/Service
  /// details, since this doesn't navigate anywhere inside the app.
  Future<void> _reportIssue() async {
    await launchUrl(
      Uri.parse(_githubIssuesUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Saves the current appearance, layout, and custom icons to a file the
  /// user picks. Silent on cancel — there's nothing to report — otherwise
  /// shows whether it actually wrote the file.
  Future<void> _exportSettings() async {
    final result = await BackupStore.exportToFile();
    if (result == null) return;
    _showMessage(result.message);
  }

  /// Reads a backup file the user picks and, once confirmed, replaces the
  /// current appearance, layout, and custom icons with it — then pushes the
  /// restored state out live, the same way [_apply] and [_setAppearance] do
  /// for a manual edit.
  Future<void> _importSettings() async {
    final read = await BackupStore.pickAndReadFile();
    if (read == null) return;
    if (!read.ok) {
      _showMessage(read.message!);
      return;
    }
    if (!mounted) return;
    if (!await confirmImportOverwrite(context)) return;
    final bundle = read.bundle!;
    await BackupStore.apply(bundle);
    if (!mounted) return;
    setState(() {
      _layout = bundle.layout;
      _theme = bundle.theme;
      _showLabels = bundle.showLabels;
      _clampPage();
      // Bytes for a restored icon can differ from whatever this session
      // already cached under the same id (a re-import of an edited backup,
      // say), so nothing already fetched can be trusted after this.
      _icons.clear();
    });
    widget.onChanged(bundle.layout);
    widget.onAppearanceChanged(bundle.theme, bundle.showLabels);
    _showMessage('Settings imported.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// [index] is into [_displayLayout] — wherever the tapped cell actually
  /// sits on screen — not [_layout] directly; see [_toCanonical].
  Future<void> _pick(int index) async {
    final maxSpan = maxWidgetSpanAt(_displayLayout, index);
    final chosen = await showDialog<DeckItemChoice>(
      context: context,
      builder: (context) => _PickerDialog(
        apps: _apps,
        shortcuts: _shortcuts,
        current: _displayLayout.slots[index]?.value,
        maxRowSpan: maxSpan.rows,
        maxColumnSpan: maxSpan.columns,
      ),
    );
    if (chosen == null || !mounted) return;
    final item = DeckItem.parse(chosen.stored);
    if (item is WidgetItem) {
      if (_displayLayout.widgetPlacementBlocked(
        index,
        rowSpan: item.rowSpan,
        columnSpan: item.columnSpan,
      )) {
        _showMessage('That overlaps another widget already on the grid.');
        return;
      }
      final dropped = itemsDroppedByWidget(_displayLayout, index, item);
      if (dropped.isNotEmpty &&
          (!await confirmWidgetOverwrite(context, dropped) || !mounted)) {
        return;
      }
      await _apply(_toCanonical(_displayLayout.withWidget(index, item)));
      return;
    }
    await _apply(_toCanonical(_displayLayout.withSlot(index, chosen.stored)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.deckLayoutHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              // Hidden once a real device is locked in: its own actual
              // orientation always wins over a guess made here — see
              // _toggleOrientationPreview.
              if (widget.lockedClientPortrait == null)
                IconButton(
                  tooltip: l10n.previewOrientationTooltip,
                  onPressed: _toggleOrientationPreview,
                  icon: const Icon(Icons.screen_rotation_outlined),
                ),
            ],
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
                        _toCanonical(
                          _displayLayout.moved(
                            from,
                            _displayLayout.indexOf(page: page, cell: 0),
                          ),
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
            // A phone's own screen ratio, not just a generic frame — this
            // is meant to preview roughly how much of the deck a real
            // phone actually shows, not merely to decorate it.
            child: Center(
              child: AspectRatio(
                aspectRatio: _displayIsPortrait ? 9 / 19.5 : 19.5 / 9,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: LayoutGrid(
                    layout: _displayLayout,
                    page: _page,
                    iconFor: (key) {
                      unawaited(_ensureIcon(key));
                      return _icons[key];
                    },
                    onPick: _pick,
                    onClear: (index) => _apply(
                      _toCanonical(_displayLayout.withSlot(index, null)),
                    ),
                    onMove: (from, to) =>
                        _apply(_toCanonical(_displayLayout.moved(from, to))),
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
  final Uint8List? Function(String key) iconFor;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onClear;

  /// Called with the source and destination slot indices.
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Same proportions — and now the same formula, the same spacing,
        // and the same grid shell — the phone draws, so this previews
        // rather than approximates. Shared with the client via
        // hotkeypad_protocol instead of each computing its own slightly
        // different answer to the same question.
        const cellRatio = 0.86;
        const spacing = kDeckGridSpacing;
        final metrics = deckGridMetrics(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          columns: layout.columns,
          rows: layout.rows,
          cellRatio: cellRatio,
        );
        return DeckGridView(
          layout: layout,
          page: page,
          metrics: metrics,
          cellRatio: cellRatio,
          spacing: spacing,
          cellBuilder: (context, index) {
            final stored = layout.slots[index]?.value;
            final item = stored == null ? null : DeckItem.parse(stored);
            final iconKey = item == null || item.emoji != null
                ? null
                : iconKeyFor(item);
            return _Cell(
              index: index,
              item: item,
              icon: iconKey == null ? null : iconFor(iconKey),
              onTap: () => onPick(index),
              onClear: stored == null ? null : () => onClear(index),
              onMoved: (from) => onMove(from, index),
            );
          },
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
    // A real icon brings its own colour, shape, and often its own padding —
    // a filled neutral square behind it just showed through that padding as
    // a flat grey box.
    final hasRealIcon = filled && icon != null;
    // Only a glyph/emoji/letter fallback gets a background square: it has
    // no colour of its own, unlike a real icon, and the square sits behind
    // just the icon rather than the whole cell so the label below it stays
    // on the plain cell background.
    final showIconBackground = filled && !hasRealIcon;

    return Material(
      color: highlighted
          ? theme.colorScheme.primaryContainer
          : Colors.transparent,
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
              Center(child: Icon(Icons.add, color: theme.colorScheme.outline))
            else if (item case final WidgetItem widgetItem)
              // Renders itself — a real, ticking preview at this cell's own
              // (possibly multi-cell) size, rather than an icon and a
              // label like every other item below.
              LayoutBuilder(
                builder: (context, constraints) => switch (widgetItem.kind) {
                  DeckWidgetKind.clock => AnalogClock(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                  DeckWidgetKind.calendar => MonthCalendar(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                },
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
                      Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: !showIconBackground
                            ? null
                            : BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                  iconSize * 0.22,
                                ),
                              ),
                        clipBehavior: showIconBackground
                            ? Clip.antiAlias
                            : Clip.none,
                        child: item!.emoji != null
                            // Sized explicitly: an emoji's advance box is
                            // wider than its glyph, so fitting the box
                            // leaves it small and off centre.
                            ? Center(
                                child: Text(
                                  item!.emoji!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: iconSize * 0.82,
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

/// A labelled +/- control for an integer, e.g. grid size or a combo step's
/// delay. Buttons rather than a text field on purpose: a field needs a
/// controller to keep in sync with a value that can also change from
/// outside (a step being reordered, say), and that is exactly the kind of
/// lifecycle bug a text field invites — see IconPicker's emoji dialog.
class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 8,
    this.step = 1,
    this.format,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  /// How to display [value]; defaults to the bare number.
  final String Function(int value)? format;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        IconButton(
          onPressed: value > min ? () => onChanged(value - step) : null,
          icon: const Icon(Icons.remove_circle_outline),
          visualDensity: VisualDensity.compact,
        ),
        Text(format?.call(value) ?? '$value'),
        IconButton(
          onPressed: value < max ? () => onChanged(value + step) : null,
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
    this.maxRowSpan,
    this.maxColumnSpan,
    this.allowCombo = true,
  });

  final List<({String name, String category, String path})> apps;
  final List<String> shortcuts;
  final String? current;

  /// False when this picker is itself being used to choose one step of a
  /// combo — hides "Button combo...", since a combo cannot contain another
  /// combo (see [ComboStep.fromJson]).
  final bool allowCombo;

  /// The largest row/column span a widget placed here could have — see
  /// [maxWidgetSpanAt]. Null hides the "Widgets" section entirely, for the
  /// same reason [allowCombo] hides "Button combo...": a combo step picks
  /// an action to *run*, and a Clock/Calendar widget isn't one — there is
  /// no grid cell of its own here for it to span in the first place.
  final int? maxRowSpan;
  final int? maxColumnSpan;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  /// The override applied to whatever is picked below; null means "use the
  /// app's own icon or the built-in glyph". Mutually exclusive by
  /// construction of [IconPicker] — choosing one clears the other.
  String? _emoji;
  String? _customIconId;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text.trim()));
    // Prefill with whatever this slot already shows, so reopening the picker
    // does not silently drop a custom icon.
    _emoji = _existing?.emoji;
    _customIconId = _existing?.customIconId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// What this slot currently holds, or null if it is empty. Parsed fresh
  /// rather than cached: `widget.current` never changes under this widget,
  /// but re-parsing a short string is cheaper than a field to keep in sync.
  DeckItem? get _existing =>
      widget.current == null ? null : DeckItem.parse(widget.current!);

  /// Which widget kind, if any, already sits here — used only to highlight
  /// the matching "Widgets" entry below, the same way every other section
  /// marks its own current choice as `selected`.
  DeckWidgetKind? get _existingWidgetKind => switch (_existing) {
    final WidgetItem item => item.kind,
    _ => null,
  };

  String? get _currentSummary => currentButtonSummary(widget.current);

  void _choose(DeckItem item) =>
      Navigator.of(context).pop(DeckItemChoice(item.stored));

  /// Which widget kind's rows/columns steppers [build] should show instead
  /// of the ordinary list — null means "showing the list". Swapped in in
  /// place, inside this same dialog, rather than opening a second `showDialog`
  /// on top of this one: two stacked dialogs left both dialogs' own Cancel
  /// buttons visible at once, and it was unclear which one a tap would
  /// dismiss.
  DeckWidgetKind? _composingWidgetKind;
  int? _composeRows;
  int? _composeColumns;

  Future<void> _composeKeyCombo() async {
    final existing = _existing;
    final item = await showDialog<KeyComboItem>(
      context: context,
      builder: (context) => _KeyComboDialog(
        existing: existing is KeyComboItem ? existing : null,
        emoji: _emoji,
        customIconId: _customIconId,
      ),
    );
    if (item == null || !mounted) return;
    _choose(item);
  }

  Future<void> _composeShell() async {
    final existing = _existing;
    final item = await showDialog<ShellItem>(
      context: context,
      builder: (context) => _ShellDialog(
        existing: existing is ShellItem ? existing : null,
        emoji: _emoji,
        customIconId: _customIconId,
      ),
    );
    if (item == null || !mounted) return;
    _choose(item);
  }

  Future<void> _composeCombo() async {
    final existing = _existing;
    final item = await showDialog<ComboItem>(
      context: context,
      builder: (context) => ComboDialog(
        apps: widget.apps,
        shortcuts: widget.shortcuts,
        existing: existing is ComboItem ? existing : null,
        emoji: _emoji,
        customIconId: _customIconId,
      ),
    );
    if (item == null || !mounted) return;
    _choose(item);
  }

  void _startComposingWidget(DeckWidgetKind kind) {
    final existing = _existing;
    final prefill = existing is WidgetItem && existing.kind == kind
        ? existing
        : null;
    setState(() {
      _composingWidgetKind = kind;
      _composeRows = (prefill?.rowSpan ?? 2).clamp(1, widget.maxRowSpan!);
      _composeColumns = (prefill?.columnSpan ?? 2).clamp(
        1,
        widget.maxColumnSpan!,
      );
    });
  }

  void _cancelComposingWidget() => setState(() => _composingWidgetKind = null);

  void _saveComposingWidget() => _choose(
    WidgetItem(
      kind: _composingWidgetKind!,
      rowSpan: _composeRows!,
      columnSpan: _composeColumns!,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final composingKind = _composingWidgetKind;
    if (composingKind != null) {
      return AlertDialog(
        title: Text(composingKind.label),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NumberStepper(
                label: 'Rows',
                value: _composeRows!,
                max: widget.maxRowSpan!,
                onChanged: (value) => setState(() => _composeRows = value),
              ),
              _NumberStepper(
                label: 'Columns',
                value: _composeColumns!,
                max: widget.maxColumnSpan!,
                onChanged: (value) => setState(() => _composeColumns = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _cancelComposingWidget,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saveComposingWidget,
            child: const Text('Save'),
          ),
        ],
      );
    }

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
          // Left-aligned to match the list below — a Column centers its
          // children by default, which only ever showed on _currentSummary
          // (everything else here is already full-width).
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconPicker(
                  emoji: _emoji,
                  customIconId: _customIconId,
                  onChanged: (emoji, customIconId) => setState(() {
                    _emoji = emoji;
                    _customIconId = customIconId;
                  }),
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
            if (_currentSummary != null) ...[
              const SizedBox(height: 8),
              Text(
                _currentSummary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
                    if (widget.allowCombo)
                      ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: const Text('Button combo...'),
                        subtitle: const Text('Runs other buttons in sequence'),
                        onTap: _composeCombo,
                      ),
                    if (widget.maxRowSpan != null &&
                        widget.maxColumnSpan != null) ...[
                      const _SectionLabel('Widgets'),
                      ListTile(
                        leading: const Icon(Icons.access_time),
                        title: const Text('Clock...'),
                        subtitle: const Text('Live analog clock'),
                        selected: _existingWidgetKind == DeckWidgetKind.clock,
                        onTap: () =>
                            _startComposingWidget(DeckWidgetKind.clock),
                      ),
                      ListTile(
                        leading: const Icon(Icons.calendar_month),
                        title: const Text('Calendar...'),
                        subtitle: const Text('Current month'),
                        selected:
                            _existingWidgetKind == DeckWidgetKind.calendar,
                        onTap: () =>
                            _startComposingWidget(DeckWidgetKind.calendar),
                      ),
                    ],
                    const _SectionLabel('Media controls'),
                    for (final action in DeckAction.values)
                      ListTile(
                        leading: Icon(deckFallbackIcon(ActionItem(action))),
                        title: Text(action.label),
                        selected: widget.current == ActionItem(action).stored,
                        onTap: () => _choose(
                          ActionItem(
                            action,
                            emoji: _emoji,
                            customIconId: _customIconId,
                          ),
                        ),
                      ),
                  ],
                  if (shortcuts.isNotEmpty) ...[
                    const _SectionLabel('Shortcuts'),
                    for (final name in shortcuts)
                      ListTile(
                        leading: const Icon(Icons.bolt),
                        title: Text(name),
                        onTap: () => _choose(
                          ShortcutItem(
                            name: name,
                            emoji: _emoji,
                            customIconId: _customIconId,
                          ),
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
                      onTap: () => _choose(
                        AppItem(
                          app.name,
                          emoji: _emoji,
                          customIconId: _customIconId,
                        ),
                      ),
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

/// Preview of a button's overriding glyph — an emoji or a custom image —
/// that opens a choice of how to change it when tapped.
///
/// Public, unlike the dialogs around it, so it can be pumped and tapped
/// through in isolation the way `confirmResizeDrop` was extracted for the
/// same reason.
class IconPicker extends StatefulWidget {
  const IconPicker({
    super.key,
    required this.emoji,
    required this.customIconId,
    required this.onChanged,
  });

  final String? emoji;

  /// The bytes behind this id live on this machine's own disk — the host is
  /// what saved them — so there is nothing to fetch over the link to show
  /// this preview.
  final String? customIconId;

  /// Reports the new (emoji, customIconId) pair. Exactly one of the two is
  /// ever non-null, or both are null to clear the override.
  final void Function(String? emoji, String? customIconId) onChanged;

  @override
  State<IconPicker> createState() => _IconPickerState();
}

enum _IconPickerAction { image, text }

class _IconPickerState extends State<IconPicker> {
  Uint8List? _bytes;

  /// Separate from [_bytes] being null: that is also true once a read
  /// finishes and finds nothing, and conflating the two kept the spinner
  /// below spinning forever for a dangling id instead of settling on the
  /// placeholder.
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant IconPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customIconId != widget.customIconId) _load();
  }

  Future<void> _load() async {
    final id = widget.customIconId;
    if (id == null) {
      setState(() {
        _bytes = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final bytes = await CustomIconStore.read(id);
    // The id could have changed again while this was in flight.
    if (mounted && widget.customIconId == id) {
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final png = await CustomIconStore.pickAndProcess();
    if (png == null || !mounted) return;
    final id = await CustomIconStore.save(png);
    if (id == null || !mounted) return;
    final previous = widget.customIconId;
    widget.onChanged(null, id);
    if (previous != null && previous != id) {
      unawaited(CustomIconStore.delete(previous));
    }
  }

  Future<void> _typeText() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _EmojiDialog(initial: widget.emoji),
    );
    if (result == null || !mounted) return;
    final text = result.trim();
    final previous = widget.customIconId;
    widget.onChanged(text.isEmpty ? null : text, null);
    if (previous != null) unawaited(CustomIconStore.delete(previous));
  }

  Future<void> _choose() async {
    final action = await showDialog<_IconPickerAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Button icon'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_IconPickerAction.image),
            child: const Row(
              children: [
                Icon(Icons.image_outlined),
                SizedBox(width: 12),
                Text('Choose image...'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_IconPickerAction.text),
            child: const Row(
              children: [
                Icon(Icons.title),
                SizedBox(width: 12),
                Text('Type text...'),
              ],
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _IconPickerAction.image:
        await _pickImage();
      case _IconPickerAction.text:
        await _typeText();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: _choose, child: _preview(context)),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    if (widget.emoji != null) {
      return Center(
        child: Text(widget.emoji!, style: const TextStyle(fontSize: 28)),
      );
    }
    if (widget.customIconId != null) {
      if (_loading) {
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      final bytes = _bytes;
      // A dangling id — the file went missing somehow — falls through to
      // the same placeholder as having nothing set, rather than spinning
      // forever waiting for bytes that are never going to arrive.
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    }
    return Icon(
      Icons.add_photo_alternate_outlined,
      color: Theme.of(context).colorScheme.outline,
    );
  }
}

/// Preview and picker for the deck's background image — [IconPicker]'s
/// image half without the emoji/text alternative, since there is no
/// glyph-sized stand-in for a whole-screen photo.
///
/// Public, not a private implementation detail of the settings dialog, for
/// the same reason [IconPicker] is: it can be pumped and tapped through in
/// isolation without the dialog around it.
class BackgroundPicker extends StatefulWidget {
  const BackgroundPicker({
    super.key,
    required this.imageId,
    required this.onChanged,
  });

  final String? imageId;

  /// Reports the newly picked id, or null when "Remove" is tapped.
  final ValueChanged<String?> onChanged;

  @override
  State<BackgroundPicker> createState() => _BackgroundPickerState();
}

class _BackgroundPickerState extends State<BackgroundPicker> {
  Uint8List? _bytes;

  /// Same reason as [_IconPickerState._loading]: distinct from [_bytes]
  /// being null, which is also true once a read finishes and finds nothing.
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BackgroundPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId) _load();
  }

  Future<void> _load() async {
    final id = widget.imageId;
    if (id == null) {
      setState(() {
        _bytes = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final bytes = await BackgroundImageStore.read(id);
    // The id could have changed again while this was in flight.
    if (mounted && widget.imageId == id) {
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    }
  }

  Future<void> _pick() async {
    final png = await BackgroundImageStore.pickAndProcess();
    if (png == null || !mounted) return;
    final id = await BackgroundImageStore.save(png);
    if (id == null || !mounted) return;
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: _pick, child: _preview(context)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: _pick,
                child: Text(
                  widget.imageId == null
                      ? AppLocalizations.of(context)!.chooseImageAction
                      : AppLocalizations.of(context)!.changeImageAction,
                ),
              ),
              if (widget.imageId != null)
                TextButton(
                  onPressed: () => widget.onChanged(null),
                  child: Text(AppLocalizations.of(context)!.removeImageAction),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final bytes = _bytes;
    // A dangling id falls through to the placeholder, same as IconPicker.
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    return Icon(
      Icons.image_outlined,
      color: Theme.of(context).colorScheme.outline,
    );
  }
}

/// Prompts for the emoji [IconPicker]'s "Type text..." option offers.
///
/// A dialog of its own, rather than building the controller inline in
/// [_IconPickerState], so its lifecycle is tied to this widget the normal
/// way: disposing it right after `showDialog` returns raced the dialog's
/// own close animation and crashed with "used after being disposed".
class _EmojiDialog extends StatefulWidget {
  const _EmojiDialog({required this.initial});

  final String? initial;

  @override
  State<_EmojiDialog> createState() => _EmojiDialogState();
}

class _EmojiDialogState extends State<_EmojiDialog> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Emoji'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22),
        decoration: const InputDecoration(hintText: '🙂'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Composes a shell button: the command, what to call it, and an optional
/// emoji or custom image carried over from the picker.
class _ShellDialog extends StatefulWidget {
  const _ShellDialog({
    required this.existing,
    required this.emoji,
    required this.customIconId,
  });

  final ShellItem? existing;
  final String? emoji;
  final String? customIconId;

  @override
  State<_ShellDialog> createState() => _ShellDialogState();
}

class _ShellDialogState extends State<_ShellDialog> {
  late final _command = TextEditingController(
    text: widget.existing?.command ?? '',
  );
  late final _label = TextEditingController(text: widget.existing?.label ?? '');

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
        customIconId: widget.customIconId ?? widget.existing?.customIconId,
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
  const _KeyComboDialog({
    required this.existing,
    required this.emoji,
    required this.customIconId,
  });

  final KeyComboItem? existing;
  final String? emoji;
  final String? customIconId;

  @override
  State<_KeyComboDialog> createState() => _KeyComboDialogState();
}

class _KeyComboDialogState extends State<_KeyComboDialog> {
  late final Set<KeyModifier> _modifiers = {...?widget.existing?.modifiers};
  late final _character = TextEditingController(
    text: widget.existing?.key ?? '',
  );
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
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

  bool get _valid => _special != null || _character.text.trim().isNotEmpty;

  void _save() {
    if (!_valid) return;
    final label = _label.text.trim();
    Navigator.of(context).pop(
      KeyComboItem(
        // Stored in enum order so the symbols always read ⌃⌥⇧⌘-style.
        modifiers: KeyModifier.values.where(_modifiers.contains).toList(),
        key: _special == null ? _character.text.trim() : null,
        special: _special,
        label: label.isEmpty ? null : label,
        emoji: widget.emoji ?? widget.existing?.emoji,
        customIconId: widget.customIconId ?? widget.existing?.customIconId,
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

/// Composes a button combo: an ordered list of other buttons' actions, each
/// picked once through [_PickerDialog] itself (with `allowCombo: false`, so
/// a combo cannot contain another combo) and then held as its own copy, not
/// a live reference back to wherever it was picked from.
class ComboDialog extends StatefulWidget {
  const ComboDialog({
    super.key,
    required this.apps,
    required this.shortcuts,
    required this.existing,
    required this.emoji,
    required this.customIconId,
  });

  final List<({String name, String category, String path})> apps;
  final List<String> shortcuts;
  final ComboItem? existing;
  final String? emoji;
  final String? customIconId;

  @override
  State<ComboDialog> createState() => _ComboDialogState();
}

class _ComboDialogState extends State<ComboDialog> {
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final List<ComboStep> _steps = [...?widget.existing?.steps];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _addStep() async {
    final chosen = await showDialog<DeckItemChoice>(
      context: context,
      builder: (context) => _PickerDialog(
        apps: widget.apps,
        shortcuts: widget.shortcuts,
        current: null,
        allowCombo: false,
      ),
    );
    if (chosen == null || !mounted) return;
    final action = DeckItem.parse(chosen.stored);
    if (action == null) return;
    setState(() {
      // A first step defaults to firing immediately; later ones default to
      // a gap worth noticing. Either is just a starting point — every
      // step's delay, including the first, can be adjusted afterward.
      _steps.add(ComboStep(action: action, delayMs: _steps.isEmpty ? 0 : 500));
    });
  }

  void _removeStep(int index) => setState(() => _steps.removeAt(index));

  void _moveStep(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _steps.length) return;
    setState(() => _steps.insert(target, _steps.removeAt(index)));
  }

  void _setDelay(int index, int delayMs) {
    setState(
      () => _steps[index] = ComboStep(
        action: _steps[index].action,
        delayMs: delayMs,
      ),
    );
  }

  bool get _valid => _steps.length >= 2 && _label.text.trim().isNotEmpty;

  void _save() {
    if (!_valid) return;
    Navigator.of(context).pop(
      ComboItem(
        steps: List.of(_steps),
        label: _label.text.trim(),
        emoji: widget.emoji ?? widget.existing?.emoji,
        customIconId: widget.customIconId ?? widget.existing?.customIconId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Button combo'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _label,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Button label',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Steps, in order',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Expanded(
              child: _steps.isEmpty
                  ? Center(
                      child: Text(
                        'Add at least two steps.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _steps.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final step = _steps[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            currentButtonSummary(step.action.stored) ??
                                step.action.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: _NumberStepper(
                            label: 'Wait before this step',
                            value: step.delayMs,
                            min: 0,
                            max: 10000,
                            step: 250,
                            format: (v) => '${v}ms',
                            onChanged: (v) => _setDelay(index, v),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Move up',
                                icon: const Icon(Icons.arrow_upward),
                                visualDensity: VisualDensity.compact,
                                onPressed: index == 0
                                    ? null
                                    : () => _moveStep(index, -1),
                              ),
                              IconButton(
                                tooltip: 'Move down',
                                icon: const Icon(Icons.arrow_downward),
                                visualDensity: VisualDensity.compact,
                                onPressed: index == _steps.length - 1
                                    ? null
                                    : () => _moveStep(index, 1),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _removeStep(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addStep,
              icon: const Icon(Icons.add),
              label: const Text('Add step...'),
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}
