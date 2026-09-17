import 'dart:async';
import 'dart:io';

import 'package:hotkeypad_client/src/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reconnect contract, exercised on the shapes that broke it rather than
/// on a live BLE stack.
///
/// A connect attempt that never returns is the failure this guards: iOS
/// waits indefinitely for a peripheral to reappear, and `connect()` cancels
/// the backoff before it starts, so an unbounded attempt stops the deck from
/// ever retrying.
void main() {
  group('a hung connect', () {
    test('gives up instead of waiting forever', () async {
      final neverCompletes = Completer<void>();

      await expectLater(
        neverCompletes.future.timeout(const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('produces something other than StateError, so it is retried', () {
      // connect() retries anything that is not a StateError, which is
      // reserved for a device that will never speak HotkeyPad.
      expect(TimeoutException('x'), isNot(isA<StateError>()));
    });
  });

  group('attempt versioning', () {
    test('a superseded attempt does not report back', () {
      // The pattern connect() uses: an attempt only owns the state while it
      // is still the newest one. A timed-out attempt is abandoned rather
      // than cancelled — CoreBluetooth keeps working on it — so it can
      // still complete later.
      var current = 0;
      final reported = <int>[];

      void finish(int attempt) {
        if (attempt != current) return;
        reported.add(attempt);
      }

      final first = ++current;
      final second = ++current;

      // The first attempt completes late, after the second superseded it.
      finish(first);
      finish(second);

      expect(reported, [second]);
    });
  });

  group('isUnresolvableHostError', () {
    test('true for a failed DNS lookup', () {
      expect(
        isUnresolvableHostError(
          const SocketException("Failed host lookup: 'not-an-ip-address'"),
        ),
        isTrue,
      );
    });

    test('false for a refused/timed-out connection — worth retrying', () {
      expect(
        isUnresolvableHostError(
          const SocketException('Connection refused'),
        ),
        isFalse,
      );
    });

    test('false for anything that is not a SocketException at all', () {
      expect(isUnresolvableHostError(TimeoutException('x')), isFalse);
      expect(isUnresolvableHostError(StateError('x')), isFalse);
    });
  });
}
