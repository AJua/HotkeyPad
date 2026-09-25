import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'icon_trim.dart';
import 'win32_app_launcher.dart'
    if (dart.library.js_interop) 'win32_app_launcher_stub.dart'
    as windows_launcher;

/// Finds and launches applications on the machine running the host.
///
/// macOS and Windows are implemented. The other desktop platforms have no
/// equivalent of a single well-known application directory, and the mobile
/// platforms cannot launch arbitrary apps at all, so they report the gap
/// rather than pretending to work.
abstract final class AppLauncher {
  static bool get supported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  static const _channel = MethodChannel('btlink/icons');

  /// Directories scanned for `.app` bundles, in the order a user would think
  /// of them.
  static const _searchPaths = [
    '/Applications',
    '/System/Applications',
    '/Applications/Utilities',
    '/System/Applications/Utilities',
    '/System/Library/CoreServices/Applications',
  ];

  /// Bundles that live directly under `/System/Library/CoreServices`, mixed
  /// in with hundreds of background agents and helpers a user would never
  /// want on a button — so, unlike [_searchPaths], these are named
  /// explicitly rather than found by scanning the whole directory.
  static const _extraApps = [
    (
      name: 'Finder',
      category: 'Apps',
      path: '/System/Library/CoreServices/Finder.app',
    ),
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
    if (Platform.isWindows) return windows_launcher.listWindowsApps();

    final seen = <String>{};
    final apps = <({String name, String category, String path})>[];

    for (final path in _searchPaths) {
      final directory = Directory(path);
      if (!directory.existsSync()) continue;

      final category =
          path.endsWith('Utilities') ||
              path == '/System/Library/CoreServices/Applications'
          ? 'Utilities'
          : 'Apps';
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

    for (final app in _extraApps) {
      if (!seen.add(app.name)) continue;
      if (!Directory(app.path).existsSync()) continue;
      apps.add(app);
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
    if (Platform.isWindows) return windows_launcher.iconWindows(path, size);
    try {
      // Rendered at twice the size and trimmed back down (see IconTrim):
      // macOS icons carry a transparent margin around their plate, and
      // cropping it away from a larger render keeps the result sharp.
      final png = await _channel.invokeMethod<Uint8List>('icon', {
        'path': path,
        'size': size * 2,
      });
      return png == null ? null : await IconTrim.trimPng(png, size);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Converts a top-down 32bpp BGRA buffer, as Windows' `GetDIBits` fills
  /// it, to the RGBA `dart:ui` expects.
  ///
  /// Many system icons carry no real alpha plane (legacy 32-bit icons that
  /// rely on the mask bitmap instead), which reads back as every pixel's
  /// alpha byte being 0 — indistinguishable, from the buffer alone, from an
  /// icon that is genuinely fully transparent. Since a wholly-invisible
  /// icon is not something this would have been asked to render in the
  /// first place, an all-zero alpha plane is treated as "this icon has no
  /// alpha channel" and forced fully opaque instead.
  ///
  /// A pure function, independent of any live `HICON`, so the
  /// channel/alpha handling can be tested directly — this project's
  /// established pattern for platform-integration decisions (see
  /// CLAUDE.md), and so `win32_app_launcher.dart` (the only real caller)
  /// can reach it despite living outside this file — see that file's own
  /// doc comment for why it has to. Lives here rather than there so it
  /// (and this test coverage) stay platform-independent, even though only
  /// Windows currently calls it.
  static Uint8List bgraToRgba(Uint8List bgra) {
    final rgba = Uint8List(bgra.length);
    var hasAlpha = false;
    for (var i = 3; i < bgra.length; i += 4) {
      if (bgra[i] != 0) {
        hasAlpha = true;
        break;
      }
    }
    for (var i = 0; i + 3 < bgra.length; i += 4) {
      rgba[i] = bgra[i + 2];
      rgba[i + 1] = bgra[i + 1];
      rgba[i + 2] = bgra[i];
      rgba[i + 3] = hasAlpha ? bgra[i + 3] : 255;
    }
    return rgba;
  }

  /// Shared by both platforms' icon rendering: macOS's own channel hands
  /// back a PNG already, but Windows' `HICON` extraction only gets as far
  /// as raw RGBA pixels — this is that last step, encoding those pixels
  /// the same way for either.
  static Future<Uint8List?> encodePng(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Launches [name], returning whether it worked and what to show the user.
  static Future<({bool ok, String message})> open(String name) async {
    if (!supported) {
      return (
        ok: false,
        message: 'Launching apps is only supported on macOS and Windows',
      );
    }
    if (Platform.isWindows) return windows_launcher.openWindows(name);
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
