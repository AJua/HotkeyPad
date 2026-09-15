import 'package:hotkeypad_host/src/layout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({
    required String? emoji,
    required String? customIconId,
    required void Function(String? emoji, String? customIconId) onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: IconPicker(
          emoji: emoji,
          customIconId: customIconId,
          onChanged: onChanged,
        ),
      ),
    );
  }

  group('IconPicker preview', () {
    testWidgets('shows the emoji when set', (tester) async {
      await tester.pumpWidget(
        harness(emoji: '🧭', customIconId: null, onChanged: (_, _) {}),
      );

      expect(find.text('🧭'), findsOneWidget);
    });

    testWidgets('shows a placeholder when nothing is set', (tester) async {
      await tester.pumpWidget(
        harness(emoji: null, customIconId: null, onChanged: (_, _) {}),
      );

      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    });
  });

  group('IconPicker menu', () {
    testWidgets('tapping offers a choice of image or text', (tester) async {
      await tester.pumpWidget(
        harness(emoji: null, customIconId: null, onChanged: (_, _) {}),
      );

      await tester.tap(find.byType(IconPicker));
      await tester.pumpAndSettle();

      expect(find.text('Choose image...'), findsOneWidget);
      expect(find.text('Type text...'), findsOneWidget);
    });

    testWidgets('typing text reports it and clears any image', (tester) async {
      String? reportedEmoji;
      String? reportedIconId;
      await tester.pumpWidget(
        harness(
          emoji: null,
          customIconId: 'img_old',
          onChanged: (emoji, customIconId) {
            reportedEmoji = emoji;
            reportedIconId = customIconId;
          },
        ),
      );

      await tester.tap(find.byType(IconPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type text...'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '🚀');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(reportedEmoji, '🚀');
      expect(reportedIconId, isNull);
    });

    testWidgets('Clear in the text dialog reports both as unset', (
      tester,
    ) async {
      String? reportedEmoji = 'unset';
      String? reportedIconId = 'unset';
      await tester.pumpWidget(
        harness(
          emoji: '🧭',
          customIconId: null,
          onChanged: (emoji, customIconId) {
            reportedEmoji = emoji;
            reportedIconId = customIconId;
          },
        ),
      );

      await tester.tap(find.byType(IconPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type text...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(reportedEmoji, isNull);
      expect(reportedIconId, isNull);
    });

    testWidgets('Cancel in the text dialog reports nothing at all', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        harness(
          emoji: '🧭',
          customIconId: null,
          onChanged: (_, _) => called = true,
        ),
      );

      await tester.tap(find.byType(IconPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type text...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      // The original emoji is still showing, untouched.
      expect(find.text('🧭'), findsOneWidget);
    });

    testWidgets('Choose image asks the native picker', (tester) async {
      const channel = MethodChannel('btlink/icons');
      var invoked = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'pickImage') invoked = true;
        return null; // Simulates the user cancelling the native panel.
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      var called = false;
      await tester.pumpWidget(
        harness(
          emoji: null,
          customIconId: null,
          onChanged: (_, _) => called = true,
        ),
      );

      await tester.tap(find.byType(IconPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose image...'));
      await tester.pumpAndSettle();

      expect(invoked, isTrue);
      // A cancel on the native side must not report a change, and — since
      // it never reaches CustomIconStore.save — never touches real disk.
      expect(called, isFalse);
    });
  });
}
