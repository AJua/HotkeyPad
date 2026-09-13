import 'package:flutter/material.dart';

import 'protocol.dart';

/// Glyph shown for a deck item that has neither a custom emoji nor an app
/// icon of its own.
///
/// Presentation, so it lives outside the protocol.
IconData deckFallbackIcon(DeckItem item) => switch (item) {
  AppItem() => Icons.apps,
  ShellItem() => Icons.terminal,
  ShortcutItem() => Icons.bolt,
  ActionItem(:final action) => switch (action) {
    DeckAction.playPause => Icons.play_arrow,
    DeckAction.next => Icons.skip_next,
    DeckAction.previous => Icons.skip_previous,
    DeckAction.volumeUp => Icons.volume_up,
    DeckAction.volumeDown => Icons.volume_down,
    DeckAction.mute => Icons.volume_off,
  },
};
