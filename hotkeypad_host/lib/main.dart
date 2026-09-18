import 'dart:async';

import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'src/host_page.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'src/locale_store.dart';
import 'src/settings_store.dart';

/// iPhone 17 Pro's "Cosmic Orange" — see the client's own main.dart for why
/// this exact value rather than [Colors.orange].
const _kSeedColor = Color(0xFFF77E2D);

void main() {
  runApp(const HotkeyPadHostApp());
}

class HotkeyPadHostApp extends StatefulWidget {
  const HotkeyPadHostApp({super.key});

  @override
  State<HotkeyPadHostApp> createState() => _HotkeyPadHostAppState();
}

class _HotkeyPadHostAppState extends State<HotkeyPadHostApp> {
  DeckTheme _theme = DeckTheme.system;

  /// The user's own manually-picked language — see [LocaleStore]'s doc
  /// comment on why this never has anything to do with the client's own
  /// language setting. Null follows the system language, same as
  /// [MaterialApp.locale]'s own null does.
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    SettingsStore.load().then((appearance) {
      if (mounted) setState(() => _theme = appearance.theme);
    });
    unawaited(_loadLocale());
  }

  Future<void> _loadLocale() async {
    final tag = await LocaleStore.load();
    if (mounted) setState(() => _locale = localeFromTag(tag));
  }

  Future<void> _setLocale(Locale? locale) async {
    setState(() => _locale = locale);
    await LocaleStore.save(tagFromLocale(locale));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: switch (_theme) {
        DeckTheme.light => ThemeMode.light,
        DeckTheme.dark => ThemeMode.dark,
        DeckTheme.system => ThemeMode.system,
      },
      title: 'HotkeyPad Host',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorSchemeSeed: _kSeedColor,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: _kSeedColor,
        brightness: Brightness.dark,
      ),
      home: HostPage(
        onThemeChanged: (theme) => setState(() => _theme = theme),
        locale: _locale,
        onLocale: _setLocale,
      ),
    );
  }
}
