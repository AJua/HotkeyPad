import 'package:bt_client/src/deck_item.dart';
import 'package:bt_client/src/deck_store.dart';
import 'package:bt_client/src/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('reordered', () {
    const items = ['a', 'b', 'c', 'd'];

    test('moves an item down', () {
      // Dragging 'a' below 'c' reports newIndex 3, meaning "before d".
      expect(DeckStore.reordered(items, 0, 3), ['b', 'c', 'a', 'd']);
    });

    test('moves an item up', () {
      expect(DeckStore.reordered(items, 3, 0), ['d', 'a', 'b', 'c']);
    });

    test('moves an item to the end', () {
      expect(DeckStore.reordered(items, 0, 4), ['b', 'c', 'd', 'a']);
    });

    test('leaves the input untouched', () {
      DeckStore.reordered(items, 0, 3);
      expect(items, ['a', 'b', 'c', 'd']);
    });
  });

  group('persistence', () {
    test('returns a modifiable list when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});

      // The session edits this list in place, so an unmodifiable empty
      // fallback breaks every first-run deck.
      final deck = await DeckStore.load('fresh-host');

      expect(deck, isEmpty);
      expect(() => deck.add('Safari'), returnsNormally);
      expect(() => deck.remove('Safari'), returnsNormally);
    });

    test('returns a modifiable list when a deck is stored', () async {
      SharedPreferences.setMockInitialValues({});
      await DeckStore.save('host-1', ['Safari']);

      final deck = await DeckStore.load('host-1');

      expect(() => deck.add('Terminal'), returnsNormally);
      expect(deck, ['Safari', 'Terminal']);
    });

    test('round-trips a deck and keeps hosts separate', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await DeckStore.load('host-1'), isEmpty);

      await DeckStore.save('host-1', ['Safari', 'Terminal']);
      await DeckStore.save('host-2', ['Notes']);

      expect(await DeckStore.load('host-1'), ['Safari', 'Terminal']);
      expect(await DeckStore.load('host-2'), ['Notes']);
    });
  });

  group('DeckItem', () {
    test('round-trips both kinds', () {
      const items = [AppItem('Safari'), ActionItem(DeckAction.playPause)];

      for (final item in items) {
        expect(DeckItem.parse(item.stored), item);
      }
    });

    test('reads a bare app name saved by an older build', () {
      // Layouts stored before actions existed held the name with no prefix.
      expect(DeckItem.parse('Safari'), const AppItem('Safari'));
    });

    test('skips an action this build does not know', () {
      expect(DeckItem.parse('act:teleport'), isNull);
      expect(DeckItem.parse(''), isNull);
    });

    test('an app and an action never collide', () {
      expect(
        const AppItem('playpause').stored,
        isNot(const ActionItem(DeckAction.playPause).stored),
      );
    });
  });
}
