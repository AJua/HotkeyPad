import 'package:flutter/material.dart';

import 'protocol.dart';

/// One button on the deck: either an app to launch or an action to perform.
///
/// Stored as a prefixed string so a layout saved by an older build — which
/// only ever held bare app names — still loads.
sealed class DeckItem {
  const DeckItem();

  String get stored;
  String get label;
  IconData get fallbackIcon;

  /// Returns null for a stored value this build does not understand, so an
  /// action added by a newer client is skipped rather than shown as a button
  /// that does nothing.
  static DeckItem? parse(String stored) {
    if (stored.startsWith('act:')) {
      final action = DeckAction.fromWire(stored.substring(4));
      return action == null ? null : ActionItem(action);
    }
    final name = stored.startsWith('app:') ? stored.substring(4) : stored;
    return name.isEmpty ? null : AppItem(name);
  }

  @override
  bool operator ==(Object other) =>
      other is DeckItem && other.stored == stored;

  @override
  int get hashCode => stored.hashCode;
}

final class AppItem extends DeckItem {
  const AppItem(this.name);

  final String name;

  @override
  String get stored => 'app:$name';

  @override
  String get label => name;

  @override
  IconData get fallbackIcon => Icons.apps;
}

final class ActionItem extends DeckItem {
  const ActionItem(this.action);

  final DeckAction action;

  @override
  String get stored => 'act:${action.wire}';

  @override
  String get label => action.label;

  @override
  IconData get fallbackIcon => switch (action) {
    DeckAction.playPause => Icons.play_arrow,
    DeckAction.next => Icons.skip_next,
    DeckAction.previous => Icons.skip_previous,
    DeckAction.volumeUp => Icons.volume_up,
    DeckAction.volumeDown => Icons.volume_down,
    DeckAction.mute => Icons.volume_off,
  };
}
