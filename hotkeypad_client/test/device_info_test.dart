import 'package:hotkeypad_client/src/device_info.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('btlink/device');

  void mock(Future<Object?> Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => mock(null));

  group('DeviceInfo.name', () {
    test('returns the platform-reported name', () async {
      mock((call) async => 'Ray\'s Pixel');

      expect(await DeviceInfo.name(), "Ray's Pixel");
    });

    test('falls back to a generic name when the platform reports none', () async {
      mock((call) async => null);

      final name = await DeviceInfo.name();
      expect(name, isNotEmpty);
    });

    test('falls back when the channel is missing entirely', () async {
      mock(null);

      final name = await DeviceInfo.name();
      expect(name, isNotEmpty);
    });

    test('falls back when the platform throws', () async {
      mock((call) async => throw PlatformException(code: 'unavailable'));

      final name = await DeviceInfo.name();
      expect(name, isNotEmpty);
    });

    test('never returns an empty string', () async {
      mock((call) async => '');

      final name = await DeviceInfo.name();
      expect(name, isNotEmpty);
    });
  });
}
