import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hotkeypad_client/src/deck_page.dart';

/// Recomputes the grid height a `squareCardSizeFor` answer would actually
/// produce, the same way `_deck`'s own layout math would — the real
/// correctness property, since a self-inconsistent answer is exactly the
/// bug this function exists to avoid (see its own doc comment).
double _gridHeightFor(
  double cardSize, {
  required double freeHeight,
  required double widthBudget,
  required int rows,
  required int columns,
  required double cellRatio,
  required int shownCount,
  required double spacing,
}) {
  final availWidth = widthBudget - shownCount * cardSize;
  final freeWidth = availWidth;
  final cellWidth = math.min(
    freeWidth / columns,
    freeHeight / rows * cellRatio,
  );
  final cellHeight = cellWidth / cellRatio;
  return cellHeight * rows + spacing * (rows - 1);
}

void main() {
  group('squareCardSizeFor', () {
    test('height-bound: a generous width just returns freeHeight', () {
      final size = squareCardSizeFor(
        freeHeight: 400,
        widthBudget: 2000,
        rows: 2,
        columns: 3,
        cellRatio: 0.86,
        shownCount: 1,
        spacing: 2,
      );
      expect(size, 400);
    });

    test(
      'width-bound (the 5-column deck this was found on): the answer is '
      'consistent with the grid height it implies',
      () {
        const params = (
          freeHeight: 600.0,
          widthBudget: 1200.0,
          rows: 3,
          columns: 5,
          cellRatio: 0.86,
          shownCount: 1,
          spacing: 2.0,
        );
        final size = squareCardSizeFor(
          freeHeight: params.freeHeight,
          widthBudget: params.widthBudget,
          rows: params.rows,
          columns: params.columns,
          cellRatio: params.cellRatio,
          shownCount: params.shownCount,
          spacing: params.spacing,
        );

        // Narrower than plain freeHeight — the bug this replaces would
        // have used freeHeight directly, taller than the grid it sat
        // beside actually rendered.
        expect(size, lessThan(params.freeHeight));

        final impliedGridHeight = _gridHeightFor(
          size,
          freeHeight: params.freeHeight,
          widthBudget: params.widthBudget,
          rows: params.rows,
          columns: params.columns,
          cellRatio: params.cellRatio,
          shownCount: params.shownCount,
          spacing: params.spacing,
        );
        expect(impliedGridHeight, closeTo(size, 0.001));
      },
    );

    test('width-bound with both clock and calendar shown', () {
      const params = (
        freeHeight: 600.0,
        widthBudget: 900.0,
        rows: 3,
        columns: 6,
        cellRatio: 1.0,
        shownCount: 2,
        spacing: 2.0,
      );
      final size = squareCardSizeFor(
        freeHeight: params.freeHeight,
        widthBudget: params.widthBudget,
        rows: params.rows,
        columns: params.columns,
        cellRatio: params.cellRatio,
        shownCount: params.shownCount,
        spacing: params.spacing,
      );

      expect(size, lessThan(params.freeHeight));
      final impliedGridHeight = _gridHeightFor(
        size,
        freeHeight: params.freeHeight,
        widthBudget: params.widthBudget,
        rows: params.rows,
        columns: params.columns,
        cellRatio: params.cellRatio,
        shownCount: params.shownCount,
        spacing: params.spacing,
      );
      expect(impliedGridHeight, closeTo(size, 0.001));
    });
  });
}
