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
      expect(parseLatestRelease({'html_url': 'https://example.com'}), isNull);
    });

    test('a missing html_url yields null', () {
      expect(parseLatestRelease({'tag_name': 'v1.0.0'}), isNull);
    });

    test('a tag that is only "v" yields null', () {
      expect(
        parseLatestRelease({
          'tag_name': 'v',
          'html_url': 'https://example.com',
        }),
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

  group('parseNewestHostRelease', () {
    Map<String, dynamic> release(
      String tag, {
      bool draft = false,
      List<String> assets = const [],
    }) => {
      'tag_name': tag,
      'html_url': 'https://github.com/AJua/HotkeyPad/releases/tag/$tag',
      'draft': draft,
      'prerelease': true,
      'assets': [
        for (final name in assets)
          {'name': name, 'browser_download_url': 'https://dl.example/$name'},
      ],
    };

    test('picks the newest host release, ignoring client ones', () {
      final newest = parseNewestHostRelease([
        release('client-v9.0.0'),
        release('host-v1.5.3'),
        release('host-v1.5.10'),
        release('host-v1.5.4'),
      ]);

      expect(newest?.version, '1.5.10');
    });

    test('skips drafts', () {
      final newest = parseNewestHostRelease([
        release('host-v2.0.0', draft: true),
        release('host-v1.5.4'),
      ]);

      expect(newest?.version, '1.5.4');
    });

    test('picks up the macOS and Windows downloads', () {
      final newest = parseNewestHostRelease([
        release(
          'host-v1.5.4',
          assets: [
            'HotkeyPad.Host-1.5.4.dmg',
            'HotkeyPad-Host-1.5.4-windows.zip',
          ],
        ),
      ]);

      expect(
        newest?.macosAssetUrl,
        'https://dl.example/HotkeyPad.Host-1.5.4.dmg',
      );
      expect(
        newest?.windowsAssetUrl,
        'https://dl.example/HotkeyPad-Host-1.5.4-windows.zip',
      );
    });

    test('is null when there is no host release at all', () {
      expect(parseNewestHostRelease([release('client-v1.6.2')]), isNull);
      expect(parseNewestHostRelease([]), isNull);
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
