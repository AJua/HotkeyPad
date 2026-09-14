import 'dart:convert';

import 'package:bt_client/src/background_fit.dart';
import 'package:bt_client/src/deck_page.dart';
import 'package:bt_link_protocol/bt_link_protocol.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        Container,
        Image,
        Key,
        KeyedSubtree,
        MaterialApp,
        MemoryImage,
        Opacity,
        Positioned,
        Scaffold,
        Stack,
        Widget;
import 'package:flutter_test/flutter_test.dart';

/// Stand-in "image" bytes — the smallest possible real PNG (a single
/// transparent pixel), not arbitrary garbage: [Image.memory] schedules a
/// decode the moment it builds, whether or not a test ever awaits it, and
/// invalid bytes surface as an async decode error on some *later*
/// `tester.takeException()` call (Flutter's image cache remembers the
/// failed decode across tests reusing the same bytes) rather than failing
/// predictably in the test that actually caused it. A real PNG sidesteps
/// that class of flake entirely — only the widget *build*, not the decode
/// result, is under test here regardless.
final _bytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// [DeckBackground] must be wrapped in `Positioned.fill` by its *caller* —
/// see deck_page.dart's own Stack — never left un-positioned itself: a
/// `Stack` sizes itself from its non-positioned children alone, and a null
/// image's `SizedBox.shrink()` is exactly such a child, sized to zero. Every
/// test here wraps it the same way to match, and 'collapses the whole deck
/// to zero size' below exists specifically to catch a regression back to
/// leaving it un-positioned.
Widget _harness(Widget background) => MaterialApp(
  home: Scaffold(body: Stack(children: [Positioned.fill(child: background)])),
);

void main() {
  group('DeckBackground', () {
    testWidgets('builds nothing for a null image', (tester) async {
      await tester.pumpWidget(
        _harness(
          const DeckBackground(
            image: null,
            opacity: 1,
            fit: BackgroundFit.cover,
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wraps the image in the requested opacity', (tester) async {
      await tester.pumpWidget(
        _harness(
          DeckBackground(
            image: _bytes,
            opacity: 0.3,
            fit: BackgroundFit.cover,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 0.3);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as MemoryImage).bytes, _bytes);
    });

    testWidgets('maps every fit mode to its BoxFit without throwing', (
      tester,
    ) async {
      for (final fit in BackgroundFit.values) {
        await tester.pumpWidget(
          _harness(DeckBackground(image: _bytes, opacity: 1, fit: fit)),
        );

        expect(tester.takeException(), isNull, reason: 'fit: $fit');
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.fit, boxFitFor(fit), reason: 'fit: $fit');
      }
    });

    testWidgets('clamps an out-of-range opacity instead of throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          DeckBackground(
            image: _bytes,
            opacity: 1.5,
            fit: BackgroundFit.cover,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    });

    testWidgets('clamps a negative opacity instead of throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          DeckBackground(
            image: _bytes,
            opacity: -0.5,
            fit: BackgroundFit.cover,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.0);
    });

    testWidgets(
      'a null image never collapses the body to zero size — regression: '
      'with no background configured, DeckBackground.build() returns a '
      "zero-size SizedBox.shrink(); left un-positioned in buildDeckStack's "
      "Stack, that alone used to shrink the whole deck — body included — "
      'to zero width, with no exception thrown to reveal why. Goes through '
      'buildDeckStack itself, the same function deck_page.dart actually '
      'calls, rather than a hand-copied Stack that could drift from it.',
      (tester) async {
        const stackKey = Key('deck-stack');
        const bodyKey = Key('body-stand-in');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: KeyedSubtree(
                key: stackKey,
                child: buildDeckStack(
                  backgroundImage: null,
                  backgroundOpacity: 1,
                  backgroundFit: BackgroundFit.cover,
                  body: Container(key: bodyKey, color: Colors.blue),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        final stackSize = tester.getSize(find.byKey(stackKey));
        expect(stackSize.width, greaterThan(0));
        expect(stackSize.height, greaterThan(0));
        // The whole point: the body meant to fill the screen actually does,
        // rather than being squeezed to zero by DeckBackground.
        expect(tester.getSize(find.byKey(bodyKey)), stackSize);
      },
    );
  });
}
