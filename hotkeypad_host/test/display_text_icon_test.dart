import 'dart:math';

import 'package:hotkeypad_host/src/display_text_icon.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

DeckLayout _layoutWith(List<DeckItem?> items) {
  var layout = DeckLayout.empty();
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    if (item != null) layout = layout.withSlot(index, item.stored);
  }
  return layout;
}

DeckItem? _itemAt(DeckLayout layout, int index) {
  final stored = layout.slots[index]?.value;
  return stored == null ? null : DeckItem.parse(stored);
}

void main() {
  group('displayTextPlateColor', () {
    test('varies with the random source', () {
      final colors = {
        for (var seed = 0; seed < 20; seed++)
          displayTextPlateColor(Random(seed)),
      };

      expect(colors.length, greaterThan(1));
    });

    test('is always an opaque pastel light enough for dark text', () {
      final random = Random(42);
      for (var i = 0; i < 200; i++) {
        final color = displayTextPlateColor(random);
        expect(color.a, 1.0);
        expect(color.computeLuminance(), greaterThan(0.45));
      }
    });
  });

  group('hasEmojiIcons', () {
    test('is false for a layout with no emoji', () {
      final layout = _layoutWith([
        const AppItem('Safari'),
        const ActionItem(DeckAction.mute, customIconId: 'img_1'),
      ]);

      expect(hasEmojiIcons(layout), isFalse);
    });

    test('is true once any button carries an emoji', () {
      final layout = _layoutWith([
        const AppItem('Safari'),
        null,
        const ShellItem(command: 'say hi', label: 'Hi', emoji: '👋'),
      ]);

      expect(hasEmojiIcons(layout), isTrue);
    });
  });

  group('migrateEmojiIcons', () {
    test('turns each emoji into a custom icon, keeping the rest', () async {
      final layout = _layoutWith([
        const AppItem('Safari', emoji: '🧭'),
        const AppItem('Mail'),
        const OpenUrlItem(url: 'https://example.com', label: 'Ex', emoji: '🔗'),
      ]);
      final saved = <String>[];

      final migrated = await migrateEmojiIcons(
        layout,
        saveDisplayText: (emoji) async {
          saved.add(emoji);
          return 'img_${saved.length}';
        },
      );

      expect(saved, ['🧭', '🔗']);
      expect(hasEmojiIcons(migrated), isFalse);
      final safari = _itemAt(migrated, 0)! as AppItem;
      expect(safari.name, 'Safari');
      expect(safari.customIconId, 'img_1');
      expect(_itemAt(migrated, 1), const AppItem('Mail'));
      final url = _itemAt(migrated, 2)! as OpenUrlItem;
      expect(url.url, 'https://example.com');
      expect(url.label, 'Ex');
      expect(url.customIconId, 'img_2');
    });

    test('an emoji wins over a custom icon it was stored alongside, '
        'matching how it used to render', () async {
      final layout = _layoutWith([
        const AppItem('Safari', emoji: '🧭', customIconId: 'img_old'),
      ]);

      final migrated = await migrateEmojiIcons(
        layout,
        saveDisplayText: (_) async => 'img_new',
      );

      expect(_itemAt(migrated, 0)!.customIconId, 'img_new');
      expect(_itemAt(migrated, 0)!.emoji, isNull);
    });

    test('leaves an emoji in place when it cannot be saved', () async {
      final layout = _layoutWith([const AppItem('Safari', emoji: '🧭')]);

      final migrated = await migrateEmojiIcons(
        layout,
        saveDisplayText: (_) async => null,
      );

      expect(_itemAt(migrated, 0)!.emoji, '🧭');
      expect(hasEmojiIcons(migrated), isTrue);
    });
  });
}
