import 'dart:typed_data';

/// The web side of `app_launcher.dart`'s conditional import — see
/// `win32_app_launcher.dart`'s own doc comment. None of these are ever
/// actually called: [AppLauncher.supported] is false on every platform
/// this stub is selected for, and `list`/`icon`/`open` all check that
/// before reaching a `Platform.isWindows` branch — but the references
/// still have to resolve at compile time.
List<({String name, String category, String path})> listWindowsApps() =>
    const [];

Future<Uint8List?> iconWindows(String path, int size) async => null;

Future<({bool ok, String message})> openWindows(String name) async =>
    (ok: false, message: 'Launching apps is only supported on macOS and Windows');
