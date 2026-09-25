import 'package:flutter/material.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// The key to fetch a rendered icon for, or null when nothing overrides the
/// built-in glyph — an emoji, checked separately by the caller, always wins.
///
/// A custom image takes priority over an app's own icon, matching how
/// [DeckItem.emoji] already takes priority over both. Presentation, so it
/// lives outside the protocol, same as [deckFallbackIcon].
String? iconKeyFor(DeckItem item) =>
    item.customIconId ?? (item is AppItem ? item.name : null);

/// Glyph shown for a deck item that has neither a custom emoji, a custom
/// image, nor an app icon of its own.
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
