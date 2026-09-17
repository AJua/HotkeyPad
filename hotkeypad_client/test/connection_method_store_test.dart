import 'package:hotkeypad_client/src/connection_method_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connectionMethodFromKey', () {
    test('maps each known key to its ConnectionMethod', () {
      expect(connectionMethodFromKey('bluetooth'), ConnectionMethod.bluetooth);
      expect(connectionMethodFromKey('wifi'), ConnectionMethod.wifi);
    });

    test('null means never chosen', () {
      expect(connectionMethodFromKey(null), isNull);
    });

    test('an unrecognized key also means never chosen', () {
      expect(connectionMethodFromKey('usb'), isNull);
      expect(connectionMethodFromKey(''), isNull);
    });
  });

  group('keyFromConnectionMethod', () {
    test('maps each method back to its key', () {
      expect(keyFromConnectionMethod(ConnectionMethod.bluetooth), 'bluetooth');
      expect(keyFromConnectionMethod(ConnectionMethod.wifi), 'wifi');
    });

    test('round-trips through connectionMethodFromKey for every method', () {
      for (final method in ConnectionMethod.values) {
        expect(
          connectionMethodFromKey(keyFromConnectionMethod(method)),
          method,
        );
      }
    });
  });
}
