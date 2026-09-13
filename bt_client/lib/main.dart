import 'package:flutter/material.dart';

import 'src/deck_page.dart';
import 'src/protocol.dart';

void main() {
  runApp(const BtClientApp());
}

class BtClientApp extends StatefulWidget {
  const BtClientApp({super.key});

  @override
  State<BtClientApp> createState() => _BtClientAppState();
}

class _BtClientAppState extends State<BtClientApp> {
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
      title: 'BTLink Client',
      debugShowCheckedModeBanner: false,
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
