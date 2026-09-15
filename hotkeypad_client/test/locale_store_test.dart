import 'package:flutter/widgets.dart';
import 'package:hotkeypad_client/src/locale_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localeFromTag', () {
    test('maps each known tag to its Locale', () {
      expect(localeFromTag('en'), const Locale('en'));
      expect(localeFromTag('ja'), const Locale('ja'));
      expect(
        localeFromTag('zh_Hant'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    });

    test('null means follow the system', () {
      expect(localeFromTag(null), isNull);
    });

    test('an unrecognized tag also falls back to the system', () {
      expect(localeFromTag('fr'), isNull);
      expect(localeFromTag(''), isNull);
    });
  });

  group('tagFromLocale', () {
    test('maps each picker locale back to its tag', () {
      expect(tagFromLocale(const Locale('en')), 'en');
      expect(tagFromLocale(const Locale('ja')), 'ja');
      expect(
        tagFromLocale(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ),
        'zh_Hant',
      );
    });

    test('null means "system", same as it does for localeFromTag', () {
      expect(tagFromLocale(null), isNull);
    });

    test('round-trips through localeFromTag for every known tag', () {
      for (final tag in ['en', 'ja', 'zh_Hant']) {
        expect(tagFromLocale(localeFromTag(tag)), tag);
      }
    });
  });
}
