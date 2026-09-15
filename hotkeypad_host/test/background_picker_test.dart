import 'package:hotkeypad_host/l10n/app_localizations.dart';
import 'package:hotkeypad_host/src/layout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({
    required String? imageId,
    required ValueChanged<String?> onChanged,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BackgroundPicker(imageId: imageId, onChanged: onChanged),
      ),
    );
  }

  group('BackgroundPicker', () {
    testWidgets('offers to choose an image when nothing is set', (
      tester,
    ) async {
      await tester.pumpWidget(harness(imageId: null, onChanged: (_) {}));

      expect(find.text('Choose image...'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('offers to change or remove an existing image', (
      tester,
    ) async {
      await tester.pumpWidget(harness(imageId: 'bg_1', onChanged: (_) {}));
      // The store has no real file for this id on a test machine, so the
      // preview settles on the placeholder — this only exercises the label
      // logic, not a real read.
      await tester.pumpAndSettle();

      expect(find.text('Change...'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('tapping Remove reports null', (tester) async {
      String? reported = 'unset';
      await tester.pumpWidget(
        harness(imageId: 'bg_1', onChanged: (id) => reported = id),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));

      expect(reported, isNull);
    });
  });
}
