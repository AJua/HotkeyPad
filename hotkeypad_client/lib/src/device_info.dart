import 'dart:io';

import 'package:flutter/services.dart';

/// This device's own name, for the [Hello] message the host uses to tell
/// connected clients apart in its device-lock dropdown.
///
/// Reads the actual Bluetooth-assigned device name from the platform (the
/// same name the phone shows in its own Bluetooth settings) rather than
/// adding a device-info package: Android exposes it directly via
/// `BluetoothAdapter.getName()`. iOS's `UIDevice.name` is generic
/// ("iPhone") for every third-party app since iOS 16 — no entitlement fixes
/// that, so this is a known, accepted limitation there, not a bug here.
abstract final class DeviceInfo {
  static const _channel = MethodChannel('btlink/device');

  static Future<String> name() async {
    try {
      final name = await _channel.invokeMethod<String>('name');
      if (name != null && name.isNotEmpty) return name;
    } on PlatformException {
      // Falls through to the generic name below.
    } on MissingPluginException {
      // Falls through — e.g. no macOS implementation, since hotkeypad_client only
      // ships on Android and iOS.
    }
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android phone';
    return 'Unknown device';
  }
}
