import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Finds and launches applications on the machine running the host.
///
/// Only macOS is implemented. The other desktop platforms have no equivalent
/// of a single well-known application directory, and the mobile platforms
/// cannot launch arbitrary apps at all, so they report the gap rather than
/// pretending to work.
abstract final class AppLauncher {
  static bool get supported => !kIsWeb && Platform.isMacOS;

  static const _channel = MethodChannel('btlink/icons');

  /// Directories scanned for `.app` bundles, in the order a user would think
  /// of them.
  static const _searchPaths = [
    '/Applications',
    '/System/Applications',
    '/Applications/Utilities',
    '/System/Applications/Utilities',
  ];

  /// Returns the installed applications, de-duplicated and sorted by name.
  ///
  /// Only the top level of each directory is scanned: nesting deeper turns up
  /// helper bundles inside other apps, which are not things a user wants on a
  /// button.
  /// Stand-ins so the layout editor can be developed and checked in a
  /// browser, where there is no filesystem to scan.
  static const _webSamples = [
    'Safari',
    'Terminal',
    'Xcode',
    'Android Studio',
    'Slack',
    'Notes',
    'Music',
    'Finder',
    'System Settings',
    'Calendar',
  ];

  static Future<List<({String name, String category, String path})>>
  list() async {
    if (kIsWeb) {
      return [
        for (final name in _webSamples)
          (name: name, category: 'Apps', path: '/Applications/$name.app'),
      ];
    }
    if (!supported) return const [];

    final seen = <String>{};
    final apps = <({String name, String category, String path})>[];

    for (final path in _searchPaths) {
      final directory = Directory(path);
      if (!directory.existsSync()) continue;

      final category = path.endsWith('Utilities') ? 'Utilities' : 'Apps';
      try {
        for (final entry in directory.listSync(followLinks: false)) {
          final base = entry.path.split('/').last;
          if (!base.endsWith('.app')) continue;
          final name = base.substring(0, base.length - 4);
          if (!seen.add(name)) continue;
          apps.add((name: name, category: category, path: entry.path));
        }
      } on FileSystemException {
        // An unreadable directory is not worth failing the whole catalogue.
        continue;
      }
    }

    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  /// Renders [path]'s icon as a PNG of [size] points square.
  ///
  /// Delegates to AppKit rather than reading CFBundleIconFile: modern apps
  /// keep their icon in Assets.car, where the plist route finds nothing.
  static Future<Uint8List?> icon(String path, {int size = 64}) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('icon', {
        'path': path,
        'size': size,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Launches [name], returning whether it worked and what to show the user.
  static Future<({bool ok, String message})> open(String name) async {
    if (!supported) {
      return (ok: false, message: 'Launching apps is only supported on macOS');
    }
    // `open -a` takes an application name, not a path, and refuses anything
    // it cannot resolve — which is the validation we want on a value that
    // arrived over the air.
    try {
      final result = await Process.run('open', ['-a', name]);
      if (result.exitCode == 0) {
        return (ok: true, message: 'Opened $name');
      }
      final stderrText = '${result.stderr}'.trim();
      return (
        ok: false,
        message: stderrText.isEmpty
            ? 'Could not open $name (exit ${result.exitCode})'
            : stderrText,
      );
    } on ProcessException catch (error) {
      return (ok: false, message: '${error.message} ($name)');
    }
  }
}
