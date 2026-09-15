import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// A persistent id for this Mac, independent of any one transport.
///
/// Bluetooth already has an identity a client can key its cache on for
/// free: the OS mints a stable per-pairing UUID for the peripheral (see
/// `hotkeypad_client`'s `HotkeyPadSession.hostId`). WiFi has nothing analogous — a
/// TCP connection's address can change with DHCP, and there is no pairing
/// step — so this is what a `WifiBeacon` carries instead: generated once,
/// on first use, and reused for as long as `~/.config/HotkeyPad/host_id`
/// exists.
abstract final class HostIdentity {
  static String? _cached;

  static File? get _file {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return File('$home/.config/HotkeyPad/host_id');
  }

  static Future<String> id() async {
    final cached = _cached;
    if (cached != null) return cached;

    final file = _file;
    if (file == null) return _cached = _generate();

    try {
      if (file.existsSync()) {
        final existing = (await file.readAsString()).trim();
        if (existing.isNotEmpty) return _cached = existing;
      }
    } on FileSystemException {
      // Fall through and mint a fresh one.
    }

    final generated = _generate();
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(generated, flush: true);
    } on FileSystemException {
      // Losing persistence is better than taking the app down — this
      // session just mints a new id again next launch.
    }
    return _cached = generated;
  }

  static String _generate() =>
      'host_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
}
