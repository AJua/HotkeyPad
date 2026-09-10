import 'package:flutter/material.dart';

import 'src/host_page.dart';

void main() {
  runApp(const BtHostApp());
}

class BtHostApp extends StatelessWidget {
  const BtHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: const HostPage(),
    );
  }
}
