import 'package:bt_host/src/app_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds installed applications on macOS', () async {
    if (!AppLauncher.supported) return;

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

  test('reports a failure for an app that does not exist', () async {
    if (!AppLauncher.supported) return;

    final result = await AppLauncher.open('NoSuchApp_${DateTime.now()}');

    expect(result.ok, isFalse);
    expect(result.message, isNotEmpty);
  });
}
