import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

import 'custom_icon_store.dart';
import 'deck_icons.dart';
import 'glyph_icon_store.dart';

/// Renders [emoji] to a PNG (see [GlyphIconStore.renderEmojiPng]) and saves
/// it as an ordinary custom icon, returning its id — or null if it could
/// not be written.
///
/// This is all an emoji ever is once picked: an image the host drew, sent
/// to the client like any other custom icon, so the client never has to
/// know an emoji was involved at all.
Future<String?> saveEmojiIcon(String emoji) async =>
    CustomIconStore.save(await GlyphIconStore.renderEmojiPng(emoji));

/// True if any button in [layout] still carries a legacy [DeckItem.emoji]
/// — written by a build from before emoji became images, or restored from
/// one of its backups — and so needs [migrateEmojiIcons].
bool hasEmojiIcons(DeckLayout layout) {
  for (final slot in layout.slots) {
    if (slot == null) continue;
    if (DeckItem.parse(slot.value)?.emoji != null) return true;
  }
  return false;
}

/// [layout] with every button's legacy [DeckItem.emoji] turned into a
/// custom icon via [saveEmoji], which is [saveEmojiIcon] outside of tests.
///
/// An emoji that fails to save is left in place rather than dropped, so a
/// later load can try again instead of the button silently losing its icon.
/// Only top-level buttons are visited: a [ComboItem]'s steps never show an
/// icon on the deck.
Future<DeckLayout> migrateEmojiIcons(
  DeckLayout layout, {
  Future<String?> Function(String emoji) saveEmoji = saveEmojiIcon,
}) async {
  var migrated = layout;
  for (var index = 0; index < layout.slots.length; index++) {
    final slot = layout.slots[index];
    if (slot == null) continue;
    final item = DeckItem.parse(slot.value);
    final emoji = item?.emoji;
    if (item == null || emoji == null) continue;
    final id = await saveEmoji(emoji);
    if (id == null) continue;
    migrated = migrated.withSlot(
      index,
      withIconOverride(item, customIconId: id).stored,
    );
  }
  return migrated;
}
