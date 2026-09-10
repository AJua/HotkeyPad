import 'package:flutter/material.dart';

import 'src/scan_page.dart';

void main() {
  runApp(const BtClientApp());
}

class BtClientApp extends StatelessWidget {
  const BtClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: const ScanPage(),
    );
  }
}
