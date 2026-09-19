import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// The key to fetch a rendered icon for, or null when there is nothing to
/// show but a plain letter-avatar placeholder.
///
/// Every case here — a custom image, an emoji, an app's own icon, or an
/// action's built-in glyph — is rendered by the host into a PNG and sent
/// over the same [RequestIcon] transfer, so `_DeckButton` only ever has
/// to decide between "there are icon bytes" and "there are not"; it does
/// not draw an emoji or a `DeckAction`'s glyph itself. The `emoji:`/
/// `action:` prefixes are this client's own invention, not part of the
/// protocol (an id is just an opaque string to it) — see
/// `hotkeypad_host`'s `GlyphIconStore`, the other end that parses them.
String? iconKeyFor(DeckItem item) {
  final emoji = item.emoji;
  if (emoji != null) return 'emoji:$emoji';
  final customIconId = item.customIconId;
  if (customIconId != null) return customIconId;
  if (item is AppItem) return item.name;
  if (item is ActionItem) return 'action:${item.action.wire}';
  return null;
}
