import 'package:hotkeypad_host/l10n/app_localizations.dart';
import 'package:hotkeypad_host/src/builtin_background_store.dart';
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
    testWidgets(
      'shows a tile for no background, every builtin scene, and one to add '
      'a custom image',
      (tester) async {
        await tester.pumpWidget(harness(imageId: null, onChanged: (_) {}));
        await tester.pumpAndSettle();

        expect(find.byTooltip('None'), findsOneWidget);
        for (final name in BuiltinBackgroundStore.ids) {
          expect(
            find.byTooltip(
              name[0].toUpperCase() + name.substring(1),
            ),
            findsOneWidget,
            reason: 'expected a tile tooltipped for $name',
          );
        }
        expect(find.byTooltip('Choose image...'), findsOneWidget);
        // Nothing set — the "none" tile's placeholder icon and the
        // custom tile's "add" icon are the only two icon glyphs shown.
        expect(find.byIcon(Icons.block), findsOneWidget);
        expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
      },
    );

    testWidgets('tapping a builtin scene reports its id', (tester) async {
      String? reported = 'unset';
      await tester.pumpWidget(
        harness(imageId: null, onChanged: (id) => reported = id),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Spring'));

      expect(reported, BuiltinBackgroundStore.idFor('spring'));
    });

    testWidgets('tapping None reports null', (tester) async {
      String? reported = 'unset';
      await tester.pumpWidget(
        harness(
          imageId: BuiltinBackgroundStore.idFor('winter'),
          onChanged: (id) => reported = id,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('None'));

      expect(reported, isNull);
    });

    testWidgets(
      'a custom image id (not a builtin one) is read back through the '
      'background image store rather than rendered procedurally',
      (tester) async {
        await tester.pumpWidget(harness(imageId: 'bg_1', onChanged: (_) {}));
        // The store has no real file for this id on a test machine, so the
        // preview settles on the placeholder — this only exercises the
        // routing logic, not a real read.
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
        expect(find.byIcon(Icons.block), findsOneWidget);
      },
    );
  });
}
