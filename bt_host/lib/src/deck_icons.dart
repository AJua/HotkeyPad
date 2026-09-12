import 'package:flutter/material.dart';

import 'protocol.dart';

/// Glyph shown for a deck item that has no icon of its own.
///
/// Presentation, so it lives outside the protocol: an app falls back to its
/// initial, while an action has a real glyph.
IconData deckFallbackIcon(DeckItem item) => switch (item) {
  AppItem() => Icons.apps,
  ActionItem(:final action) => switch (action) {
    DeckAction.playPause => Icons.play_arrow,
    DeckAction.next => Icons.skip_next,
    DeckAction.previous => Icons.skip_previous,
    DeckAction.volumeUp => Icons.volume_up,
    DeckAction.volumeDown => Icons.volume_down,
    DeckAction.mute => Icons.volume_off,
  },
};
