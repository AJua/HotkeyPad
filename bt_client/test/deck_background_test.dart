import 'dart:convert';

import 'package:bt_client/src/background_fit.dart';
import 'package:bt_client/src/deck_page.dart';
import 'package:bt_link_protocol/bt_link_protocol.dart';
import 'package:flutter/material.dart'
    show Image, MaterialApp, MemoryImage, Opacity, Scaffold, Stack, Widget;
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

/// [DeckBackground] renders itself as a [Positioned], which is only valid
/// directly inside a [Stack] — exactly how deck_page.dart actually places
/// it, and how every test here must too.
Widget _harness(Widget background) =>
    MaterialApp(home: Scaffold(body: Stack(children: [background])));

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
  });
}
