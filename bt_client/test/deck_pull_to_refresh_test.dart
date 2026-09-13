import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wrapper `_body` puts around the deck (deck_page.dart) so pulling down
/// can retry a stuck icon, reproduced here without any of the session/BLE
/// plumbing — just the widget shape, which is what actually broke.
Widget pullToRefreshWrapper({required WidgetBuilder deckBuilder}) {
  return LayoutBuilder(
    builder: (context, outer) {
      return RefreshIndicator(
        onRefresh: () async {},
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: outer.maxHeight, child: deckBuilder(context)),
        ),
      );
    },
  );
}

void main() {
  testWidgets('wrapping a LayoutBuilder-based deck in the pull-to-refresh shell '
      'lays out without throwing', (tester) async {
    // The deck itself (_deck in deck_page.dart) is a LayoutBuilder reading
    // its own constraints to size cells. A Sliver-based wrapper
    // (SliverFillRemaining) can query a child's *intrinsic* height in some
    // constraint shapes, and LayoutBuilder throws rather than answer that
    // — a real crash this test reproduces and the fix (a SingleChildScrollView-based
    // wrapper instead) avoids, since SingleChildScrollView never asks.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: pullToRefreshWrapper(
            deckBuilder: (context) => LayoutBuilder(
              builder: (context, constraints) => Center(
                child: Text('deck ${constraints.maxWidth.toStringAsFixed(0)}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('deck'), findsOneWidget);
  });

  testWidgets('pulling down still triggers the refresh callback', (
    tester,
  ) async {
    var refreshed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, outer) => RefreshIndicator(
              onRefresh: () async => refreshed = true,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: outer.maxHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) => const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(refreshed, isTrue);
  });
}
