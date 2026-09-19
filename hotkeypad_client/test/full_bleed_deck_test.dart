import 'package:hotkeypad_client/src/deck_page.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildFullBleedDeck', () {
    testWidgets('the background fills the whole screen even where the body is '
        "inset for a notch — regression: an earlier version wrapped the "
        'background in the same SafeArea as the body, leaving a bar of '
        "blank space on the notch's edge (most visible in landscape, "
        'where the notch/Dynamic Island sits on a side rather than the '
        'top).', (tester) async {
      // Stands in for a landscape phone's Dynamic Island having moved
      // to a side edge: a real SafeArea insets its child by exactly
      // this on that side.
      // FakeViewPadding is in physical pixels, same as the real platform
      // API it stands in for — pinning the ratio to 1 keeps the numbers
      // below directly comparable to the logical sizes SafeArea works in.
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.padding = const FakeViewPadding(left: 59, bottom: 21);
      addTearDown(tester.view.resetPadding);

      const bodyKey = Key('body-stand-in');
      await tester.pumpWidget(
        MaterialApp(
          home: buildFullBleedDeck(
            backgroundImage: null,
            backgroundOpacity: 1,
            backgroundFit: BackgroundFit.cover,
            body: Container(key: bodyKey, color: Colors.blue),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;

      // The background — found via DeckBackground's own Positioned.fill
      // ancestor, since a null image renders nothing sized on its own
      // (see deck_background_test.dart) — covers the full screen,
      // starting at the true origin, not inset by the simulated notch.
      final backgroundBox = tester.renderObject<RenderBox>(
        find.ancestor(
          of: find.byType(DeckBackground),
          matching: find.byType(Positioned),
        ),
      );
      expect(backgroundBox.size, screenSize);
      expect(backgroundBox.localToGlobal(Offset.zero), Offset.zero);

      // The body, in contrast, is the thing SafeArea actually protects:
      // inset by exactly the simulated padding on every side that has
      // one, not filling the raw screen the way the background does.
      final bodySize = tester.getSize(find.byKey(bodyKey));
      expect(bodySize.width, screenSize.width - 59);
      expect(bodySize.height, screenSize.height - 21);
    });

    testWidgets('an overlay is also kept inside the safe area', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.padding = const FakeViewPadding(left: 59);
      addTearDown(tester.view.resetPadding);

      const overlayKey = Key('overlay-stand-in');
      await tester.pumpWidget(
        MaterialApp(
          home: buildFullBleedDeck(
            backgroundImage: null,
            backgroundOpacity: 1,
            backgroundFit: BackgroundFit.cover,
            body: const SizedBox.shrink(),
            overlay: Container(key: overlayKey, color: Colors.black54),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        tester.getSize(find.byKey(overlayKey)).width,
        screenSize.width - 59,
      );
    });

    testWidgets("the Scaffold's background matches EdgeBarScaffold's exactly — "
        'regression: with none set, a plain Scaffold falls back to '
        "colorScheme.surface, a different Material 3 tone than "
        'surfaceContainer, so the deck visibly changed shade under the '
        'grid depending only on whether the app bar happened to be on', (
      tester,
    ) async {
      late Color expected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.blue),
          home: Builder(
            builder: (context) {
              expected = Theme.of(context).colorScheme.surfaceContainer;
              return buildFullBleedDeck(
                backgroundImage: null,
                backgroundOpacity: 1,
                backgroundFit: BackgroundFit.cover,
                body: const SizedBox.shrink(),
              );
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, expected);
    });

    testWidgets('with no inset at all, background and body agree', (
      tester,
    ) async {
      const bodyKey = Key('body-stand-in');
      await tester.pumpWidget(
        MaterialApp(
          home: buildFullBleedDeck(
            backgroundImage: null,
            backgroundOpacity: 1,
            backgroundFit: BackgroundFit.cover,
            body: Container(key: bodyKey, color: Colors.blue),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final backgroundBox = tester.renderObject<RenderBox>(
        find.ancestor(
          of: find.byType(DeckBackground),
          matching: find.byType(Positioned),
        ),
      );
      expect(backgroundBox.size, tester.getSize(find.byKey(bodyKey)));
    });
  });
}
