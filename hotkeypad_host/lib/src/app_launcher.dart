import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' as win32;

import 'custom_icon_store.dart';
import 'steam_library.dart';

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

  /// Start Menu folders scanned for `.lnk` shortcuts on Windows: the
  /// current user's own Start Menu, then the one every account on the
  /// machine shares — the closest Windows equivalent of [_searchPaths].
  static List<String> get _windowsSearchPaths {
    final appData = Platform.environment['AppData'];
    final programData = Platform.environment['ProgramData'];
    return [
      if (appData != null && appData.isNotEmpty)
        '$appData\\Microsoft\\Windows\\Start Menu\\Programs',
      if (programData != null && programData.isNotEmpty)
        '$programData\\Microsoft\\Windows\\Start Menu\\Programs',
    ];
  }

  /// Start Menu subfolders that hold tool-like shortcuts rather than
  /// everyday apps — the closest Windows equivalent of the Applications/
  /// Utilities split [_searchPaths] draws by directory on macOS.
  static const _utilityFolders = {
    'windows accessories',
    'windows administrative tools',
    'windows ease of access',
    'windows powershell',
    'windows system',
    'windows tools',
    'administrative tools',
  };

  /// Whether [name] — a shortcut's filename, minus its `.lnk` extension —
  /// is the kind of thing Windows installers scatter next to the app
  /// itself in the Start Menu rather than something a user wants on a
  /// button.
  static bool _isNoiseShortcut(String name) {
    final lower = name.toLowerCase();
    return lower.contains('uninstall') ||
        lower.contains('read me') ||
        lower.contains('readme') ||
        lower.contains('license');
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('/', r'\');
    final index = normalized.lastIndexOf(r'\');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  /// Windows equivalent of the macOS branch of [list]: walks the Start
  /// Menu's shortcut folders — recursively, since Windows nests apps a
  /// couple of levels deep under a publisher's own folder, unlike the flat
  /// `/Applications` layout on macOS — collecting one entry per `.lnk`.
  static List<({String name, String category, String path})>
  _listWindows() {
    final seen = <String>{};
    final apps = <({String name, String category, String path})>[];

    // Ahead of the Start Menu scan: a Steam game that also happens to have
    // its own shortcut there is still better launched through Steam (which
    // keeps it updated and honors Steam Cloud) than through whatever that
    // shortcut points at directly, and `seen` makes sure it is not listed
    // twice.
    for (final game in SteamLibrary.list()) {
      if (!seen.add(game.name)) continue;
      apps.add((
        name: game.name,
        category: 'Games',
        path: 'steam://rungameid/${game.appId}',
      ));
    }

    for (final root in _windowsSearchPaths) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      try {
        for (final entry in directory.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entry is! File || !entry.path.toLowerCase().endsWith('.lnk')) {
            continue;
          }
          final base = _basename(entry.path);
          final name = base.substring(0, base.length - 4);
          if (name.isEmpty || _isNoiseShortcut(name) || !seen.add(name)) {
            continue;
          }
          final parent = _basename(
            entry.path.substring(0, entry.path.length - base.length - 1),
          ).toLowerCase();
          apps.add((
            name: name,
            category: _utilityFolders.contains(parent) ? 'Utilities' : 'Apps',
            path: entry.path,
          ));
        }
      } on FileSystemException {
        // An unreadable directory is not worth failing the whole catalogue.
        continue;
      }
    }

    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  static Future<List<({String name, String category, String path})>>
  list() async {
    if (kIsWeb) {
      return [
        for (final name in _webSamples)
          (name: name, category: 'Apps', path: '/Applications/$name.app'),
      ];
    }
    if (!supported) return const [];
    if (Platform.isWindows) return _listWindows();

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
    if (Platform.isWindows) return _iconWindows(path, size);
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

  /// Windows equivalent of the macOS branch of [icon]: resolves [path] (a
  /// `.lnk`, ordinarily) down to the real icon source — see
  /// [_resolveIconSource] — and reads that source's icon straight out of its
  /// resources at [size], rather than asking the shell for the icon it shows
  /// in Explorer. That would be simpler, but it only ever hands back a
  /// small system-list icon (blurry once stretched across a deck button)
  /// and, for a `.lnk`, one with the shortcut-arrow badge baked in — neither
  /// of which belongs on a launcher button. Best-effort like its macOS
  /// counterpart: any failure along the way just means no icon.
  static Future<Uint8List?> _iconWindows(String path, int size) async {
    if (path.startsWith('steam://')) return _steamIcon(path);
    try {
      final source = _resolveIconSource(path);
      if (source == null) return null;
      final hIcon = _extractIcon(source.file, source.index, size);
      if (hIcon == null) return null;
      try {
        final bitmap = _iconToRgba(hIcon);
        if (bitmap == null) return null;
        return await _encodePng(bitmap.pixels, bitmap.width, bitmap.height);
      } finally {
        win32.DestroyIcon(hIcon);
      }
    } catch (_) {
      return null;
    }
  }

  /// A Steam game has no icon resource of its own to extract — `steam://`
  /// is a URI, not a file — so this reads whatever box-art image Steam has
  /// already cached locally for its own library views instead, cropped to a
  /// square the same way a user-picked image is (see
  /// [CustomIconStore.cropToSquarePng]). Steam does not cache a true square
  /// icon locally — only fetching one from its CDN would, which is a
  /// network call this project does not make for an app icon — so the crop
  /// loses whatever the source image's own edges show, the same tradeoff a
  /// Steam library grid view makes with the same images.
  ///
  /// Steam only caches an image once its own UI has actually shown that
  /// view for a given game, so no single filename is guaranteed to exist;
  /// [_libraryCacheCandidates] are tried in the order most likely to still
  /// look right once forced square.
  static Future<Uint8List?> _steamIcon(String uri) async {
    final appId = uri.split('/').last;
    final cacheDir = SteamLibrary.libraryCacheDir(appId);
    if (cacheDir == null) return null;
    for (final name in _libraryCacheCandidates) {
      final file = File('$cacheDir\\$name');
      try {
        if (!file.existsSync()) continue;
        final cropped = await CustomIconStore.cropToSquarePng(
          await file.readAsBytes(),
        );
        if (cropped != null) return cropped;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  /// Widescreen box art first — the closest thing to a poster, so square
  /// crop loses the least — then the portrait grid image (already close to
  /// square), and only then the logo, which is text on a transparent
  /// background and reads worst forced into a square.
  static const _libraryCacheCandidates = [
    'header.jpg',
    'library_600x900.jpg',
    'logo.png',
  ];

  static bool _comInitialized = false;

  /// COM is needed for [IShellLink], and nothing in a Flutter app otherwise
  /// guarantees it has been initialized on this thread. `S_FALSE` (already
  /// initialized) and `RPC_E_CHANGED_MODE` (initialized with a different
  /// concurrency model — still usable) are both fine; only call once, since
  /// there is no matching `CoUninitialize` and repeating it would just leak
  /// reference counts.
  static void _ensureComInitialized() {
    if (_comInitialized) return;
    win32.CoInitializeEx(nullptr, win32.COINIT_APARTMENTTHREADED);
    _comInitialized = true;
  }

  /// Finds the file (and, for a multi-icon file, the index within it) that
  /// actually holds [path]'s icon.
  ///
  /// A `.lnk` can point its icon at something other than its target — a
  /// `.ico` file, or an index into `shell32.dll` — the same way Explorer
  /// resolves it, via [win32.IShellLink.getIconLocation]. Only when a
  /// shortcut has no such override does this fall back to its target
  /// ([win32.IShellLink.getPath]). Anything that is not a `.lnk` is assumed
  /// to already be an icon source in its own right.
  static ({String file, int index})? _resolveIconSource(String path) {
    if (!path.toLowerCase().endsWith('.lnk')) {
      return (file: path, index: 0);
    }

    _ensureComInitialized();
    final shellLink = win32.ShellLink.createInstance();
    final persistFile = win32.IPersistFile.from(shellLink);
    final pathPtr = path.toNativeUtf16();
    try {
      if (win32.FAILED(persistFile.load(pathPtr, win32.STGM_READ))) {
        return null;
      }

      final iconPathBuf = win32.wsalloc(win32.MAX_PATH);
      final iconIndexPtr = calloc<Int32>();
      try {
        final hr = shellLink.getIconLocation(
          iconPathBuf,
          win32.MAX_PATH,
          iconIndexPtr,
        );
        final iconPath = iconPathBuf.toDartString();
        if (win32.SUCCEEDED(hr) && iconPath.isNotEmpty) {
          return (file: iconPath, index: iconIndexPtr.value);
        }
      } finally {
        calloc.free(iconPathBuf);
        calloc.free(iconIndexPtr);
      }

      final targetBuf = win32.wsalloc(win32.MAX_PATH);
      try {
        final hr = shellLink.getPath(targetBuf, win32.MAX_PATH, nullptr, 0);
        final target = targetBuf.toDartString();
        if (win32.SUCCEEDED(hr) && target.isNotEmpty) {
          return (file: target, index: 0);
        }
        return null;
      } finally {
        calloc.free(targetBuf);
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Reads icon number [index] out of [file]'s icon resources, rendered at
  /// [size] square. Unlike [win32.ExtractIconEx] (fixed at the system's
  /// small/large sizes), [win32.PrivateExtractIcons] renders at whatever
  /// size is asked for — documented public API despite the name.
  static int? _extractIcon(String file, int index, int size) {
    final filePtr = file.toNativeUtf16();
    final hIconBuf = calloc<IntPtr>();
    try {
      final extracted = win32.PrivateExtractIcons(
        filePtr,
        index,
        size,
        size,
        hIconBuf,
        nullptr,
        1,
        0,
      );
      if (extracted == 0 || extracted == 0xFFFFFFFF) return null;
      final hIcon = hIconBuf.value;
      return hIcon == 0 ? null : hIcon;
    } finally {
      calloc.free(hIconBuf);
      calloc.free(filePtr);
    }
  }

  /// Reads an `HICON`'s colour plane into a top-down 32bpp buffer and hands
  /// it to [bgraToRgba]. Returns null on any failure — a missing or
  /// unreadable icon is not worth failing the whole lookup over.
  static ({Uint8List pixels, int width, int height})? _iconToRgba(int hIcon) {
    final iconInfo = calloc<win32.ICONINFO>();
    final bitmap = calloc<win32.BITMAP>();
    var hdc = 0;
    try {
      if (win32.GetIconInfo(hIcon, iconInfo) == 0) return null;
      final colorBitmap = iconInfo.ref.hbmColor;
      final maskBitmap = iconInfo.ref.hbmMask;
      try {
        if (colorBitmap == 0) return null;
        if (win32.GetObject(colorBitmap, sizeOf<win32.BITMAP>(), bitmap) ==
            0) {
          return null;
        }
        final width = bitmap.ref.bmWidth;
        final height = bitmap.ref.bmHeight;
        if (width <= 0 || height <= 0) return null;

        hdc = win32.GetDC(0);
        final bmi = calloc<win32.BITMAPINFO>();
        final buffer = calloc<Uint8>(width * height * 4);
        try {
          bmi.ref.bmiHeader
            ..biSize = sizeOf<win32.BITMAPINFOHEADER>()
            ..biWidth = width
            ..biHeight = -height
            ..biPlanes = 1
            ..biBitCount = 32
            ..biCompression = win32.BI_RGB;
          final copied = win32.GetDIBits(
            hdc,
            colorBitmap,
            0,
            height,
            buffer.cast(),
            bmi,
            win32.DIB_RGB_COLORS,
          );
          if (copied == 0) return null;
          return (
            pixels: bgraToRgba(buffer.asTypedList(width * height * 4)),
            width: width,
            height: height,
          );
        } finally {
          calloc.free(buffer);
          calloc.free(bmi);
        }
      } finally {
        if (colorBitmap != 0) win32.DeleteObject(colorBitmap);
        if (maskBitmap != 0) win32.DeleteObject(maskBitmap);
      }
    } finally {
      if (hdc != 0) win32.ReleaseDC(0, hdc);
      calloc.free(bitmap);
      calloc.free(iconInfo);
    }
  }

  /// Converts a top-down 32bpp BGRA buffer, as [GetDIBits] fills it, to the
  /// RGBA `dart:ui` expects.
  ///
  /// Many system icons carry no real alpha plane (legacy 32-bit icons that
  /// rely on the mask bitmap instead), which reads back as every pixel's
  /// alpha byte being 0 — indistinguishable, from the buffer alone, from an
  /// icon that is genuinely fully transparent. Since a wholly-invisible
  /// icon is not something [_iconToRgba] would have been asked to render in
  /// the first place, an all-zero alpha plane is treated as "this icon has
  /// no alpha channel" and forced fully opaque instead.
  ///
  /// Pulled out as a pure function, independent of any live `HICON`, so the
  /// channel/alpha handling can be tested directly — this project's
  /// established pattern for platform-integration decisions (see
  /// CLAUDE.md).
  @visibleForTesting
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

  static Future<Uint8List?> _encodePng(
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
    if (Platform.isWindows) return _openWindows(name);
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

  /// Windows equivalent of the macOS branch of [open]: looks [name] back up
  /// against a fresh scan (protocol messages carry only the app's name, not
  /// its shortcut path — see host_page.dart's `_appPaths`) and asks the
  /// shell to run the shortcut, the same as double-clicking it.
  static Future<({bool ok, String message})> _openWindows(String name) async {
    final match = _listWindows()
        .where((app) => app.name == name)
        .firstOrNull;
    if (match == null) {
      return (ok: false, message: 'Could not find $name');
    }
    final verbPtr = 'open'.toNativeUtf16();
    final pathPtr = match.path.toNativeUtf16();
    try {
      final result = win32.ShellExecute(
        0,
        verbPtr,
        pathPtr,
        nullptr,
        nullptr,
        win32.SW_SHOWNORMAL,
      );
      // Anything above 32 means success — the convention ShellExecute
      // inherited from 16-bit Windows and never changed.
      return result > 32
          ? (ok: true, message: 'Opened $name')
          : (ok: false, message: 'Could not open $name (code $result)');
    } finally {
      calloc.free(pathPtr);
      calloc.free(verbPtr);
    }
  }
}
