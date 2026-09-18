import 'dart:async';

import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'src/deck_page.dart';
import 'src/locale_store.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

void main() {
  runApp(const HotkeyPadClientApp());
}

class HotkeyPadClientApp extends StatefulWidget {
  const HotkeyPadClientApp({super.key});

  @override
  State<HotkeyPadClientApp> createState() => _HotkeyPadClientAppState();
}

class _HotkeyPadClientAppState extends State<HotkeyPadClientApp> {
  /// Set by the host, which owns configuration here as it owns the grid.
  DeckTheme _theme = DeckTheme.system;

  /// The user's own manual language choice — entirely client-side, never
  /// sent to or learned from the host (unlike [_theme]): the host has no
  /// business deciding what language the *person holding the phone*
  /// reads, and a host possibly controlling several different clients
  /// could not pick one language for all of them anyway. Null follows
  /// the system language, same as [MaterialApp.locale]'s own null does.
  Locale? _locale;

  @override
  void initState() {
    super.initState();
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
        DeckTheme.system => ThemeMode.system,
        DeckTheme.light => ThemeMode.light,
        DeckTheme.dark => ThemeMode.dark,
      },
      title: 'HotkeyPad',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: DeckPage(
        onTheme: (theme) => setState(() => _theme = theme),
        locale: _locale,
        onLocale: _setLocale,
      ),
    );
  }
}
