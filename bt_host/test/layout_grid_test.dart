import 'package:bt_host/src/layout_page.dart';
import 'package:bt_host/src/protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps a grid and records what it reports back.
  Future<
    ({
      List<(int, int)> moves,
      List<int> picks,
      List<int> clears,
      void Function(DeckLayout) update,
    })
  >
  pumpGrid(WidgetTester tester, DeckLayout initial, {int page = 0}) async {
    final moves = <(int, int)>[];
    final picks = <int>[];
    final clears = <int>[];
    late void Function(DeckLayout) update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              var layout = initial;
              update = (next) => setState(() => layout = next);
              return LayoutGrid(
                layout: layout,
                page: page,
                iconFor: (_) => null,
                onPick: picks.add,
                onClear: clears.add,
                onMove: (from, to) => moves.add((from, to)),
              );
            },
          ),
        ),
      ),
    );

    return (moves: moves, picks: picks, clears: clears, update: update);
  }

  Finder cell(int index) => find.byKey(ValueKey('cell-$index'));

  testWidgets('dragging a button onto another cell reports the move', (
    tester,
  ) async {
    final recorded = await pumpGrid(
      tester,
      DeckLayout.empty().withSlot(0, 'app:Safari'),
    );

    final gesture = await tester.startGesture(tester.getCenter(cell(0)));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(cell(7)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(recorded.moves, [(0, 7)]);
  });

  testWidgets('an empty cell is not draggable', (tester) async {
    final recorded = await pumpGrid(tester, DeckLayout.empty());

    final gesture = await tester.startGesture(tester.getCenter(cell(3)));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(cell(9)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Nothing to pick up, so nothing is reported.
    expect(recorded.moves, isEmpty);
  });

  testWidgets('a cell will not accept a drop from itself', (tester) async {
    final recorded = await pumpGrid(
      tester,
      DeckLayout.empty().withSlot(2, 'app:Safari'),
    );

    final gesture = await tester.startGesture(tester.getCenter(cell(2)));
    await tester.pump(const Duration(milliseconds: 50));
    // Move away and back, so the drag starts but lands where it began.
    await gesture.moveTo(tester.getCenter(cell(8)));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(cell(2)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(recorded.moves, isEmpty);
  });

  testWidgets('tapping a cell asks for its contents', (tester) async {
    final recorded = await pumpGrid(tester, DeckLayout.empty());

    await tester.tap(cell(4));
    await tester.pumpAndSettle();

    expect(recorded.picks, [4]);
  });

  testWidgets('a filled cell offers a clear button, an empty one does not', (
    tester,
  ) async {
    final recorded = await pumpGrid(
      tester,
      DeckLayout.empty().withSlot(1, 'act:mute'),
    );

    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(recorded.clears, [1]);
  });

  testWidgets('only the requested page is shown', (tester) async {
    final layout = DeckLayout.empty(pages: 2)
        .withSlot(0, 'app:FirstPage')
        .withSlot(15, 'app:SecondPage');

    await pumpGrid(tester, layout, page: 1);

    expect(find.text('SecondPage'), findsOneWidget);
    expect(find.text('FirstPage'), findsNothing);
    // Indices stay global, so the second page starts at 15.
    expect(cell(15), findsOneWidget);
    expect(cell(0), findsNothing);
  });
}
