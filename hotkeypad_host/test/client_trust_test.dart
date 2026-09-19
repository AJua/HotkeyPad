import 'package:hotkeypad_host/src/client_trust_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trustFor', () {
    test('is unknown for a client id never decided on', () {
      expect(trustFor('client_a', {}), ClientTrust.unknown);
      expect(
        trustFor('client_a', {'client_b': true}),
        ClientTrust.unknown,
      );
    });

    test('is trusted once accepted', () {
      expect(
        trustFor('client_a', {'client_a': true}),
        ClientTrust.trusted,
      );
    });

    test('is blocked once rejected', () {
      expect(
        trustFor('client_a', {'client_a': false}),
        ClientTrust.blocked,
      );
    });
  });
}
