import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pure — turns a stored tag back into the [Locale] `MaterialApp.locale`
/// expects. Null (unrecognized, or "system") means "let Flutter resolve
/// the system locale itself" — the same meaning [LocaleStore.load]'s
/// null already carries, kept as one flat mapping rather than a second
/// enum so there is only one place that has to agree with
/// [AppLocalizations.supportedLocales] on what languages exist.
Locale? localeFromTag(String? tag) => switch (tag) {
  'en' => const Locale('en'),
  'ja' => const Locale('ja'),
  'zh_Hant' => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  _ => null,
};

/// Pure — the inverse of [localeFromTag], for saving what the picker UI
/// chose. Only ever called with a [Locale] built from one of that
/// picker's own fixed options, so anything not recognized here is a
/// programming error, not user input to validate — hence the assertion
/// rather than a silent fallback.
String? tagFromLocale(Locale? locale) {
  if (locale == null) return null;
  final tag = switch ((locale.languageCode, locale.scriptCode)) {
    ('en', _) => 'en',
    ('ja', _) => 'ja',
    ('zh', 'Hant') => 'zh_Hant',
    _ => null,
  };
  assert(tag != null, 'unrecognized locale from the language picker: $locale');
  return tag;
}

/// The user's manually-picked app language, distinct from — and
/// overriding — the phone's own system language.
///
/// Stored as a plain language/script string (`'en'`, `'ja'`, `'zh_Hant'`)
/// rather than a [Locale] object, the same reason [DeckTheme] round-
/// trips through a plain wire string elsewhere in this codebase: a
/// primitive survives JSON-free `SharedPreferences` storage without a
/// codec, and there is a fixed, known set of values to parse back.
abstract final class LocaleStore {
  static const _key = 'app_locale';

  /// Null means "follow the system" — the default, and the only
  /// behavior before this has ever been written to.
  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> save(String? languageTag) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageTag == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, languageTag);
    }
  }
}
