import 'package:hotkeypad_host/src/update_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldCheckNow', () {
    test('never checked before is always due', () {
      expect(shouldCheckNow(null, DateTime(2026, 1, 2)), isTrue);
    });

    test('checked moments ago is not due', () {
      final now = DateTime(2026, 1, 2, 12);
      expect(shouldCheckNow(now.subtract(const Duration(minutes: 5)), now), isFalse);
    });

    test('checked more than a day ago is due again', () {
      final now = DateTime(2026, 1, 2, 12);
      expect(
        shouldCheckNow(now.subtract(const Duration(hours: 25)), now),
        isTrue,
      );
    });

    test('exactly at the interval boundary is due', () {
      final now = DateTime(2026, 1, 2, 12);
      expect(
        shouldCheckNow(now.subtract(updateCheckInterval), now),
        isTrue,
      );
    });

    test('just under the interval boundary is not due', () {
      final now = DateTime(2026, 1, 2, 12);
      expect(
        shouldCheckNow(
          now.subtract(updateCheckInterval - const Duration(seconds: 1)),
          now,
        ),
        isFalse,
      );
    });
  });

  group('shouldShowBanner', () {
    test('never dismissed shows the banner', () {
      expect(shouldShowBanner(null, '1.2.0'), isTrue);
    });

    test('dismissing exactly this version hides it', () {
      expect(shouldShowBanner('1.2.0', '1.2.0'), isFalse);
    });

    test('a version newer than the dismissed one shows again', () {
      expect(shouldShowBanner('1.1.0', '1.2.0'), isTrue);
    });
  });
}
