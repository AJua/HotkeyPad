import 'package:hotkeypad_host/src/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLatestRelease', () {
    test('a well-formed release response parses, v stripped', () {
      final release = parseLatestRelease({
        'tag_name': 'v1.2.0',
        'html_url': 'https://github.com/AJua/HotkeyPad/releases/tag/v1.2.0',
        'name': 'HotkeyPad Host 1.2.0',
        'published_at': '2026-01-01T00:00:00Z',
      });

      expect(release?.version, '1.2.0');
      expect(
        release?.htmlUrl,
        'https://github.com/AJua/HotkeyPad/releases/tag/v1.2.0',
      );
    });

    test('a tag with no leading v is used as-is', () {
      expect(
        parseLatestRelease({
          'tag_name': '1.2.0',
          'html_url': 'https://example.com',
        })?.version,
        '1.2.0',
      );
    });

    test('a missing tag_name yields null', () {
      expect(
        parseLatestRelease({'html_url': 'https://example.com'}),
        isNull,
      );
    });

    test('a missing html_url yields null', () {
      expect(parseLatestRelease({'tag_name': 'v1.0.0'}), isNull);
    });

    test('a tag that is only "v" yields null', () {
      expect(
        parseLatestRelease({'tag_name': 'v', 'html_url': 'https://example.com'}),
        isNull,
      );
    });

    test('non-string fields yield null instead of throwing', () {
      expect(
        parseLatestRelease({'tag_name': 42, 'html_url': 'https://example.com'}),
        isNull,
      );
    });
  });

  group('isNewerVersion', () {
    test('a newer patch version is newer', () {
      expect(isNewerVersion('1.0.0', '1.0.1'), isTrue);
    });

    test('a newer minor version is newer', () {
      expect(isNewerVersion('1.0.9', '1.1.0'), isTrue);
    });

    test('a newer major version is newer', () {
      expect(isNewerVersion('1.9.9', '2.0.0'), isTrue);
    });

    test('the same version is not newer', () {
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    });

    test('an older version is not newer', () {
      expect(isNewerVersion('1.2.0', '1.1.0'), isFalse);
    });

    test('a leading v on either or both sides is tolerated', () {
      expect(isNewerVersion('v1.0.0', '1.1.0'), isTrue);
      expect(isNewerVersion('1.0.0', 'v1.1.0'), isTrue);
      expect(isNewerVersion('v1.0.0', 'v1.0.0'), isFalse);
    });

    test('a missing trailing segment counts as zero', () {
      expect(isNewerVersion('1.2', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2', '1.2.1'), isTrue);
    });

    test('malformed input returns false rather than throwing', () {
      expect(isNewerVersion('not-a-version', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', 'not-a-version'), isFalse);
      expect(isNewerVersion('', ''), isFalse);
    });
  });
}
