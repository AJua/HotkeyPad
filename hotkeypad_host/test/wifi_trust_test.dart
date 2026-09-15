import 'package:hotkeypad_host/src/wifi_trust_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wifiTrustFor', () {
    test('is unknown for a client id never decided on', () {
      expect(wifiTrustFor('client_a', {}), WifiTrust.unknown);
      expect(
        wifiTrustFor('client_a', {'client_b': true}),
        WifiTrust.unknown,
      );
    });

    test('is trusted once accepted', () {
      expect(
        wifiTrustFor('client_a', {'client_a': true}),
        WifiTrust.trusted,
      );
    });

    test('is blocked once rejected', () {
      expect(
        wifiTrustFor('client_a', {'client_a': false}),
        WifiTrust.blocked,
      );
    });
  });
}
