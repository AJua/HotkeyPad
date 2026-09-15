import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'src/deck_page.dart';
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: DeckPage(
        onTheme: (theme) => setState(() => _theme = theme),
      ),
    );
  }
}
