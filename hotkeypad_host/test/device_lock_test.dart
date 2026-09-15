import 'package:hotkeypad_host/src/host_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPressAllowed', () {
    test('rejects everyone when nothing is picked', () {
      expect(isPressAllowed(clientId: 'a', lockedClientId: null), isFalse);
      expect(isPressAllowed(clientId: 'b', lockedClientId: null), isFalse);
    });

    test('accepts the picked client', () {
      expect(isPressAllowed(clientId: 'a', lockedClientId: 'a'), isTrue);
    });

    test('rejects anyone but the picked client', () {
      expect(isPressAllowed(clientId: 'b', lockedClientId: 'a'), isFalse);
    });
  });

  group('nextLockedClientId', () {
    test('picks the sole connected client automatically', () {
      expect(
        nextLockedClientId(
          currentLockedClientId: null,
          connectedClientIds: ['a'],
        ),
        'a',
      );
    });

    test('stays unpicked with no clients connected', () {
      expect(
        nextLockedClientId(
          currentLockedClientId: null,
          connectedClientIds: [],
        ),
        isNull,
      );
    });

    test('stays unpicked with more than one candidate', () {
      expect(
        nextLockedClientId(
          currentLockedClientId: null,
          connectedClientIds: ['a', 'b'],
        ),
        isNull,
      );
    });

    test('never overrides an existing explicit choice', () {
      // Even once a second device connects, or the auto-picked one is no
      // longer the only candidate — an explicit pick is a deliberate act
      // the client list changing should not undo.
      expect(
        nextLockedClientId(
          currentLockedClientId: 'a',
          connectedClientIds: ['a', 'b'],
        ),
        'a',
      );
    });

    test(
      'keeps an explicit choice even once it is the only one left, rather '
      'than re-deriving it',
      () {
        expect(
          nextLockedClientId(
            currentLockedClientId: 'a',
            connectedClientIds: ['a'],
          ),
          'a',
        );
      },
    );
  });
}
