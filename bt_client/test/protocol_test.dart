import 'dart:convert';

import 'package:bt_client/src/protocol.dart';
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
      final json = utf8.encode(jsonEncode(const OpenApp(name: 'Safari')));

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
        ListApps(),
        AppEntry(name: 'Safari', category: 'Apps'),
        ListEnd(count: 96),
        OpenApp(name: 'Safari'),
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

    test('an app and an action never collide', () {
      expect(
        const AppItem('playpause').stored,
        isNot(const ActionItem(DeckAction.playPause).stored),
      );
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
      final layout = DeckLayout.empty(pages: 2)
          .withSlot(0, 'app:First')
          .withSlot(15, 'app:Second');

      expect(layout.page(0).first, 'app:First');
      expect(layout.page(0).length, 15);
      expect(layout.page(1).first, 'app:Second');
    });

    test('moving works across pages', () {
      // A drag from page 0 to page 1 is an ordinary index move.
      final moved = DeckLayout.empty(pages: 2)
          .withSlot(0, 'app:A')
          .moved(0, 20);

      expect(moved.slots[0], isNull);
      expect(moved.slots[20], 'app:A');
    });

    test('adding a page leaves existing pages untouched', () {
      final layout = DeckLayout.empty().withSlot(14, 'app:Last');

      final grown = layout.resized(pages: 2);

      expect(grown.capacity, 30);
      expect(grown.slots[14], 'app:Last');
      expect(grown.page(1).every((slot) => slot == null), isTrue);
    });

    test('removing a page drops only that page', () {
      final layout = DeckLayout.empty(pages: 2)
          .withSlot(0, 'app:Keep')
          .withSlot(15, 'app:Drop');

      final shrunk = layout.resized(pages: 1);

      expect(shrunk.slots.contains('app:Keep'), isTrue);
      expect(shrunk.slots.contains('app:Drop'), isFalse);
    });

    test('reads a layout written before pages existed', () {
      final decoded = DeckLayout.fromJson({
        'columns': 2,
        'rows': 2,
        'slots': <String?>[null, 'app:A', null, null],
      });

      expect(decoded!.pages, 1);
      expect(decoded.slots[1], 'app:A');
    });

    test('moving swaps the two cells', () {
      final layout = DeckLayout.empty()
          .withSlot(0, 'app:A')
          .withSlot(1, 'app:B');

      final moved = layout.moved(0, 1);

      expect(moved.slots[0], 'app:B');
      expect(moved.slots[1], 'app:A');
    });

    test('moving into an empty cell leaves the source empty', () {
      final moved = DeckLayout.empty().withSlot(0, 'app:A').moved(0, 7);

      expect(moved.slots[0], isNull);
      expect(moved.slots[7], 'app:A');
    });

    test('resizing keeps cells in the same screen position', () {
      // Second row, first column of a 5-wide grid.
      final layout = DeckLayout.empty().withSlot(5, 'app:A');

      final wider = layout.resized(columns: 6);

      // Still second row, first column — index 6 in a 6-wide grid. A naive
      // copy would leave it at index 5, sliding it up a row.
      expect(wider.slots[6], 'app:A');
      expect(wider.slots[5], isNull);
    });

    test('shrinking drops cells that fall outside', () {
      final layout = DeckLayout.empty().withSlot(4, 'app:Edge');

      final narrower = layout.resized(columns: 3);

      expect(narrower.capacity, 9);
      expect(narrower.slots.contains('app:Edge'), isFalse);
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
      final layout = DeckLayout.empty(columns: 2, rows: 2)
          .withSlot(3, 'act:mute');

      final decoded = DeckLayout.fromJson(layout.toJson());

      expect(decoded!.slots, layout.slots);
      expect(decoded.columns, 2);
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
}
