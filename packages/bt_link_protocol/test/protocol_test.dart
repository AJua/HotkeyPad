import 'dart:convert';

import 'package:bt_link_protocol/bt_link_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IconFrame', () {
    test('round-trips a frame', () {
      final payload = List<int>.generate(200, (i) => i % 256);

      final encoded = IconFrame.encode(
        name: 'Safari',
        index: 3,
        total: 12,
        payload: payload,
      );
      final decoded = IconFrame.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.name, 'Safari');
      expect(decoded.index, 3);
      expect(decoded.total, 12);
      expect(decoded.payload, payload);
    });

    test('handles a non-ASCII app name', () {
      // macOS ships apps with CJK names; nameLength is bytes, not characters.
      const name = '系統設定';

      final decoded = IconFrame.decode(
        IconFrame.encode(name: name, index: 0, total: 1, payload: [1, 2, 3]),
      );

      expect(decoded!.name, name);
      expect(decoded.payload, [1, 2, 3]);
    });

    test('survives an index and total above one byte', () {
      final decoded = IconFrame.decode(
        IconFrame.encode(name: 'A', index: 300, total: 400, payload: const []),
      );

      expect(decoded!.index, 300);
      expect(decoded.total, 400);
    });

    test('rejects a truncated frame', () {
      final encoded = IconFrame.encode(
        name: 'Safari',
        index: 0,
        total: 1,
        payload: [9, 9, 9],
      );

      for (var length = 1; length < IconFrame.headerSize('Safari'); length++) {
        expect(
          IconFrame.decode(encoded.sublist(0, length)),
          isNull,
          reason: 'a $length-byte frame must not decode',
        );
      }
    });

    test('rejects a nonsensical index', () {
      expect(
        IconFrame.decode(
          IconFrame.encode(name: 'A', index: 5, total: 5, payload: const []),
        ),
        isNull,
      );
    });

    test('does not mistake a JSON message for a frame', () {
      final json = utf8.encode(jsonEncode(const PressSlot(id: 3)));

      expect(IconFrame.looksLikeFrame(json), isFalse);
      expect(IconFrame.decode(json), isNull);
    });

    test('a frame is not mistaken for a JSON message', () {
      final frame = IconFrame.encode(
        name: 'Safari',
        index: 0,
        total: 1,
        payload: [1, 2, 3],
      );

      expect(BtMessage.decode(frame), isNull);
    });

    test('payload capacity leaves room for the header', () {
      const name = 'Safari';
      final capacity = IconFrame.payloadCapacity(185, name);

      final frame = IconFrame.encode(
        name: name,
        index: 0,
        total: 1,
        payload: List.filled(capacity, 0),
      );

      expect(frame.length, 185);
    });
  });

  group('BtMessage', () {
    test('round-trips every message shape', () {
      const messages = <BtMessage>[
        Hello(name: 'Pixel 7'),
        ListApps(),
        AppEntry(name: 'Safari', category: 'Apps'),
        ListEnd(count: 96),
        PressSlot(id: 3),
        RequestIcon(name: 'Safari'),
        IconUnavailable(name: 'Safari'),
        Ack(ok: true, message: 'Opened Safari'),
        DebugText(text: 'hello'),
      ];

      for (final message in messages) {
        final decoded = BtMessage.decode(message.encode());
        expect(decoded.runtimeType, message.runtimeType);
        expect(decoded!.toJson(), message.toJson());
      }
    });

    test('returns null for an unknown message type', () {
      expect(BtMessage.decode(utf8.encode('{"t":"from-the-future"}')), isNull);
    });

    test('returns null for malformed input', () {
      expect(BtMessage.decode(utf8.encode('not json')), isNull);
      expect(BtMessage.decode(const [0xff, 0xfe]), isNull);
    });

    test('Hello defaults to an empty name rather than crashing', () {
      final decoded = BtMessage.decode(utf8.encode('{"t":"hi"}'));
      expect(decoded, isA<Hello>());
      expect((decoded as Hello).name, '');
    });
  });

  group('DeckItem', () {
    test('round-trips both kinds', () {
      for (final item in const [
        AppItem('Safari'),
        ActionItem(DeckAction.playPause),
      ]) {
        expect(DeckItem.parse(item.stored), item);
      }
    });

    test('reads a bare app name saved by an older build', () {
      expect(DeckItem.parse('Safari'), const AppItem('Safari'));
    });

    test('skips an item this build does not know', () {
      expect(DeckItem.parse('act:teleport'), isNull);
      expect(DeckItem.parse(''), isNull);
    });

    test('round-trips a shell command', () {
      const item = ShellItem(command: 'say hello', label: 'Greet', emoji: '👋');

      final parsed = DeckItem.parse(item.stored) as ShellItem?;

      expect(parsed!.command, 'say hello');
      expect(parsed.label, 'Greet');
      expect(parsed.emoji, '👋');
    });

    test('a command containing punctuation survives', () {
      // The old colon-prefixed format would have split this apart.
      const command = r'''osascript -e 'display notification "a: b"' ''';
      const item = ShellItem(command: command, label: 'Notify');

      expect((DeckItem.parse(item.stored) as ShellItem).command, command);
    });

    test('round-trips a shortcut, falling back to its name', () {
      const named = ShortcutItem(name: 'Start focus', label: 'Focus');
      const bare = ShortcutItem(name: 'Start focus');

      expect((DeckItem.parse(named.stored) as ShortcutItem).label, 'Focus');
      expect(
        (DeckItem.parse(bare.stored) as ShortcutItem).label,
        'Start focus',
      );
    });

    test('an emoji survives on an app or an action', () {
      const app = AppItem('Safari', emoji: '🧭');
      const action = ActionItem(DeckAction.mute, emoji: '🔇');

      expect(DeckItem.parse(app.stored)!.emoji, '🧭');
      expect(DeckItem.parse(action.stored)!.emoji, '🔇');
    });

    test('an item without an emoji keeps the short legacy form', () {
      // Readable in the layout file, and loadable by an older build.
      expect(const AppItem('Safari').stored, 'app:Safari');
      expect(const ActionItem(DeckAction.mute).stored, 'act:mute');
    });

    test('a custom icon id survives on any item kind', () {
      for (final item in const [
        AppItem('Safari', customIconId: 'img_1'),
        ActionItem(DeckAction.mute, customIconId: 'img_2'),
        ShellItem(command: 'say hi', label: 'Hi', customIconId: 'img_3'),
        ShortcutItem(name: 'Start focus', customIconId: 'img_4'),
        KeyComboItem(
          modifiers: [],
          key: '4',
          special: null,
          customIconId: 'img_5',
        ),
      ]) {
        expect(DeckItem.parse(item.stored)!.customIconId, item.customIconId);
      }
    });

    test('a custom icon id forces the long JSON form', () {
      // Same reason an emoji does: the short form has nowhere to put it.
      expect(
        const AppItem('Safari', customIconId: 'img_1').stored,
        isNot('app:Safari'),
      );
      expect(
        DeckItem.parse('{"t":"app","n":"Safari","ci":"img_1"}'),
        const AppItem('Safari', customIconId: 'img_1'),
      );
    });

    test('emoji and a custom icon id can be set independently', () {
      const bothUnset = AppItem('Safari');
      const emojiOnly = AppItem('Safari', emoji: '🧭');
      const imageOnly = AppItem('Safari', customIconId: 'img_1');

      expect(bothUnset.emoji, isNull);
      expect(bothUnset.customIconId, isNull);
      expect(emojiOnly.customIconId, isNull);
      expect(imageOnly.emoji, isNull);
    });

    test('round-trips a key combination', () {
      const item = KeyComboItem(
        modifiers: [KeyModifier.command, KeyModifier.shift],
        key: '4',
        special: null,
        label: 'Screenshot',
        emoji: '📸',
      );

      final parsed = DeckItem.parse(item.stored) as KeyComboItem?;

      expect(parsed!.modifiers, [KeyModifier.command, KeyModifier.shift]);
      expect(parsed.key, '4');
      expect(parsed.special, isNull);
      expect(parsed.label, 'Screenshot');
      expect(parsed.emoji, '📸');
    });

    test('round-trips a special key', () {
      const item = KeyComboItem(
        modifiers: [KeyModifier.option],
        key: null,
        special: SpecialKey.space,
      );

      final parsed = DeckItem.parse(item.stored) as KeyComboItem?;

      expect(parsed!.special, SpecialKey.space);
      expect(parsed.key, isNull);
    });

    test('reads as symbols, and labels itself when unnamed', () {
      const combo = KeyComboItem(
        modifiers: [KeyModifier.command, KeyModifier.shift],
        key: '4',
        special: null,
      );

      expect(combo.combination, '⌘⇧4');
      // No label given, so the combination is the label.
      expect(combo.label, '⌘⇧4');
      expect(
        const KeyComboItem(
          modifiers: [KeyModifier.option],
          key: null,
          special: SpecialKey.space,
        ).combination,
        '⌥Space',
      );
    });

    test('an unknown modifier is dropped, not fatal', () {
      final parsed =
          DeckItem.parse('{"t":"key","m":["cmd","hyper"],"k":"c"}')
              as KeyComboItem?;

      expect(parsed!.modifiers, [KeyModifier.command]);
    });

    test('an app and an action never collide', () {
      expect(
        const AppItem('playpause').stored,
        isNot(const ActionItem(DeckAction.playPause).stored),
      );
    });
  });

  group('ComboItem', () {
    test('round-trips its steps and delays', () {
      const combo = ComboItem(
        steps: [
          ComboStep(action: ActionItem(DeckAction.mute), delayMs: 0),
          ComboStep(action: AppItem('Safari'), delayMs: 500),
        ],
        label: 'Mute then Safari',
      );

      final decoded = DeckItem.parse(combo.stored) as ComboItem?;

      expect(decoded!.label, 'Mute then Safari');
      expect(decoded.steps, hasLength(2));
      expect(decoded.steps[0].action, const ActionItem(DeckAction.mute));
      expect(decoded.steps[0].delayMs, 0);
      expect(decoded.steps[1].action, const AppItem('Safari'));
      expect(decoded.steps[1].delayMs, 500);
    });

    test('always uses the long JSON form, even with two plain app steps', () {
      const combo = ComboItem(
        steps: [
          ComboStep(action: AppItem('Safari'), delayMs: 0),
          ComboStep(action: AppItem('Chrome'), delayMs: 0),
        ],
        label: 'Both browsers',
      );

      expect(combo.stored, startsWith('{'));
    });

    test('drops a step that fails to parse', () {
      final decoded = DeckItem.parse(
        jsonEncode({
          't': 'combo',
          'l': 'Partly broken',
          'steps': [
            {'v': 'app:Safari', 'd': 0},
            {'v': 12345, 'd': 0}, // not a string: fails to parse
            {'v': 'act:mute', 'd': 100},
          ],
        }),
      );

      expect(decoded, isA<ComboItem>());
      expect((decoded as ComboItem).steps, hasLength(2));
      expect(decoded.steps[0].action, const AppItem('Safari'));
      expect(decoded.steps[1].action, const ActionItem(DeckAction.mute));
    });

    test('drops a step that is itself a combo — combos cannot nest', () {
      const inner = ComboItem(
        steps: [ComboStep(action: AppItem('Safari'), delayMs: 0)],
        label: 'Inner',
      );
      final decoded = DeckItem.parse(
        jsonEncode({
          't': 'combo',
          'l': 'Outer',
          'steps': [
            {'v': inner.stored, 'd': 0},
            {'v': 'act:mute', 'd': 0},
          ],
        }),
      );

      expect(decoded, isA<ComboItem>());
      expect((decoded as ComboItem).steps, hasLength(1));
      expect(decoded.steps.single.action, const ActionItem(DeckAction.mute));
    });

    test('is invalid once dropping bad steps leaves nothing to run', () {
      final decoded = DeckItem.parse(
        jsonEncode({
          't': 'combo',
          'l': 'All broken',
          'steps': [
            {'v': 999, 'd': 0},
          ],
        }),
      );

      expect(decoded, isNull);
    });

    test('a missing steps list is invalid, not a crash', () {
      expect(DeckItem.parse(jsonEncode({'t': 'combo', 'l': 'Empty'})), isNull);
    });

    test('an emoji and a custom icon id survive like any other item', () {
      const combo = ComboItem(
        steps: [
          ComboStep(action: AppItem('Safari'), delayMs: 0),
          ComboStep(action: AppItem('Chrome'), delayMs: 0),
        ],
        label: 'Browsers',
        emoji: '🌐',
      );

      expect(DeckItem.parse(combo.stored)!.emoji, '🌐');
    });
  });

  group('DeckLayout', () {
    test('defaults to one 5x3 page of empty cells', () {
      final layout = DeckLayout.empty();

      expect(layout.columns, 5);
      expect(layout.rows, 3);
      expect(layout.pages, 1);
      expect(layout.pageCapacity, 15);
      expect(layout.capacity, 15);
      expect(layout.slots.every((slot) => slot == null), isTrue);
    });

    test('pages extend the flat slot list', () {
      final layout = DeckLayout.empty(pages: 3);

      expect(layout.capacity, 45);
      expect(layout.pageCapacity, 15);
      expect(layout.indexOf(page: 2, cell: 4), 34);
    });

    test('page() returns just that page', () {
      final layout = DeckLayout.empty(
        pages: 2,
      ).withSlot(0, 'app:First').withSlot(15, 'app:Second');

      expect(layout.page(0).first?.value, 'app:First');
      expect(layout.page(0).length, 15);
      expect(layout.page(1).first?.value, 'app:Second');
    });

    test('moving works across pages', () {
      // A drag from page 0 to page 1 is an ordinary index move.
      final moved = DeckLayout.empty(
        pages: 2,
      ).withSlot(0, 'app:A').moved(0, 20);

      expect(moved.slots[0], isNull);
      expect(moved.slots[20]?.value, 'app:A');
    });

    test('adding a page leaves existing pages untouched', () {
      final layout = DeckLayout.empty().withSlot(14, 'app:Last');

      final grown = layout.resized(pages: 2);

      expect(grown.capacity, 30);
      expect(grown.slots[14]?.value, 'app:Last');
      expect(grown.page(1).every((slot) => slot == null), isTrue);
    });

    test('removing a page drops only that page', () {
      final layout = DeckLayout.empty(
        pages: 2,
      ).withSlot(0, 'app:Keep').withSlot(15, 'app:Drop');

      final shrunk = layout.resized(pages: 1);

      expect(shrunk.slots.any((slot) => slot?.value == 'app:Keep'), isTrue);
      expect(shrunk.slots.any((slot) => slot?.value == 'app:Drop'), isFalse);
    });

    test('reads a layout written before pages existed', () {
      final decoded = DeckLayout.fromJson({
        'columns': 2,
        'rows': 2,
        'slots': <String?>[null, 'app:A', null, null],
      });

      expect(decoded!.pages, 1);
      expect(decoded.slots[1]?.value, 'app:A');
    });

    test('moving swaps the two cells', () {
      final layout = DeckLayout.empty()
          .withSlot(0, 'app:A')
          .withSlot(1, 'app:B');

      final moved = layout.moved(0, 1);

      expect(moved.slots[0]?.value, 'app:B');
      expect(moved.slots[1]?.value, 'app:A');
      // Whichever button ends up at a position takes that position's id —
      // this is a host-side edit, always followed by a full layout resend.
      expect(moved.slots[0]!.id, 0);
      expect(moved.slots[1]!.id, 1);
    });

    test('moving into an empty cell leaves the source empty', () {
      final moved = DeckLayout.empty().withSlot(0, 'app:A').moved(0, 7);

      expect(moved.slots[0], isNull);
      expect(moved.slots[7]?.value, 'app:A');
    });

    test('resizing keeps cells in the same screen position', () {
      // Second row, first column of a 5-wide grid.
      final layout = DeckLayout.empty().withSlot(5, 'app:A');

      final wider = layout.resized(columns: 6);

      // Still second row, first column — index 6 in a 6-wide grid. A naive
      // copy would leave it at index 5, sliding it up a row.
      expect(wider.slots[6]?.value, 'app:A');
      expect(wider.slots[5], isNull);
      // Re-stamped to the new position, same as every other host-side edit.
      expect(wider.slots[6]!.id, 6);
    });

    test('shrinking drops cells that fall outside', () {
      final layout = DeckLayout.empty().withSlot(4, 'app:Edge');

      final narrower = layout.resized(columns: 3);

      expect(narrower.capacity, 9);
      expect(narrower.slots.any((slot) => slot?.value == 'app:Edge'), isFalse);
    });

    test('rejects json that does not describe a grid', () {
      expect(DeckLayout.fromJson(null), isNull);
      expect(DeckLayout.fromJson({'columns': 5, 'rows': 3}), isNull);
      expect(
        DeckLayout.fromJson({'columns': 5, 'rows': 3, 'slots': <String?>[]}),
        isNull,
      );
      expect(
        DeckLayout.fromJson({'columns': 0, 'rows': 3, 'slots': <String?>[]}),
        isNull,
      );
    });

    test('round-trips through json', () {
      final layout = DeckLayout.empty(
        columns: 2,
        rows: 2,
      ).withSlot(3, 'act:mute');

      final decoded = DeckLayout.fromJson(layout.toJson());

      expect(decoded!.slots, layout.slots);
      expect(decoded.columns, 2);
    });
  });

  group('PressSlot', () {
    test('round-trips', () {
      final decoded =
          BtMessage.decode(const PressSlot(id: 12).encode()) as PressSlot?;

      expect(decoded!.id, 12);
    });
  });

  group('layout messages', () {
    test('round-trip', () {
      const messages = <BtMessage>[
        RequestLayout(),
        LayoutStart(columns: 5, rows: 3, pages: 2),
        LayoutSlot(index: 7, value: 'app:Safari'),
        LayoutEnd(),
      ];

      for (final message in messages) {
        final decoded = BtMessage.decode(message.encode());
        expect(decoded.runtimeType, message.runtimeType);
        expect(decoded!.toJson(), message.toJson());
      }
    });
  });

  group('orientation', () {
    test('transposing swaps the dimensions', () {
      final layout = DeckLayout.empty(columns: 5, rows: 3);

      final turned = layout.transposed();

      expect(turned.columns, 3);
      expect(turned.rows, 5);
      expect(turned.capacity, 15);
    });

    test('the first row becomes the first column', () {
      // A 5x3 grid with the top row filled left to right.
      var layout = DeckLayout.empty(columns: 5, rows: 3);
      for (var column = 0; column < 5; column++) {
        layout = layout.withSlot(column, 'app:$column');
      }

      final turned = layout.transposed();

      // Now reading down the first column of a 3-wide grid.
      for (var row = 0; row < 5; row++) {
        expect(turned.slots[row * 3]?.value, 'app:$row');
      }
    });

    test('transposing twice returns the original', () {
      final layout = DeckLayout.empty(
        columns: 5,
        rows: 3,
      ).withSlot(0, 'app:A').withSlot(7, 'app:B').withSlot(14, 'app:C');

      expect(layout.transposed().transposed().slots, layout.slots);
    });

    test('every page is transposed', () {
      final layout = DeckLayout.empty(columns: 5, rows: 3, pages: 2)
          .withSlot(4, 'app:FirstPageTopRight')
          .withSlot(15, 'app:SecondPageTopLeft');

      final turned = layout.transposed();

      // Top-right of a 5x3 is index 4; in a 3x5 it is row 4, column 0.
      expect(turned.slots[4 * 3]?.value, 'app:FirstPageTopRight');
      expect(turned.slots[turned.pageCapacity]?.value, 'app:SecondPageTopLeft');
    });

    test('orients to match the screen', () {
      final wide = DeckLayout.empty(columns: 5, rows: 3);

      expect(wide.orientedFor(portrait: false).columns, 5);
      expect(wide.orientedFor(portrait: true).columns, 3);
      expect(wide.orientedFor(portrait: true).rows, 5);
      // Already tall: portrait leaves it alone.
      final tall = wide.transposed();
      expect(tall.orientedFor(portrait: true).columns, 3);
      expect(tall.orientedFor(portrait: false).columns, 5);
    });

    test('a turned cell keeps the id it had before turning', () {
      // Host layout: 5 wide, 3 tall. Top-right is 4; second row start is 5.
      final source = DeckLayout.empty(
        columns: 5,
        rows: 3,
      ).withSlot(4, 'app:TopRight').withSlot(5, 'app:SecondRowStart');
      final turned = source.transposed();

      for (final slot in turned.slots) {
        if (slot == null) continue;
        // Wherever a button ends up on screen, its id still names the cell
        // it occupies in the host's own (unturned) copy — which is what
        // makes a press land correctly without any translation on this end.
        expect(source.slots[slot.id], slot);
      }
    });

    test('a freshly placed slot is its own id', () {
      final layout = DeckLayout.empty().withSlot(7, 'app:A');

      expect(layout.slots[7]!.id, 7);
    });

    test('an id survives transposing across pages', () {
      final source = DeckLayout.empty(
        columns: 5,
        rows: 3,
        pages: 2,
      ).withSlot(16, 'app:SecondPage');
      final turned = source.transposed();

      final shown = turned.slots.indexWhere(
        (slot) => slot?.value == 'app:SecondPage',
      );
      expect(shown, greaterThanOrEqualTo(turned.pageCapacity));
      expect(turned.slots[shown]!.id, 16);
    });

    test('a square grid is never turned', () {
      final square = DeckLayout.empty(columns: 3, rows: 3).withSlot(1, 'app:A');

      expect(square.orientedFor(portrait: true).slots, square.slots);
      expect(square.orientedFor(portrait: false).slots, square.slots);
      expect(square.transposed().slots, square.slots);
    });
  });

  group('DeckTheme', () {
    test('round-trips through a message', () {
      for (final theme in DeckTheme.values) {
        for (final showLabels in [true, false]) {
          final decoded =
              BtMessage.decode(
                    SetAppearance(
                      theme: theme,
                      showLabels: showLabels,
                    ).encode(),
                  )
                  as SetAppearance?;
          expect(decoded!.theme, theme);
          expect(decoded.showLabels, showLabels);
        }
      }
    });

    test('labels default to on when an older host omits them', () {
      // A host that predates the switch always drew labels.
      final decoded =
          BtMessage.decode(utf8.encode('{"t":"thm","v":"dark"}'))
              as SetAppearance?;

      expect(decoded!.showLabels, isTrue);
      expect(decoded.theme, DeckTheme.dark);
    });

    test('an unknown or missing value falls back to system', () {
      expect(DeckTheme.fromWire('solarized'), DeckTheme.system);
      expect(DeckTheme.fromWire(null), DeckTheme.system);
    });

    test('is offered as system, light, dark', () {
      expect(DeckTheme.values.map((theme) => theme.label), [
        'System',
        'Light',
        'Dark',
      ]);
    });
  });

  group('background appearance', () {
    test('round-trips an id, opacity, and fit', () {
      for (final fit in BackgroundFit.values) {
        final decoded =
            BtMessage.decode(
                  SetAppearance(
                    theme: DeckTheme.dark,
                    showLabels: true,
                    backgroundImageId: 'bg_1',
                    backgroundOpacity: 0.42,
                    backgroundFit: fit,
                  ).encode(),
                )
                as SetAppearance?;

        expect(decoded!.backgroundImageId, 'bg_1');
        expect(decoded.backgroundOpacity, 0.42);
        expect(decoded.backgroundFit, fit);
      }
    });

    test('defaults to no background, full opacity, cover', () {
      const message = SetAppearance(theme: DeckTheme.system, showLabels: true);

      expect(message.backgroundImageId, isNull);
      expect(message.backgroundOpacity, 1.0);
      expect(message.backgroundFit, BackgroundFit.cover);
    });

    test('an unset background is not sent on the wire at all', () {
      const message = SetAppearance(theme: DeckTheme.system, showLabels: true);

      expect(message.toJson(), isNot(contains('bg')));
      expect(message.toJson(), isNot(contains('bop')));
      expect(message.toJson(), isNot(contains('bft')));
    });

    test('an older host omitting these fields yields no background', () {
      final decoded =
          BtMessage.decode(utf8.encode('{"t":"thm","v":"dark","lbl":true}'))
              as SetAppearance?;

      expect(decoded!.backgroundImageId, isNull);
      expect(decoded.backgroundOpacity, 1.0);
      expect(decoded.backgroundFit, BackgroundFit.cover);
    });

    test('an unknown fit falls back to cover', () {
      expect(BackgroundFit.fromWire('parallax'), BackgroundFit.cover);
      expect(BackgroundFit.fromWire(null), BackgroundFit.cover);
    });

    test('is offered as cover, contain, stretch', () {
      expect(BackgroundFit.values.map((fit) => fit.wire), [
        'cover',
        'contain',
        'fill',
      ]);
    });
  });
}
