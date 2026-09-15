import 'package:flutter/material.dart';

import 'src/host_page.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'src/settings_store.dart';

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
      title: 'HotkeyPad Host',
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
