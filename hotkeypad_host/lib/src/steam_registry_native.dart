import 'package:win32_registry/win32_registry.dart';

/// The real, Windows-only implementation of [SteamLibrary]'s registry
/// lookup — split out so `steam_library.dart` itself never imports
/// `package:win32_registry` directly, which fails to compile at all on
/// web (it wraps native Win32 registry calls via `dart:ffi`, unavailable
/// there regardless of whether this code path would ever run). See
/// `steam_registry_stub.dart` for the web side of the same conditional
/// import.
String? steamInstallPathFromRegistry() {
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
