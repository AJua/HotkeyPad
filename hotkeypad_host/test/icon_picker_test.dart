import 'dart:io';

import 'package:hotkeypad_host/src/layout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({
    required String? customIconId,
    required ValueChanged<String?> onChanged,
    Future<String?> Function(String emoji)? saveDisplayText,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: IconPicker(
          customIconId: customIconId,
          onChanged: onChanged,
          saveDisplayText:
              saveDisplayText ??
              (_) async => fail('saveDisplayText not expected'),
        ),
      ),
    );
  }

  Future<void> openTextDialog(WidgetTester tester) async {
    await tester.tap(find.byType(IconPicker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Type text...'));
    await tester.pumpAndSettle();
  }

  group('IconPicker preview', () {
    testWidgets('shows a placeholder when nothing is set', (tester) async {
      await tester.pumpWidget(harness(customIconId: null, onChanged: (_) {}));

      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    });
  });

  group('IconPicker menu', () {
    testWidgets('tapping offers a choice of image or text', (tester) async {
      await tester.pumpWidget(harness(customIconId: null, onChanged: (_) {}));

      await tester.tap(find.byType(IconPicker));
      await tester.pumpAndSettle();

      expect(find.text('Choose image...'), findsOneWidget);
      expect(find.text('Type text...'), findsOneWidget);
    });

    testWidgets('typing an emoji saves it as an image and reports its id', (
      tester,
    ) async {
      String? savedEmoji;
      String? reported = 'unset';
      await tester.pumpWidget(
        harness(
          customIconId: null,
          onChanged: (id) => reported = id,
          saveDisplayText: (emoji) async {
            savedEmoji = emoji;
            return 'img_emoji';
          },
        ),
      );

      await openTextDialog(tester);
      await tester.enterText(find.byType(TextField), ' 🚀 ');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(savedEmoji, '🚀');
      expect(reported, 'img_emoji');
    });

    testWidgets('keeps line breaks in multi-line display text', (tester) async {
      String? savedText;
      await tester.pumpWidget(
        harness(
          customIconId: null,
          onChanged: (_) {},
          saveDisplayText: (text) async {
            savedText = text;
            return 'img_text';
          },
        ),
      );

      await openTextDialog(tester);
      expect(find.text('Display text'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Answer\nme!');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(savedText, 'Answer\nme!');
    });

    testWidgets('an emoji that fails to save reports nothing', (tester) async {
      var called = false;
      await tester.pumpWidget(
        harness(
          customIconId: null,
          onChanged: (_) => called = true,
          saveDisplayText: (_) async => null,
        ),
      );

      await openTextDialog(tester);
      await tester.enterText(find.byType(TextField), '🚀');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });

    testWidgets('Clear in the text dialog reports the override as unset', (
      tester,
    ) async {
      String? reported = 'unset';
      await tester.pumpWidget(
        harness(customIconId: null, onChanged: (id) => reported = id),
      );

      await openTextDialog(tester);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(reported, isNull);
    });

    testWidgets('Cancel in the text dialog reports nothing at all', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        harness(customIconId: null, onChanged: (_) => called = true),
      );

      await openTextDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });

    testWidgets(
      'Choose image asks the native picker',
      (tester) async {
        const channel = MethodChannel('btlink/icons');
        var invoked = false;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'pickImage') invoked = true;
            return null; // Simulates the user cancelling the native panel.
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });
        var called = false;
        await tester.pumpWidget(
          harness(customIconId: null, onChanged: (_) => called = true),
        );

        await tester.tap(find.byType(IconPicker));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose image...'));
        await tester.pumpAndSettle();

        expect(invoked, isTrue);
        // A cancel on the native side must not report a change, and — since
        // it never reaches CustomIconStore.save — never touches real disk.
        expect(called, isFalse);
      },
      // CustomIconStore.pickRaw() gates the whole native-picker call behind
      // Platform.isMacOS — see its doc comment — so on any other platform
      // (CI's Linux runner included) the method channel is never invoked at
      // all, and this test's "invoked" expectation would fail through no
      // fault of the widget under test.
      skip: !Platform.isMacOS,
    );
  });
}
