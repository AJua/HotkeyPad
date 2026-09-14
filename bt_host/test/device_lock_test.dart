import 'package:bt_host/src/host_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPressAllowed', () {
    test('accepts anyone when nothing is locked', () {
      expect(
        isPressAllowed(centralId: 'a', lockedClientId: null),
        isTrue,
      );
      expect(
        isPressAllowed(centralId: 'b', lockedClientId: null),
        isTrue,
      );
    });

    test('accepts the locked client', () {
      expect(
        isPressAllowed(centralId: 'a', lockedClientId: 'a'),
        isTrue,
      );
    });

    test('rejects anyone but the locked client', () {
      expect(
        isPressAllowed(centralId: 'b', lockedClientId: 'a'),
        isFalse,
      );
    });
  });
}
