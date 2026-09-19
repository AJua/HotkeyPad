import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkeypad_client/src/edge_bar.dart';

void main() {
  group('EdgeBarScaffold', () {
    Future<void> pump(
      WidgetTester tester, {
      required Size size,
      String? subtitle,
    }) async {
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: EdgeBarScaffold(
            title: 'HotkeyPad',
            subtitle: subtitle,
            actions: const [Icon(Icons.settings)],
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    testWidgets(
      'portrait shows the bar, title included, same as an ordinary app bar',
      (tester) async {
        await pump(tester, size: const Size(1170, 2532));

        expect(tester.takeException(), isNull);
        expect(find.text('HotkeyPad'), findsOneWidget);
        expect(find.byIcon(Icons.settings), findsOneWidget);
      },
    );

    testWidgets('landscape hides the bar entirely — matching YouTube\'s own '
        'landscape-fullscreen convention (see main.dart\'s hideSystemBars, '
        'which hides the system bars the same way on the same rotation) — '
        'handing the deck the whole screen rather than a shorter version '
        'of the same bar', (tester) async {
      await pump(tester, size: const Size(2532, 1170));

      expect(tester.takeException(), isNull);
      expect(find.text('HotkeyPad'), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('portrait: shows the subtitle when given one', (tester) async {
      await pump(
        tester,
        size: const Size(1170, 2532),
        subtitle: 'linjianongdeMBP',
      );

      expect(tester.takeException(), isNull);
      expect(find.text('linjianongdeMBP'), findsOneWidget);
    });

    testWidgets(
      'portrait: the bar sits above the content rather than overlaying it',
      (tester) async {
        const bodyKey = Key('body-stand-in');
        tester.view.physicalSize = const Size(1170, 2532);
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: EdgeBarScaffold(
              title: 'HotkeyPad',
              actions: const [],
              child: SizedBox.expand(key: bodyKey),
            ),
          ),
        );

        final titleBottom = tester.getBottomLeft(find.text('HotkeyPad')).dy;
        final bodyTop = tester.getTopLeft(find.byKey(bodyKey)).dy;
        expect(bodyTop, greaterThanOrEqualTo(titleBottom));
      },
    );

    testWidgets('landscape: content still avoids a notch on either side even '
        'though the (now-hidden) bar no longer claims any inset for it', (
      tester,
    ) async {
      for (final padding in [
        const FakeViewPadding(left: 59, bottom: 21),
        const FakeViewPadding(right: 59, bottom: 21),
      ]) {
        tester.view.physicalSize = const Size(2532, 1170);
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.viewPadding = padding;
        addTearDown(tester.view.resetViewPadding);

        const bodyKey = Key('body-stand-in');
        await tester.pumpWidget(
          MaterialApp(
            home: EdgeBarScaffold(
              title: 'HotkeyPad',
              actions: const [],
              child: Container(key: bodyKey, color: Colors.blue),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'landscape: content reaches flush to the top and bottom edges — '
      'regression: wrapping it in a SafeArea reserved room for the home '
      "indicator's software gesture-area convention even with the bar "
      'gone, which is not actually edge to edge — a real device showed a '
      'visible gap at the bottom with no hardware reason to be there. '
      'MediaQuery.padding is what SafeArea reads and what is safe to '
      'ignore here; viewPadding (a real notch/cutout, 0 on every side in '
      'this case) is the one this still has to respect.',
      (tester) async {
        tester.view.physicalSize = const Size(2532, 1170);
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);
        // padding (the home indicator's software convention) has a
        // bottom inset; viewPadding (the actual hardware shape) does
        // not — the real-world case this distinction exists for.
        tester.view.padding = const FakeViewPadding(bottom: 21);
        addTearDown(tester.view.resetPadding);

        const bodyKey = Key('body-stand-in');
        await tester.pumpWidget(
          MaterialApp(
            home: EdgeBarScaffold(
              title: 'HotkeyPad',
              actions: const [],
              child: SizedBox.expand(key: bodyKey),
            ),
          ),
        );

        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(tester.getSize(find.byKey(bodyKey)).height, screenHeight);
      },
    );

    testWidgets(
      'landscape: MediaQuery.paddingOf reads zero further down the tree, '
      'not just SizedBox.expand filling the outer Padding — regression: '
      'the deck grid centers itself using its own margin math '
      '(safeScrollPadding, deck_page.dart) that adds MediaQuery.paddingOf\'s '
      "bottom inset on top of a flat margin but not the top's, so if this "
      "ambient value weren't also zeroed here (not just wrapped in this "
      "widget's own Padding), the grid ended up centered in a shorter box "
      'than the screen actually is — off-centre, not merely inset',
      (tester) async {
        tester.view.physicalSize = const Size(2532, 1170);
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.padding = const FakeViewPadding(bottom: 21);
        addTearDown(tester.view.resetPadding);

        late EdgeInsets seenPadding;
        await tester.pumpWidget(
          MaterialApp(
            home: EdgeBarScaffold(
              title: 'HotkeyPad',
              actions: const [],
              child: Builder(
                builder: (context) {
                  seenPadding = MediaQuery.paddingOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(seenPadding, EdgeInsets.zero);
      },
    );

    testWidgets(
      'landscape: a bottom-only viewPadding (the home indicator, which — '
      "unlike the rest of the software safe-area convention — turns out "
      'to claim real space even by that measure on real iOS hardware) '
      'gets mirrored onto the top too, so the deck lands dead centre '
      "instead of pulled toward whichever edge doesn't have one",
      (tester) async {
        tester.view.physicalSize = const Size(2532, 1170);
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.viewPadding = const FakeViewPadding(bottom: 21);
        addTearDown(tester.view.resetViewPadding);

        const bodyKey = Key('body-stand-in');
        await tester.pumpWidget(
          MaterialApp(
            home: EdgeBarScaffold(
              title: 'HotkeyPad',
              actions: const [],
              child: SizedBox.expand(key: bodyKey),
            ),
          ),
        );

        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final bodyRect = tester.getRect(find.byKey(bodyKey));
        expect(bodyRect.top, 21);
        expect(screenHeight - bodyRect.bottom, 21);
      },
    );
  });
}
