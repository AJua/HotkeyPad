import 'package:flutter/material.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// The key to fetch a rendered icon for, or null when nothing overrides the
/// built-in glyph.
///
/// A custom image — which is also what an emoji becomes, see
/// `IconPicker` — takes priority over an app's own icon. Presentation, so
/// it lives outside the protocol, same as [deckFallbackIcon].
String? iconKeyFor(DeckItem item) =>
    item.customIconId ?? (item is AppItem ? item.name : null);

/// Glyph shown for a deck item that has neither a custom image nor an app
/// icon of its own.
///
/// Presentation, so it lives outside the protocol.
IconData deckFallbackIcon(DeckItem item) => switch (item) {
  AppItem() => Icons.apps,
  ShellItem() => Icons.terminal,
  KeyComboItem() => Icons.keyboard,
  ShortcutItem() => Icons.bolt,
  OpenUrlItem() => Icons.open_in_browser,
  PlaySoundItem() => Icons.music_note,
  ComboItem() => Icons.playlist_play,
  ActionItem(:final action) => switch (action) {
    DeckAction.playPause => Icons.play_arrow,
    DeckAction.next => Icons.skip_next,
    DeckAction.previous => Icons.skip_previous,
    DeckAction.volumeUp => Icons.volume_up,
    DeckAction.volumeDown => Icons.volume_down,
    DeckAction.mute => Icons.volume_off,
  },
  // Unreachable in practice — a WidgetItem renders its own live preview
  // (see LayoutGrid's _Cell) rather than ever falling back to a glyph —
  // but the switch above is exhaustive over DeckItem, so this still has
  // to exist.
  WidgetItem(:final kind) => switch (kind) {
    DeckWidgetKind.clock => Icons.access_time,
    DeckWidgetKind.digitalClock => Icons.watch_later_outlined,
    DeckWidgetKind.calendar => Icons.calendar_month,
  },
};

/// [item] with its icon override replaced by [customIconId], every other
/// field carried over unchanged — including clearing a legacy
/// [DeckItem.emoji], which nothing sets any more (see
/// `migrateEmojiIcons`).
///
/// What the picker's Save button applies: changing the icon in
/// `IconPicker` alone, with no action re-chosen underneath it, otherwise
/// has nothing to attach the new icon to and is silently lost — see
/// layout_page.dart's `_PickerDialogState._saveIconOnly`. A [WidgetItem]
/// has no icon of its own and is returned unchanged.
DeckItem withIconOverride(
  DeckItem item, {
  required String? customIconId,
}) => switch (item) {
  AppItem(:final name) => AppItem(name, customIconId: customIconId),
  ActionItem(:final action) => ActionItem(action, customIconId: customIconId),
  ShellItem(:final command, :final label, :final shell) => ShellItem(
    command: command,
    label: label,
    shell: shell,
    customIconId: customIconId,
  ),
  KeyComboItem(:final modifiers, :final key, :final special) => KeyComboItem(
    modifiers: modifiers,
    key: key,
    special: special,
    label: item.label,
    customIconId: customIconId,
  ),
  ShortcutItem(:final name) => ShortcutItem(
    name: name,
    label: item.label,
    customIconId: customIconId,
  ),
  OpenUrlItem(:final url) => OpenUrlItem(
    url: url,
    label: item.label,
    customIconId: customIconId,
  ),
  PlaySoundItem(:final soundId, :final label, :final target) => PlaySoundItem(
    soundId: soundId,
    label: label,
    target: target,
    customIconId: customIconId,
  ),
  ComboItem(:final steps, :final label) => ComboItem(
    steps: steps,
    label: label,
    customIconId: customIconId,
  ),
  WidgetItem() => item,
};
