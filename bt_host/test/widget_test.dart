import 'package:bt_host/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds without a Bluetooth implementation registered', (
    tester,
  ) async {
    // No plugin is registered in the test host, which is the same situation
    // the web build is in. The app must degrade instead of throwing.
    await tester.pumpWidget(const BtHostApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
