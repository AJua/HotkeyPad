import 'package:hotkeypad_host/src/update_checker.dart';
import 'package:hotkeypad_host/src/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const release = LatestRelease(
    version: '1.5.4',
    htmlUrl: 'https://example.com',
    macosAssetUrl: 'https://dl.example/a.dmg',
    windowsAssetUrl: 'https://dl.example/a-windows.zip',
  );

  group('assetUrlFor', () {
    test('picks the download for the running platform', () {
      expect(
        assetUrlFor(release, isMacOS: true, isWindows: false),
        'https://dl.example/a.dmg',
      );
      expect(
        assetUrlFor(release, isMacOS: false, isWindows: true),
        'https://dl.example/a-windows.zip',
      );
      expect(assetUrlFor(release, isMacOS: false, isWindows: false), isNull);
    });
  });

  group('macAppBundlePath', () {
    test('walks up from the executable to its .app', () {
      expect(
        macAppBundlePath(
          '/Applications/HotkeyPad Host.app/Contents/MacOS/HotkeyPad Host',
        ),
        '/Applications/HotkeyPad Host.app',
      );
    });

    test('is null outside an .app bundle', () {
      expect(macAppBundlePath('/usr/local/bin/hotkeypad'), isNull);
    });
  });

  test('macStagedPath is a hidden sibling of the bundle', () {
    expect(
      macStagedPath('/Applications/HotkeyPad Host.app'),
      '/Applications/.HotkeyPad Host.app.update',
    );
  });

  test('shellQuote survives spaces and single quotes', () {
    expect(shellQuote("it's here"), r"'it'\''s here'");
  });

  test('powershellQuote doubles single quotes', () {
    expect(powershellQuote("it's"), "'it''s'");
  });

  test('macInstallScript waits for the pid, swaps, and relaunches', () {
    final script = macInstallScript(
      pid: 42,
      bundle: '/Applications/HotkeyPad Host.app',
      staged: '/Applications/.HotkeyPad Host.app.update',
      workDir: '/tmp/work',
    );

    expect(script, contains('kill -0 42'));
    expect(
      script,
      contains(
        "mv '/Applications/.HotkeyPad Host.app.update' "
        "'/Applications/HotkeyPad Host.app'",
      ),
    );
    expect(script, contains("open '/Applications/HotkeyPad Host.app'"));
  });

  test('windowsInstallScript waits for the pid, copies, and relaunches', () {
    final script = windowsInstallScript(
      pid: 42,
      installDir: r'C:\HotkeyPad',
      executable: r'C:\HotkeyPad\hotkeypad_host.exe',
      staged: r'C:\Temp\staged',
      workDir: r'C:\Temp',
    );

    expect(script, contains('PID eq 42'));
    expect(script, contains(r'robocopy "C:\Temp\staged" "C:\HotkeyPad"'));
    expect(script, contains(r'start "" "C:\HotkeyPad\hotkeypad_host.exe"'));
  });
}
