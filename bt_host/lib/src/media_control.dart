import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:bt_link_protocol/bt_link_protocol.dart';

/// Performs the non-launch deck actions on the host machine.
///
/// Two mechanisms, for a reason worth remembering: volume is scriptable and
/// works with no special permission, while transport control is not exposed
/// to any script and has to be posted as an HID system event, which macOS
/// drops unless the app is trusted for Accessibility.
abstract final class MediaControl {
  static bool get supported => !kIsWeb && Platform.isMacOS;

  static const _channel = MethodChannel('btlink/media');

  /// Whether posting media keys will actually do anything.
  static Future<bool> get trusted async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('trusted') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shows the system prompt that deep-links to the Accessibility pane.
  static Future<void> requestTrust() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('requestTrust');
    } on MissingPluginException {
      // Nothing to prompt with on this platform.
    }
  }

  static Future<({bool ok, String message})> run(DeckAction action) async {
    if (!supported) {
      return (ok: false, message: 'Actions are only supported on macOS');
    }
    return action.isVolume ? _volume(action) : _transport(action);
  }

  static Future<({bool ok, String message})> _transport(
    DeckAction action,
  ) async {
    try {
      await _channel.invokeMethod<bool>('key', {'key': action.wire});
      return (ok: true, message: action.label);
    } on PlatformException catch (error) {
      // The only expected failure is the missing permission; prompt for it.
      if (error.code == 'not-trusted') unawaited(requestTrust());
      return (ok: false, message: error.message ?? 'Media key failed');
    } on MissingPluginException {
      return (ok: false, message: 'Media keys are unavailable');
    }
  }

  /// Volume steps match the 6.25% of a hardware key press (16 steps).
  static const _step = 6;

  static Future<({bool ok, String message})> _volume(DeckAction action) async {
    try {
      if (action == DeckAction.mute) {
        final muted = await _script('output muted of (get volume settings)');
        final next = muted.trim() == 'true' ? 'false' : 'true';
        await _script('set volume output muted $next');
        return (ok: true, message: next == 'true' ? 'Muted' : 'Unmuted');
      }

      final current =
          int.tryParse(
            (await _script('output volume of (get volume settings)')).trim(),
          ) ??
          0;
      final target = (action == DeckAction.volumeUp
              ? current + _step
              : current - _step)
          .clamp(0, 100);
      // Changing the volume while muted should also unmute, as the hardware
      // keys do.
      await _script('set volume output volume $target output muted false');
      return (ok: true, message: 'Volume $target%');
    } on ProcessException catch (error) {
      return (ok: false, message: error.message);
    } on StateError catch (error) {
      return (ok: false, message: error.message);
    }
  }

  static Future<String> _script(String source) async {
    final result = await Process.run('osascript', ['-e', source]);
    if (result.exitCode != 0) {
      throw StateError('${result.stderr}'.trim());
    }
    return '${result.stdout}';
  }
}
