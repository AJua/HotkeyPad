import 'dart:io';

import 'package:flutter/foundation.dart';

/// Runs the host-side commands a deck button can hold.
///
/// These only ever come from the host's own layout — a client presses a slot
/// by index and the host looks up what is there — so nothing arriving over
/// the air reaches a shell.
abstract final class CommandRunner {
  static bool get supported => !kIsWeb && Platform.isMacOS;

  /// A command that hangs would wedge the transfer queue behind it.
  static const _timeout = Duration(seconds: 10);

  static Future<({bool ok, String message})> shell(String command) async {
    if (!supported) {
      return (ok: false, message: 'Commands are only supported on macOS');
    }
    try {
      final result = await Process.run('/bin/sh', [
        '-c',
        command,
      ]).timeout(_timeout);
      if (result.exitCode == 0) {
        final output = '${result.stdout}'.trim();
        return (
          ok: true,
          message: output.isEmpty ? 'Ran' : _firstLine(output),
        );
      }
      final error = '${result.stderr}'.trim();
      return (
        ok: false,
        message: error.isEmpty
            ? 'Exited with ${result.exitCode}'
            : _firstLine(error),
      );
    } on ProcessException catch (error) {
      return (ok: false, message: error.message);
    } catch (error) {
      // Includes the timeout, which is the interesting case.
      return (ok: false, message: '$error');
    }
  }

  /// Starts a Shortcut by name through the `shortcuts` CLI, which ships with
  /// macOS 12 and later.
  ///
  /// Started rather than awaited: a Shortcut can legitimately run for
  /// minutes or put up its own interface — Shazam listens to the room —
  /// and a deck button should report that it fired, not sit spinning until
  /// the work is done. Only a failure to launch is reported as an error.
  static Future<({bool ok, String message})> shortcut(String name) async {
    if (!supported) {
      return (ok: false, message: 'Shortcuts are only supported on macOS');
    }
    try {
      final process = await Process.start('shortcuts', ['run', name]);
      // A name that does not exist fails almost immediately; anything still
      // running after this is genuinely working.
      final exitCode = await process.exitCode.timeout(
        const Duration(milliseconds: 800),
        onTimeout: () => 0,
      );
      if (exitCode != 0) {
        final error = await process.stderr
            .transform(const SystemEncoding().decoder)
            .join()
            .timeout(
              const Duration(seconds: 1),
              onTimeout: () => '',
            );
        return (
          ok: false,
          message: error.trim().isEmpty
              ? 'Could not run $name'
              : _firstLine(error),
        );
      }
      return (ok: true, message: 'Started $name');
    } on ProcessException {
      return (
        ok: false,
        message: 'The shortcuts command is unavailable (needs macOS 12+)',
      );
    } catch (error) {
      return (ok: false, message: '$error');
    }
  }

  /// The Shortcuts available to put on a button.
  static Future<List<String>> listShortcuts() async {
    if (!supported) return const [];
    try {
      final result = await Process.run('shortcuts', ['list']).timeout(_timeout);
      if (result.exitCode != 0) return const [];
      return '${result.stdout}'
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Output is shown on a button-sized ack, so only the first line is useful.
  static String _firstLine(String text) {
    final line = text.split('\n').first.trim();
    return line.length > 120 ? '${line.substring(0, 120)}…' : line;
  }
}
