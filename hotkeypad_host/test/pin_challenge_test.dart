import 'package:hotkeypad_host/src/host_page.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bleAttemptExhausted', () {
    test('is false for a BLE central that has not failed a PIN yet', () {
      expect(
        bleAttemptExhausted(
          transport: LinkTransport.bluetooth,
          alreadyRejected: false,
        ),
        isFalse,
      );
    });

    test('is true once a BLE central has already been rejected', () {
      expect(
        bleAttemptExhausted(
          transport: LinkTransport.bluetooth,
          alreadyRejected: true,
        ),
        isTrue,
      );
    });

    test('is always false for WiFi, which closes the socket instead', () {
      expect(
        bleAttemptExhausted(transport: LinkTransport.wifi, alreadyRejected: true),
        isFalse,
      );
    });
  });

  group('initialSubscribedFor', () {
    test('is always true for WiFi, regardless of what BLE tracked', () {
      expect(
        initialSubscribedFor(transport: LinkTransport.wifi, bleSubscribed: null),
        isTrue,
      );
      expect(
        initialSubscribedFor(transport: LinkTransport.wifi, bleSubscribed: false),
        isTrue,
      );
    });

    test('reads back whatever BLE already recorded', () {
      expect(
        initialSubscribedFor(
          transport: LinkTransport.bluetooth,
          bleSubscribed: true,
        ),
        isTrue,
      );
      expect(
        initialSubscribedFor(
          transport: LinkTransport.bluetooth,
          bleSubscribed: false,
        ),
        isFalse,
      );
    });

    test('is null for BLE when nothing was ever recorded', () {
      expect(
        initialSubscribedFor(
          transport: LinkTransport.bluetooth,
          bleSubscribed: null,
        ),
        isNull,
      );
    });
  });
}
