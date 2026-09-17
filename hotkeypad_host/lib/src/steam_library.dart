import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

/// Installed Steam games, found the same way the Steam client itself does —
/// its own on-disk manifests — rather than a network call.
///
/// Windows only for now: the install path comes from the registry key Steam
/// itself writes on install, and every other store this project reads is
/// keyed by an install path resolved the same platform-specific way (see
/// `config_dir.dart`). macOS Steam installs use the identical manifest
/// format under a fixed `~/Library/Application Support/Steam`, so adding it
/// later is mostly a different [_installPath] — this just has not been
/// exercised against a real macOS Steam install.
abstract final class SteamLibrary {
  static bool get supported => !kIsWeb && Platform.isWindows;

  static String? get _installPath {
    if (!Platform.isWindows) return null;
    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: r'Software\Valve\Steam',
      );
      try {
        final path = key.getValueAsString('SteamPath');
        if (path == null || path.isEmpty) return null;
        return path.replaceAll('/', r'\');
      } finally {
        key.close();
      }
    } catch (_) {
      // Not installed, or the key has moved — either way, no games.
      return null;
    }
  }

  /// Every library folder Steam knows about — the default install plus any
  /// extra drives added under Steam's own Settings > Storage — parsed out
  /// of `steamapps/libraryfolders.vdf`. Falls back to just the install
  /// folder if that file is missing or unparsable, since that is still a
  /// valid (if incomplete) library on its own.
  static List<String> _libraryFolders(String installPath) {
    final vdfFile = File('$installPath\\steamapps\\libraryfolders.vdf');
    try {
      if (!vdfFile.existsSync()) return [installPath];
      final paths = parseLibraryFolderPaths(vdfFile.readAsStringSync());
      return paths.isEmpty ? [installPath] : paths;
    } on FileSystemException {
      return [installPath];
    }
  }

  /// The icon-cache folder Steam keeps per app id — see [parseAppManifest]'s
  /// caller in `app_launcher.dart`, which reads `header.jpg` out of here.
  static String? libraryCacheDir(String appId) {
    final installPath = _installPath;
    if (installPath == null) return null;
    return '$installPath\\appcache\\librarycache\\$appId';
  }

  /// Every installed game, de-duplicated by app id (the same game can be
  /// listed twice if a library folder is registered more than once).
  static List<({String appId, String name})> list() {
    final installPath = _installPath;
    if (installPath == null) return const [];

    final seen = <String>{};
    final games = <({String appId, String name})>[];
    for (final library in _libraryFolders(installPath)) {
      final steamapps = Directory('$library\\steamapps');
      if (!steamapps.existsSync()) continue;
      try {
        for (final entry in steamapps.listSync(followLinks: false)) {
          if (entry is! File) continue;
          final name = _basename(entry.path);
          if (!name.startsWith('appmanifest_') || !name.endsWith('.acf')) {
            continue;
          }
          try {
            final parsed = parseAppManifest(entry.readAsStringSync());
            if (parsed == null || !seen.add(parsed.appId)) continue;
            games.add(parsed);
          } on FileSystemException {
            continue;
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return games;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('/', r'\');
    final index = normalized.lastIndexOf(r'\');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}

/// Extracts every library's on-disk path out of `libraryfolders.vdf`'s raw
/// text.
///
/// Steam's VDF format is a full nested key/value tree, but every library
/// entry's `"path"` line is unambiguous read in isolation, so this looks for
/// just that one key rather than writing a general VDF parser. `\\` is how
/// Steam escapes a single backslash in this format.
@visibleForTesting
List<String> parseLibraryFolderPaths(String vdf) {
  final pattern = RegExp(r'"path"\s*"([^"]*)"');
  return [
    for (final match in pattern.allMatches(vdf))
      match.group(1)!.replaceAll(r'\\', r'\'),
  ];
}

/// Pulls `appid` and `name` out of one `appmanifest_*.acf`'s raw text. Null
/// if either is missing — a manifest mid-write, or a future Steam version
/// that dropped a field this relies on — same "best effort" stance
/// `AppLauncher` takes on anything it reads off disk.
@visibleForTesting
({String appId, String name})? parseAppManifest(String acf) {
  final appId = RegExp(r'"appid"\s*"(\d+)"').firstMatch(acf)?.group(1);
  final name = RegExp(r'"name"\s*"([^"]*)"').firstMatch(acf)?.group(1);
  if (appId == null || name == null || name.isEmpty) return null;
  return (appId: appId, name: name);
}
