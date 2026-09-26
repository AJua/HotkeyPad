import 'package:hotkeypad_host/src/deck_icons.dart';
import 'package:hotkeypad_host/src/layout_page.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps a grid and records what it reports back.
  Future<
    ({
      List<(int, int)> moves,
      List<int> picks,
      void Function(DeckLayout) update,
    })
  >
  pumpGrid(
    WidgetTester tester,
    DeckLayout initial, {
    int page = 0,
    bool showLabels = true,
  }) async {
    final moves = <(int, int)>[];
    final picks = <int>[];
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
                showLabels: showLabels,
                iconFor: (_) => null,
                onPick: picks.add,
                onMove: (from, to) => moves.add((from, to)),
              );
            },
          ),
        ),
      ),
    );

    return (moves: moves, picks: picks, update: update);
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

  testWidgets('showLabels false hides button labels', (tester) async {
    final layout = DeckLayout.empty().withSlot(0, 'app:Safari');

    await pumpGrid(tester, layout, showLabels: false);

    expect(find.text('Safari'), findsNothing);
  });

  testWidgets('showLabels true shows button labels', (tester) async {
    final layout = DeckLayout.empty().withSlot(0, 'app:Safari');

    await pumpGrid(tester, layout, showLabels: true);

    expect(find.text('Safari'), findsOneWidget);
  });

  testWidgets(
    'a placed widget renders a live preview and hides its covered cells',
    (tester) async {
      final layout = DeckLayout.empty(columns: 5, rows: 3).withWidget(
        1,
        const WidgetItem(
          kind: DeckWidgetKind.clock,
          rowSpan: 2,
          columnSpan: 2,
        ),
      );

      await pumpGrid(tester, layout);

      // The anchor renders the real widget...
      expect(cell(1), findsOneWidget);
      expect(
        find.descendant(of: cell(1), matching: find.byType(AnalogClock)),
        findsOneWidget,
      );
      // ...and every other cell in its footprint isn't built at all, not
      // even as an empty placeholder — there is nothing there to tap.
      expect(cell(2), findsNothing);
      expect(cell(6), findsNothing);
      expect(cell(7), findsNothing);
      // Cells outside the footprint are unaffected.
      expect(cell(0), findsOneWidget);
      expect(cell(3), findsOneWidget);
    },
  );

  testWidgets('tapping anywhere on a widget tile asks to reconfigure it', (
    tester,
  ) async {
    final layout = DeckLayout.empty(columns: 5, rows: 3).withWidget(
      1,
      const WidgetItem(
        kind: DeckWidgetKind.calendar,
        rowSpan: 2,
        columnSpan: 2,
      ),
    );

    final recorded = await pumpGrid(tester, layout);
    await tester.tap(cell(1));
    await tester.pumpAndSettle();

    expect(recorded.picks, [1]);
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

  group('maxWidgetSpanAt', () {
    test('the top-left corner can use the whole grid', () {
      final layout = DeckLayout.empty(columns: 5, rows: 3);

      final span = maxWidgetSpanAt(layout, 0);

      expect(span.rows, 3);
      expect(span.columns, 5);
    });

    test('the bottom-right corner can only be 1x1', () {
      final layout = DeckLayout.empty(columns: 5, rows: 3);

      final span = maxWidgetSpanAt(layout, 14);

      expect(span.rows, 1);
      expect(span.columns, 1);
    });

    test('a mid-grid anchor is bounded by whatever room is left', () {
      final layout = DeckLayout.empty(columns: 5, rows: 3);

      // Row 1, column 3 (index 8): 2 rows and 2 columns remain.
      final span = maxWidgetSpanAt(layout, 8);

      expect(span.rows, 2);
      expect(span.columns, 2);
    });
  });

  group('itemsDroppedByWidget', () {
    const clock = WidgetItem(
      kind: DeckWidgetKind.clock,
      rowSpan: 2,
      columnSpan: 2,
    );

    test('reports the buttons a footprint would clear, anchor excluded', () {
      final layout = DeckLayout.empty(
        columns: 5,
        rows: 3,
      ).withSlot(1, 'app:Anchor').withSlot(2, 'app:Neighbour');

      final dropped = itemsDroppedByWidget(layout, 1, clock);

      expect(dropped, [const AppItem('Neighbour')]);
    });

    test('an empty footprint drops nothing', () {
      final layout = DeckLayout.empty(columns: 5, rows: 3);

      expect(itemsDroppedByWidget(layout, 1, clock), isEmpty);
    });
  });

  group('confirmWidgetOverwrite', () {
    Future<bool?> confirm(
      WidgetTester tester,
      List<DeckItem> dropped, {
      String? tap,
    }) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await confirmWidgetOverwrite(context, dropped);
                },
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      if (tap != null) {
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
      return result;
    }

    testWidgets('names the buttons the widget would cover', (tester) async {
      await confirm(tester, const [AppItem('Safari')]);

      expect(find.text('Remove 1 button?'), findsOneWidget);
    });

    testWidgets('Cancel reports false', (tester) async {
      final result = await confirm(tester, const [
        AppItem('Safari'),
      ], tap: 'Cancel');

      expect(result, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Remove reports true', (tester) async {
      final result = await confirm(tester, const [
        AppItem('Safari'),
      ], tap: 'Remove');

      expect(result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('currentButtonSummary', () {
    test('null for an empty slot', () {
      expect(currentButtonSummary(null), isNull);
    });

    test('null for a value this build cannot parse', () {
      expect(currentButtonSummary(''), isNull);
    });

    test('names the app for an app button', () {
      expect(
        currentButtonSummary(const AppItem('Safari').stored),
        'Opens Safari',
      );
    });

    test('prefixes the action label for a media button', () {
      expect(
        currentButtonSummary(const ActionItem(DeckAction.volumeUp).stored),
        'Action: Volume up',
      );
    });

    test('shows the actual command for a shell button', () {
      const item = ShellItem(command: 'say hello', label: 'Greet');
      expect(currentButtonSummary(item.stored), 'Runs: say hello');
    });

    test('names the interpreter for a non-default shell button', () {
      const item = ShellItem(
        command: r'echo $fish_greeting',
        label: 'Greet',
        shell: ShellKind.fish,
      );
      expect(
        currentButtonSummary(item.stored),
        r'Runs (fish): echo $fish_greeting',
      );
    });

    test('shows the key combination even when a custom label is set', () {
      // A custom label ("Screenshot") is what the button shows; the
      // summary still names the actual keys, since that's what someone
      // reopening the picker wants to check.
      const item = KeyComboItem(
        modifiers: [KeyModifier.command, KeyModifier.shift],
        key: '4',
        special: null,
        label: 'Screenshot',
      );
      expect(currentButtonSummary(item.stored), 'Sends ⌘⇧4');
    });

    test('names the shortcut for a Shortcut button', () {
      const item = ShortcutItem(name: 'Start focus');
      expect(
        currentButtonSummary(item.stored),
        'Runs the "Start focus" Shortcut',
      );
    });

    test('counts the steps for a combo button', () {
      const item = ComboItem(
        steps: [
          ComboStep(action: AppItem('Safari'), delayMs: 0),
          ComboStep(action: AppItem('Chrome'), delayMs: 0),
        ],
        label: 'Browsers',
      );
      expect(currentButtonSummary(item.stored), 'Runs 2 steps');
    });

    test('names the kind and span for a widget button', () {
      const item = WidgetItem(
        kind: DeckWidgetKind.calendar,
        rowSpan: 2,
        columnSpan: 3,
      );
      expect(currentButtonSummary(item.stored), 'Calendar widget (2x3)');
    });
  });

  group('withIconOverride', () {
    test('replaces an app button\'s icon, keeping its name', () {
      const item = AppItem('Safari', emoji: '🧭');

      final updated = withIconOverride(item, customIconId: 'img_1');

      expect(updated, isA<AppItem>());
      expect((updated as AppItem).name, 'Safari');
      expect(updated.emoji, isNull);
      expect(updated.customIconId, 'img_1');
    });

    test('replaces a shell button\'s icon, keeping its command and shell', () {
      const item = ShellItem(
        command: 'say hi',
        label: 'Hi',
        shell: ShellKind.fish,
      );

      final updated =
          withIconOverride(item, customIconId: 'img_2') as ShellItem;

      expect(updated.command, 'say hi');
      expect(updated.label, 'Hi');
      expect(updated.shell, ShellKind.fish);
      expect(updated.customIconId, 'img_2');
    });

    test('replaces a URL button\'s icon, keeping its address', () {
      const item = OpenUrlItem(url: 'https://example.com', label: 'Example');

      final updated =
          withIconOverride(item, customIconId: 'img_3') as OpenUrlItem;

      expect(updated.url, 'https://example.com');
      expect(updated.label, 'Example');
      expect(updated.customIconId, 'img_3');
    });

    test('leaves a widget button unchanged — it has no icon of its own', () {
      const item = WidgetItem(
        kind: DeckWidgetKind.clock,
        rowSpan: 1,
        columnSpan: 1,
      );

      expect(withIconOverride(item, customIconId: 'img_4'), item);
    });
  });

  group('displayEditToCanonical', () {
    test('does nothing when the display was not actually transposed', () {
      final layout = DeckLayout.empty().withSlot(3, 'app:X');

      expect(
        identical(
          displayEditToCanonical(layout, wasTransposed: false),
          layout,
        ),
        isTrue,
      );
    });

    test('a pick through a transposed display lands on the right canonical '
        'slot', () {
      // 5 wide x 3 tall (landscape) with one button at index 7.
      final canonical = DeckLayout.empty().withSlot(7, 'app:Original');
      final canonicalId = canonical.slots[7]!.id;

      // Turned for a portrait phone: 3 wide x 5 tall. The button keeps its
      // id but moves to a different array position.
      final display = canonical.orientedFor(portrait: true);
      final displayIndex = display.slots.indexWhere(
        (slot) => slot?.id == canonicalId,
      );

      final edited = display.withSlot(displayIndex, 'app:Edited');
      final result = displayEditToCanonical(edited, wasTransposed: true);

      expect(result.columns, canonical.columns);
      expect(result.rows, canonical.rows);
      expect(result.slots[7]?.value, 'app:Edited');
      expect(result.slots[7]?.id, canonicalId);
    });

    test('a clear through a transposed display clears the right canonical '
        'slot', () {
      final canonical = DeckLayout.empty().withSlot(7, 'app:Original');
      final canonicalId = canonical.slots[7]!.id;
      final display = canonical.orientedFor(portrait: true);
      final displayIndex = display.slots.indexWhere(
        (slot) => slot?.id == canonicalId,
      );

      final edited = display.withSlot(displayIndex, null);
      final result = displayEditToCanonical(edited, wasTransposed: true);

      expect(result.slots[7], isNull);
    });

    test('a move through a transposed display moves the right canonical '
        'slots', () {
      final canonical = DeckLayout.empty()
          .withSlot(0, 'app:A')
          .withSlot(7, 'app:B');
      final idA = canonical.slots[0]!.id;
      final idB = canonical.slots[7]!.id;
      final display = canonical.orientedFor(portrait: true);
      final displayIndexA = display.slots.indexWhere(
        (slot) => slot?.id == idA,
      );
      final displayIndexB = display.slots.indexWhere(
        (slot) => slot?.id == idB,
      );

      final edited = display.moved(displayIndexA, displayIndexB);
      final result = displayEditToCanonical(edited, wasTransposed: true);

      // moved() swaps the two cells.
      expect(result.slots[0]?.value, 'app:B');
      expect(result.slots[7]?.value, 'app:A');
    });
  });

  group('confirmResizeDrop', () {
    /// Opens the dialog and, if [tap] is given, taps that action's button.
    /// Returns whatever confirmResizeDrop resolved to — null while the
    /// dialog is still open, i.e. when [tap] is left out.
    Future<bool?> confirm(
      WidgetTester tester,
      List<DeckItem> dropped, {
      String? tap,
    }) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await confirmResizeDrop(context, dropped);
                },
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      if (tap != null) {
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
      return result;
    }

    testWidgets('names the buttons that would be removed', (tester) async {
      await confirm(tester, const [AppItem('Safari'), AppItem('Chrome')]);

      expect(find.text('Remove 2 buttons?'), findsOneWidget);
      expect(
        find.text(
          'Shrinking the grid no longer has room for Safari, Chrome. '
          'This cannot be undone.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('uses singular wording for exactly one button', (tester) async {
      await confirm(tester, const [AppItem('Safari')]);

      expect(find.text('Remove 1 button?'), findsOneWidget);
    });

    testWidgets('Cancel reports false', (tester) async {
      final result = await confirm(tester, const [
        AppItem('Safari'),
      ], tap: 'Cancel');

      expect(result, isFalse);
      // And the dialog is actually gone, not just reporting false while
      // still open.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Remove reports true', (tester) async {
      final result = await confirm(tester, const [
        AppItem('Safari'),
      ], tap: 'Remove');

      expect(result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('confirmImportOverwrite', () {
    /// Opens the dialog and, if [tap] is given, taps that action's button.
    /// Returns whatever confirmImportOverwrite resolved to — null while the
    /// dialog is still open, i.e. when [tap] is left out.
    Future<bool?> confirm(WidgetTester tester, {String? tap}) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await confirmImportOverwrite(context);
                },
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      if (tap != null) {
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
      return result;
    }

    testWidgets('names the destructive action clearly', (tester) async {
      await confirm(tester);

      expect(find.text('Replace current settings?'), findsOneWidget);
      expect(
        find.text(
          'Importing replaces the current appearance, deck layout, and '
          'custom icons with what is in the chosen file. This cannot be '
          'undone.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Cancel reports false', (tester) async {
      final result = await confirm(tester, tap: 'Cancel');

      expect(result, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Replace reports true', (tester) async {
      final result = await confirm(tester, tap: 'Replace');

      expect(result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('ComboDialog', () {
    const apps = [
      (name: 'Safari', category: 'Apps', path: '/Applications/Safari.app'),
      (name: 'Chrome', category: 'Apps', path: '/Applications/Chrome.app'),
    ];

    Future<ComboItem?> pumpAndSave(
      WidgetTester tester, {
      ComboItem? existing,
      required Future<void> Function() interact,
    }) async {
      ComboItem? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<ComboItem>(
                    context: context,
                    builder: (context) => ComboDialog(
                      apps: apps,
                      shortcuts: const [],
                      existing: existing,
                      customIconId: null,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await interact();
      return result;
    }

    /// Adds one app step through the reused picker.
    Future<void> addAppStep(WidgetTester tester, String appName) async {
      await tester.tap(find.text('Add step...'));
      await tester.pumpAndSettle();
      // The picker's Applications section is below several fixed items
      // (Command, Media controls), so it is off the fixed-height dialog's
      // initial viewport — scroll its list until the app is actually built.
      await tester.scrollUntilVisible(
        find.text(appName),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(appName));
      await tester.pumpAndSettle();
    }

    testWidgets('Save is disabled with fewer than two steps', (tester) async {
      await pumpAndSave(
        tester,
        interact: () async {
          expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
          final button = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save'),
          );
          expect(button.onPressed, isNull);

          await addAppStep(tester, 'Safari');

          final afterOneStep = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save'),
          );
          expect(afterOneStep.onPressed, isNull);
        },
      );
    });

    testWidgets("the step picker hides 'Button combo...'", (tester) async {
      await pumpAndSave(
        tester,
        interact: () async {
          await tester.tap(find.text('Add step...'));
          await tester.pumpAndSettle();

          expect(find.text('Button combo...'), findsNothing);
          // Same reason: a combo step picks an action to run, and a
          // Clock/Calendar widget isn't one.
          expect(find.text('Clock...'), findsNothing);
          expect(find.text('Shell command...'), findsOneWidget);
        },
      );
    });

    testWidgets('adding two steps and a label enables Save and saves them '
        'in order', (tester) async {
      final result = await pumpAndSave(
        tester,
        interact: () async {
          await addAppStep(tester, 'Safari');
          await addAppStep(tester, 'Chrome');
          await tester.enterText(
            find.widgetWithText(TextField, 'Button label'),
            'Two browsers',
          );
          // Lets the label field's onChanged setState (which is what turns
          // Save enabled) actually take effect before tapping it.
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await tester.pumpAndSettle();
        },
      );

      expect(result, isNotNull);
      expect(result!.label, 'Two browsers');
      expect(result.steps.map((s) => s.action), [
        const AppItem('Safari'),
        const AppItem('Chrome'),
      ]);
    });

    testWidgets('removing a step drops it from the list', (tester) async {
      final result = await pumpAndSave(
        tester,
        interact: () async {
          await addAppStep(tester, 'Safari');
          await addAppStep(tester, 'Chrome');
          // Both steps' remove buttons look the same; take the first one.
          await tester.tap(find.byTooltip('Remove').first);
          await tester.pumpAndSettle();
          await addAppStep(tester, 'Safari');
          await tester.enterText(
            find.widgetWithText(TextField, 'Button label'),
            'Chrome then Safari',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await tester.pumpAndSettle();
        },
      );

      expect(result!.steps.map((s) => s.action), [
        const AppItem('Chrome'),
        const AppItem('Safari'),
      ]);
    });

    testWidgets('moving a step down reorders it', (tester) async {
      final result = await pumpAndSave(
        tester,
        interact: () async {
          await addAppStep(tester, 'Safari');
          await addAppStep(tester, 'Chrome');
          // Move step 1 (Safari) down past step 2 (Chrome).
          await tester.tap(find.byTooltip('Move down').first);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Button label'),
            'Reordered',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await tester.pumpAndSettle();
        },
      );

      expect(result!.steps.map((s) => s.action), [
        const AppItem('Chrome'),
        const AppItem('Safari'),
      ]);
    });

    testWidgets('a new step defaults to a 500ms delay', (tester) async {
      final result = await pumpAndSave(
        tester,
        interact: () async {
          await addAppStep(tester, 'Safari');
          await addAppStep(tester, 'Chrome');
          // The second step's delay defaults to 500ms.
          expect(find.text('500ms'), findsOneWidget);
          // Tapping the text itself does nothing (only the +/- buttons do).
          await tester.tap(find.text('500ms'));
          await tester.pumpAndSettle();
        },
      );

      expect(result, isNull);
    });

    testWidgets("the delay stepper adjusts a step's delay", (tester) async {
      final adjusted = await pumpAndSave(
        tester,
        interact: () async {
          await addAppStep(tester, 'Safari');
          await addAppStep(tester, 'Chrome');
          final plusButtons = find.byIcon(Icons.add_circle_outline);
          // The first belongs to step 1's stepper, the second to step 2's.
          await tester.tap(plusButtons.last);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Button label'),
            'Delayed',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await tester.pumpAndSettle();
        },
      );

      expect(adjusted!.steps[1].delayMs, 750);
    });

    testWidgets('editing an existing combo prefills its steps and label', (
      tester,
    ) async {
      const existing = ComboItem(
        steps: [
          ComboStep(action: AppItem('Safari'), delayMs: 0),
          ComboStep(action: AppItem('Chrome'), delayMs: 500),
        ],
        label: 'Existing combo',
      );

      await pumpAndSave(
        tester,
        existing: existing,
        interact: () async {
          final labelField = tester.widget<TextField>(
            find.widgetWithText(TextField, 'Button label'),
          );
          expect(labelField.controller!.text, 'Existing combo');
          expect(find.text('Opens Safari'), findsOneWidget);
          expect(find.text('Opens Chrome'), findsOneWidget);
        },
      );
    });
  });
}
