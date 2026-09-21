import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'media_control.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Runs the host-side commands a deck button can hold.
///
/// These only ever come from the host's own layout — a client presses a slot
/// by index and the host looks up what is there — so nothing arriving over
/// the air reaches a shell.
abstract final class CommandRunner {
  static bool get supported => !kIsWeb && Platform.isMacOS;

  /// A command that hangs would wedge the transfer queue behind it.
  static const _timeout = Duration(seconds: 10);

  static Future<({bool ok, String message})> shell(
    String command, {
    ShellKind shell = ShellKind.sh,
  }) async {
    if (!supported) {
      return (ok: false, message: 'Commands are only supported on macOS');
    }
    try {
      // Resolved through env rather than a fixed path: sh/bash/zsh all live
      // at a stable /bin path on macOS, but fish is user-installed (Homebrew
      // puts it somewhere different on Intel and Apple Silicon), so only a
      // PATH lookup finds it on every machine.
      final result = await Process.run('/usr/bin/env', [
        shell.wire,
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

  /// Sends a keyboard combination to whatever is frontmost.
  ///
  /// Through System Events rather than CGEvent: AppleScript maps a character
  /// to the right key for the current layout, which a virtual key code does
  /// not. Keys with no character are sent by code instead. Either way macOS
  /// requires Accessibility, and silently does nothing without it — so the
  /// trust state is checked first and reported.
  static Future<({bool ok, String message})> keyCombo({
    required List<KeyModifier> modifiers,
    String? key,
    SpecialKey? special,
    required String label,
  }) async {
    if (!supported) {
      return (ok: false, message: 'Key combinations are macOS only');
    }
    if (!await MediaControl.trusted) {
      // Puts up the system prompt that deep-links to the right pane. macOS
      // shows it once per app, so this cannot become a nuisance — the
      // status line in Service details covers it after that.
      unawaited(MediaControl.requestTrust());
      return (
        ok: false,
        message:
            'Grant this app Accessibility in System Settings > Privacy & '
            'Security > Accessibility',
      );
    }

    final using = modifiers.isEmpty
        ? ''
        : ' using {${modifiers.map((m) => m.appleScript).join(', ')}}';
    final String action;
    if (special != null) {
      action = 'key code ${special.code}';
    } else if (key != null && key.isNotEmpty) {
      // Escape for AppleScript's string syntax, not the shell: the script is
      // passed as one argument, never through a shell.
      final escaped = key
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"');
      action = 'keystroke "$escaped"';
    } else {
      return (ok: false, message: 'No key to send');
    }

    try {
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to $action$using',
      ]).timeout(_timeout);
      if (result.exitCode == 0) return (ok: true, message: 'Sent $label');
      final error = '${result.stderr}'.trim();
      return (
        ok: false,
        message: error.isEmpty ? 'Could not send $label' : _firstLine(error),
      );
    } catch (error) {
      return (ok: false, message: '$error');
    }
  }

  /// Opens [url] in Chrome, focusing a tab already showing it instead of
  /// opening a duplicate.
  ///
  /// Chrome's AppleScript dictionary has no "open or focus" verb, so this
  /// walks every window's tabs looking for one whose URL already contains
  /// [url] before falling back to a new tab in the frontmost window (or a
  /// new window, if Chrome has none open). [url] travels as an `osascript`
  /// argument (`item 1 of argv`), never spliced into the script text, so
  /// nothing in it can break out into other AppleScript.
  static Future<({bool ok, String message})> openUrl(String url) async {
    if (!supported) {
      return (ok: false, message: 'Opening a URL is only supported on macOS');
    }
    if (url.isEmpty) {
      return (ok: false, message: 'No URL to open');
    }
    try {
      final result = await Process.run('osascript', [
        '-e',
        _openUrlScript,
        url,
      ]).timeout(_timeout);
      if (result.exitCode == 0) return (ok: true, message: 'Opened $url');
      final error = '${result.stderr}'.trim();
      return (
        ok: false,
        message: error.isEmpty ? 'Could not open $url' : _firstLine(error),
      );
    } catch (error) {
      return (ok: false, message: '$error');
    }
  }

  static const _openUrlScript = '''
on run argv
  set target to item 1 of argv
  tell application "Google Chrome"
    activate
    if (count of windows) is 0 then
      make new window
      set URL of active tab of window 1 to target
      return
    end if
    repeat with w in windows
      set tabIndex to 1
      repeat with t in tabs of w
        if URL of t contains target then
          set active tab index of w to tabIndex
          set index of w to 1
          return
        end if
        set tabIndex to tabIndex + 1
      end repeat
    end repeat
    tell window 1 to make new tab with properties {URL:target}
  end tell
end run
''';

  /// Output is shown on a button-sized ack, so only the first line is useful.
  static String _firstLine(String text) {
    final line = text.split('\n').first.trim();
    return line.length > 120 ? '${line.substring(0, 120)}…' : line;
  }
}
