import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import 'app_launcher.dart';
import 'custom_icon_store.dart';
import 'steam_library.dart';

/// The real, Windows-only implementation behind [AppLauncher]'s
/// `Platform.isWindows` branches — split out so `app_launcher.dart` itself
/// never imports `dart:ffi` or `package:win32` directly, neither of which
/// compiles at all on web (raw native struct/pointer interop, unavailable
/// there regardless of whether this code path would ever run). See
/// `win32_app_launcher_stub.dart` for the web side of the same
/// conditional import.

/// Start Menu folders scanned for `.lnk` shortcuts on Windows: the
/// current user's own Start Menu, then the one every account on the
/// machine shares.
List<String> get _windowsSearchPaths {
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
/// everyday apps.
const _utilityFolders = {
  'windows accessories',
  'windows administrative tools',
  'windows ease of access',
  'windows powershell',
  'windows system',
  'windows tools',
  'administrative tools',
};

/// Whether [name] — a shortcut's filename, minus its `.lnk` extension —
/// is the kind of thing Windows installers scatter next to the app itself
/// in the Start Menu rather than something a user wants on a button.
bool _isNoiseShortcut(String name) {
  final lower = name.toLowerCase();
  return lower.contains('uninstall') ||
      lower.contains('read me') ||
      lower.contains('readme') ||
      lower.contains('license');
}

String _basename(String path) {
  final normalized = path.replaceAll('/', r'\');
  final index = normalized.lastIndexOf(r'\');
  return index == -1 ? normalized : normalized.substring(index + 1);
}

/// Windows equivalent of the macOS branch of [AppLauncher.list]: walks the
/// Start Menu's shortcut folders — recursively, since Windows nests apps a
/// couple of levels deep under a publisher's own folder, unlike the flat
/// `/Applications` layout on macOS — collecting one entry per `.lnk`.
List<({String name, String category, String path})> listWindowsApps() {
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

/// Windows equivalent of the macOS branch of [AppLauncher.icon]: resolves
/// [path] (a `.lnk`, ordinarily) down to the real icon source — see
/// [_resolveIconSource] — and reads that source's icon straight out of its
/// resources at [size], rather than asking the shell for the icon it shows
/// in Explorer. That would be simpler, but it only ever hands back a small
/// system-list icon (blurry once stretched across a deck button) and, for
/// a `.lnk`, one with the shortcut-arrow badge baked in — neither of which
/// belongs on a launcher button. Best-effort like its macOS counterpart:
/// any failure along the way just means no icon.
Future<Uint8List?> iconWindows(String path, int size) async {
  if (path.startsWith('steam://')) return _steamIcon(path);
  try {
    final source = _resolveIconSource(path);
    if (source == null) return null;
    final hIcon = _extractIcon(source.file, source.index, size);
    if (hIcon == null) return null;
    try {
      final bitmap = _iconToRgba(hIcon);
      if (bitmap == null) return null;
      return await AppLauncher.encodePng(
        bitmap.pixels,
        bitmap.width,
        bitmap.height,
      );
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
Future<Uint8List?> _steamIcon(String uri) async {
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
const _libraryCacheCandidates = ['header.jpg', 'library_600x900.jpg', 'logo.png'];

var _comInitialized = false;

/// COM is needed for [win32.IShellLink], and nothing in a Flutter app
/// otherwise guarantees it has been initialized on this thread. `S_FALSE`
/// (already initialized) and `RPC_E_CHANGED_MODE` (initialized with a
/// different concurrency model — still usable) are both fine; only call
/// once, since there is no matching `CoUninitialize` and repeating it
/// would just leak reference counts.
void _ensureComInitialized() {
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
({String file, int index})? _resolveIconSource(String path) {
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
int? _extractIcon(String file, int index, int size) {
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
/// it to [AppLauncher.bgraToRgba]. Returns null on any failure — a missing
/// or unreadable icon is not worth failing the whole lookup over.
({Uint8List pixels, int width, int height})? _iconToRgba(int hIcon) {
  final iconInfo = calloc<win32.ICONINFO>();
  final bitmap = calloc<win32.BITMAP>();
  var hdc = 0;
  try {
    if (win32.GetIconInfo(hIcon, iconInfo) == 0) return null;
    final colorBitmap = iconInfo.ref.hbmColor;
    final maskBitmap = iconInfo.ref.hbmMask;
    try {
      if (colorBitmap == 0) return null;
      if (win32.GetObject(colorBitmap, sizeOf<win32.BITMAP>(), bitmap) == 0) {
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
          pixels: AppLauncher.bgraToRgba(buffer.asTypedList(width * height * 4)),
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

/// Windows equivalent of the macOS branch of [AppLauncher.open]: looks
/// [name] back up against a fresh scan (protocol messages carry only the
/// app's name, not its shortcut path — see host_page.dart's `_appPaths`)
/// and asks the shell to run the shortcut, the same as double-clicking
/// it.
Future<({bool ok, String message})> openWindows(String name) async {
  final match = listWindowsApps().where((app) => app.name == name).firstOrNull;
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
