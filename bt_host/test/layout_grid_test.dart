import 'package:bt_host/src/layout_page.dart';
import 'package:bt_link_protocol/bt_link_protocol.dart';
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
    final layout = DeckLayout.empty(
      pages: 2,
    ).withSlot(0, 'app:FirstPage').withSlot(15, 'app:SecondPage');

    await pumpGrid(tester, layout, page: 1);

    expect(find.text('SecondPage'), findsOneWidget);
    expect(find.text('FirstPage'), findsNothing);
    // Indices stay global, so the second page starts at 15.
    expect(cell(15), findsOneWidget);
    expect(cell(0), findsNothing);
  });

  group('itemsDroppedByResize', () {
    test('growing never drops anything', () {
      final layout = DeckLayout.empty().withSlot(14, 'app:Last');

      expect(itemsDroppedByResize(layout, columns: 6), isEmpty);
      expect(itemsDroppedByResize(layout, rows: 4), isEmpty);
      expect(itemsDroppedByResize(layout, pages: 2), isEmpty);
    });

    test('reports exactly what shrinking columns would drop', () {
      // Default 5x3: column 4 (the last one) holds a button on every row.
      final layout = DeckLayout.empty()
          .withSlot(4, 'app:TopRight')
          .withSlot(9, 'act:mute')
          .withSlot(14, 'app:BottomRight')
          .withSlot(0, 'app:Kept');

      final dropped = itemsDroppedByResize(layout, columns: 4);

      expect(dropped, [
        const AppItem('TopRight'),
        const ActionItem(DeckAction.mute),
        const AppItem('BottomRight'),
      ]);
    });

    test('reports exactly what shrinking rows would drop', () {
      final layout = DeckLayout.empty()
          .withSlot(0, 'app:Kept')
          .withSlot(10, 'app:BottomLeft');

      expect(itemsDroppedByResize(layout, rows: 2), [
        const AppItem('BottomLeft'),
      ]);
    });

    test('reports exactly what shrinking pages would drop', () {
      final layout = DeckLayout.empty(
        pages: 2,
      ).withSlot(0, 'app:FirstPage').withSlot(15, 'app:SecondPage');

      expect(itemsDroppedByResize(layout, pages: 1), [
        const AppItem('SecondPage'),
      ]);
    });

    test('skips empty cells outside the new bounds', () {
      final layout = DeckLayout.empty().withSlot(0, 'app:Kept');

      expect(itemsDroppedByResize(layout, columns: 1), isEmpty);
    });

    test('agrees with what resized() actually removes', () {
      final layout = DeckLayout.empty(
        pages: 2,
      ).withSlot(4, 'app:A').withSlot(9, 'app:B').withSlot(20, 'app:C');

      for (final shape in [
        (columns: 3, rows: 3, pages: 2),
        (columns: 5, rows: 2, pages: 2),
        (columns: 5, rows: 3, pages: 1),
      ]) {
        final dropped = itemsDroppedByResize(
          layout,
          columns: shape.columns,
          rows: shape.rows,
          pages: shape.pages,
        );
        final resized = layout.resized(
          columns: shape.columns,
          rows: shape.rows,
          pages: shape.pages,
        );
        final kept = resized.slots.whereType<DeckSlot>().length;
        final before = layout.slots.whereType<DeckSlot>().length;

        expect(dropped.length, before - kept, reason: 'shape $shape');
      }
    });
  });
}
