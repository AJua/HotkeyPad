import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

import 'custom_icon_store.dart';
import 'deck_icons.dart';
import 'glyph_icon_store.dart';

/// Renders [text] — display text: an emoji, a word, or several lines — to a
/// PNG (see [GlyphIconStore.renderDisplayTextPng]), puts it
/// on the same plate a picked image gets (see
/// [CustomIconStore.cropToSquarePng]) so the two match in size and corner
/// rounding, and saves it as an ordinary custom icon, returning its id — or
/// null if it could not be rendered or written.
///
/// The plate gets a random colour (see [displayTextPlateColor]) so a deck
/// of text buttons is not a wall of identical white squares.
///
/// This is all display text ever is once picked: an image the host drew,
/// sent to the client like any other custom icon, so the client never has
/// to know text was involved at all.
Future<String?> saveDisplayTextIcon(String text) async {
  // Drawn at twice the icon size: the plate is composed on a canvas that
  // large before being trimmed down (see cropToSquarePng), so a glyph
  // rendered any smaller would be scaled up and come out soft.
  final plated = await CustomIconStore.cropToSquarePng(
    await GlyphIconStore.renderDisplayTextPng(
      text,
      size: HotkeyPad.iconSize * 2,
    ),
    plateColor: displayTextPlateColor(Random()),
  );
  return plated == null ? null : CustomIconStore.save(plated);
}

/// A random pastel for display text's plate: any hue, but always light enough
/// that the near-black [GlyphIconStore] draws plain text in stays legible
/// on it, and soft enough that a colour emoji on top still stands out.
Color displayTextPlateColor(Random random) =>
    HSLColor.fromAHSL(1, random.nextDouble() * 360, 0.7, 0.82).toColor();

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
/// custom icon via [saveDisplayText], which is [saveDisplayTextIcon] outside of tests.
///
/// An emoji that fails to save is left in place rather than dropped, so a
/// later load can try again instead of the button silently losing its icon.
/// Only top-level buttons are visited: a [ComboItem]'s steps never show an
/// icon on the deck.
Future<DeckLayout> migrateEmojiIcons(
  DeckLayout layout, {
  Future<String?> Function(String emoji) saveDisplayText = saveDisplayTextIcon,
}) async {
  var migrated = layout;
  for (var index = 0; index < layout.slots.length; index++) {
    final slot = layout.slots[index];
    if (slot == null) continue;
    final item = DeckItem.parse(slot.value);
    final emoji = item?.emoji;
    if (item == null || emoji == null) continue;
    final id = await saveDisplayText(emoji);
    if (id == null) continue;
    migrated = migrated.withSlot(
      index,
      withIconOverride(item, customIconId: id).stored,
    );
  }
  return migrated;
}
