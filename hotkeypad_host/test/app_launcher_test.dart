import 'dart:io';
import 'dart:typed_data';

import 'package:hotkeypad_host/src/app_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds installed applications on macOS', () async {
    if (!Platform.isMacOS) return;

    final apps = await AppLauncher.list();

    expect(apps, isNotEmpty);
    final names = apps.map((app) => app.name).toList();
    // Shipped with every macOS install, so its absence means the scan is
    // looking in the wrong place.
    expect(names, contains('Safari'));
    expect(names.toSet().length, names.length, reason: 'names must be unique');
    expect(names, equals(List.of(names)..sort(
      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
    )));
  });

  test('finds installed applications on Windows', () async {
    if (!Platform.isWindows) return;

    final apps = await AppLauncher.list();

    expect(apps, isNotEmpty);
    final names = apps.map((app) => app.name).toList();
    // Shipped with every Windows install, so its absence means the scan is
    // looking in the wrong place.
    expect(names, contains('Command Prompt'));
    expect(names.toSet().length, names.length, reason: 'names must be unique');
    expect(names, equals(List.of(names)..sort(
      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
    )));
  });

  test('renders an icon for a real Windows shortcut without throwing', () async {
    if (!Platform.isWindows) return;

    final apps = await AppLauncher.list();
    expect(apps, isNotEmpty);

    // Not every shortcut resolves to something with a renderable icon, so
    // this only asserts the extraction path is exception-free end to end —
    // decoding the HICON, converting it, and re-encoding as PNG.
    for (final app in apps.take(10)) {
      final bytes = await AppLauncher.icon(app.path);
      if (bytes != null) expect(bytes, isNotEmpty);
    }
  });

  test('reports a failure for an app that does not exist', () async {
    if (!AppLauncher.supported) return;

    final result = await AppLauncher.open('NoSuchApp_${DateTime.now()}');

    expect(result.ok, isFalse);
    expect(result.message, isNotEmpty);
  });

  group('bgraToRgba', () {
    test('swaps blue and red', () {
      final bgra = Uint8List.fromList([10, 20, 30, 255]);

      final rgba = AppLauncher.bgraToRgba(bgra);

      expect(rgba, [30, 20, 10, 255]);
    });

    test('forces full opacity when the whole buffer has no alpha', () {
      final bgra = Uint8List.fromList([10, 20, 30, 0, 40, 50, 60, 0]);

      final rgba = AppLauncher.bgraToRgba(bgra);

      expect(rgba, [30, 20, 10, 255, 60, 50, 40, 255]);
    });

    test('keeps a real alpha channel as-is', () {
      final bgra = Uint8List.fromList([10, 20, 30, 128, 40, 50, 60, 0]);

      final rgba = AppLauncher.bgraToRgba(bgra);

      expect(rgba, [30, 20, 10, 128, 60, 50, 40, 0]);
    });
  });
}
