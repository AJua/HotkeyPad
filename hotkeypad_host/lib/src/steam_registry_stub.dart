/// The web side of `steam_library.dart`'s conditional import — see
/// `steam_registry_native.dart`'s own doc comment. Never actually called:
/// `SteamLibrary`'s own `Platform.isWindows` guard is false on every
/// platform this stub is selected for, but the reference still has to
/// resolve at compile time.
String? steamInstallPathFromRegistry() => null;
