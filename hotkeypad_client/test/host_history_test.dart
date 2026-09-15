import 'package:hotkeypad_client/src/host_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

HostHistoryEntry _entry(
  String address, {
  int port = 54871,
  String name = 'HotkeyPad',
  String? hostId,
  DateTime? at,
}) => HostHistoryEntry(
  hostId: hostId ?? 'manual:$address:$port',
  address: address,
  port: port,
  name: name,
  lastConnectedAt: at ?? DateTime(2026, 1, 1),
);

void main() {
  group('upsertHistory', () {
    test('a new host is added to the front', () {
      final result = upsertHistory([], _entry('192.168.1.10'));
      expect(result, hasLength(1));
      expect(result.single.address, '192.168.1.10');
    });

    test('reconnecting to the same address+port updates it in place', () {
      final first = _entry('192.168.1.10', name: 'Old name', at: DateTime(2026, 1, 1));
      final second = _entry('192.168.1.10', name: 'New name', at: DateTime(2026, 1, 2));

      final result = upsertHistory([first], second);

      expect(result, hasLength(1));
      expect(result.single.name, 'New name');
      expect(result.single.lastConnectedAt, DateTime(2026, 1, 2));
    });

    test('the same address on a different port is a distinct entry', () {
      final result = upsertHistory(
        [_entry('192.168.1.10', port: 54871)],
        _entry('192.168.1.10', port: 9999),
      );
      expect(result, hasLength(2));
    });

    test('the most recently connected host is always first', () {
      final result = upsertHistory([
        _entry('192.168.1.10'),
        _entry('192.168.1.11'),
      ], _entry('192.168.1.12'));

      expect(result.map((e) => e.address), [
        '192.168.1.12',
        '192.168.1.10',
        '192.168.1.11',
      ]);
    });

    test('the list never grows past hostHistoryLimit', () {
      var current = <HostHistoryEntry>[];
      for (var i = 0; i < hostHistoryLimit + 5; i++) {
        current = upsertHistory(current, _entry('10.0.0.$i'));
      }
      expect(current, hasLength(hostHistoryLimit));
      // The most recently added ones survive; the oldest are dropped.
      expect(current.first.address, '10.0.0.${hostHistoryLimit + 4}');
    });
  });
}
