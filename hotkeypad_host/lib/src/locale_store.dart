import 'dart:io';

import 'package:flutter/widgets.dart';

import 'config_dir.dart';

/// The user's manually-picked app language, distinct from — and
/// overriding — this Mac's own system language. Entirely independent of
/// `hotkeypad_client`'s own copy of this same store: the host and the
/// phone are two different people's UIs (or the same person's, on two
/// different devices), and there is no reason a language choice made on
/// one should follow to the other.
///
/// Persisted the same `~/.config/HotkeyPad/*` file way as every other
/// host-side store (`ClientTrustStore`, `UpdateStore`, ...) — plain text,
/// not JSON, since there is exactly one value to hold.
abstract final class LocaleStore {
  static File? get _file {
    final dir = ConfigDir.path;
    if (dir == null) return null;
    return File('$dir/locale');
  }

  /// Null means "follow the system" — the default, and the only
  /// behavior before this has ever been written to.
  static Future<String?> load() async {
    final file = _file;
    if (file == null) return null;
    try {
      if (!file.existsSync()) return null;
      final tag = (await file.readAsString()).trim();
      return tag.isEmpty ? null : tag;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String? languageTag) async {
    final file = _file;
    if (file == null) return;
    try {
      if (languageTag == null) {
        if (file.existsSync()) await file.delete();
        return;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(languageTag, flush: true);
    } on FileSystemException {
      // Losing this on disk is better than taking the app down; the
      // in-memory state the caller holds still has it for the rest of
      // this run.
    }
  }
}

/// Pure — turns a stored tag back into the [Locale] `MaterialApp.locale`
/// expects. Null (unrecognized, or "system") means "let Flutter resolve
/// the system locale itself".
Locale? localeFromTag(String? tag) => switch (tag) {
  'en' => const Locale('en'),
  'ja' => const Locale('ja'),
  'zh_Hant' => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  _ => null,
};

/// Pure — the inverse of [localeFromTag], for saving what the picker UI
/// chose. Only ever called with a [Locale] built from that picker's own
/// fixed options, so anything unrecognized is a programming error, not
/// user input to validate.
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
