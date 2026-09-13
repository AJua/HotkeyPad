import 'package:flutter/material.dart';

import 'src/host_page.dart';
import 'src/protocol.dart';
import 'src/settings_store.dart';

void main() {
  runApp(const BtHostApp());
}

class BtHostApp extends StatefulWidget {
  const BtHostApp({super.key});

  @override
  State<BtHostApp> createState() => _BtHostAppState();
}

class _BtHostAppState extends State<BtHostApp> {
  DeckTheme _theme = DeckTheme.system;

  @override
  void initState() {
    super.initState();
    SettingsStore.load().then((appearance) {
      if (mounted) setState(() => _theme = appearance.theme);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: switch (_theme) {
        DeckTheme.light => ThemeMode.light,
        DeckTheme.dark => ThemeMode.dark,
        DeckTheme.system => ThemeMode.system,
      },
      title: 'BTLink Host',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: HostPage(
        onThemeChanged: (theme) => setState(() => _theme = theme),
      ),
    );
  }
}
