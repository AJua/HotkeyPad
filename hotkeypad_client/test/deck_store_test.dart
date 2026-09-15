import 'package:hotkeypad_client/src/deck_store.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
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
      expect(loaded!.slots[4]?.value, 'app:Safari');
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

  group('appearance cache', () {
    test('defaults to no background at full opacity, cover', () async {
      SharedPreferences.setMockInitialValues({});

      final cached = await DeckStore.loadAppearance('host-1');

      expect(cached.showAppBar, isTrue);
      expect(cached.showPageDots, isTrue);
      expect(cached.backgroundImageId, isNull);
      expect(cached.backgroundOpacity, 1.0);
      expect(cached.backgroundFit, BackgroundFit.cover);
    });

    test('round-trips a background image, opacity, and fit', () async {
      SharedPreferences.setMockInitialValues({});

      await DeckStore.saveAppearance(
        'host-1',
        DeckTheme.dark,
        false,
        showAppBar: false,
        showPageDots: false,
        backgroundImageId: 'bg_1',
        backgroundOpacity: 0.42,
        backgroundFit: BackgroundFit.contain,
      );
      final cached = await DeckStore.loadAppearance('host-1');

      expect(cached.theme, DeckTheme.dark);
      expect(cached.showLabels, isFalse);
      expect(cached.showAppBar, isFalse);
      expect(cached.showPageDots, isFalse);
      expect(cached.backgroundImageId, 'bg_1');
      expect(cached.backgroundOpacity, 0.42);
      expect(cached.backgroundFit, BackgroundFit.contain);
    });

    test(
      'clearing the background removes it rather than storing empty',
      () async {
        SharedPreferences.setMockInitialValues({});
        await DeckStore.saveAppearance(
          'host-1',
          DeckTheme.system,
          true,
          backgroundImageId: 'bg_1',
        );

        await DeckStore.saveAppearance('host-1', DeckTheme.system, true);

        expect(
          (await DeckStore.loadAppearance('host-1')).backgroundImageId,
          isNull,
        );
      },
    );

    test('keeps hosts separate', () async {
      SharedPreferences.setMockInitialValues({});
      await DeckStore.saveAppearance(
        'host-1',
        DeckTheme.system,
        true,
        backgroundImageId: 'bg_1',
      );
      await DeckStore.saveAppearance('host-2', DeckTheme.system, true);

      expect(
        (await DeckStore.loadAppearance('host-1')).backgroundImageId,
        'bg_1',
      );
      expect(
        (await DeckStore.loadAppearance('host-2')).backgroundImageId,
        isNull,
      );
    });
  });
}
