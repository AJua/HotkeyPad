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
}
