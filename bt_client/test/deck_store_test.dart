import 'package:bt_client/src/deck_store.dart';
import 'package:bt_link_protocol/bt_link_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('layout cache', () {
    test('returns null when nothing is cached', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await DeckStore.load('host-1'), isNull);
    });

    test('round-trips a layout and keeps hosts separate', () async {
      SharedPreferences.setMockInitialValues({});
      final layout = DeckLayout.empty().withSlot(4, 'app:Safari');

      await DeckStore.save('host-1', layout);
      await DeckStore.save('host-2', DeckLayout.empty(columns: 2, rows: 2));

      final loaded = await DeckStore.load('host-1');
      expect(loaded!.slots[4], 'app:Safari');
      expect(loaded.columns, DeckLayout.defaultColumns);
      expect((await DeckStore.load('host-2'))!.columns, 2);
    });

    test('discards a corrupt entry instead of throwing', () async {
      SharedPreferences.setMockInitialValues({'layout:host-1': 'not json'});

      expect(await DeckStore.load('host-1'), isNull);
      // The bad entry is cleared, so the next load does not retry it.
      expect(await DeckStore.load('host-1'), isNull);
    });
  });
}
