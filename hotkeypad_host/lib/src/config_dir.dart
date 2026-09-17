import 'dart:io';

import 'package:flutter/foundation.dart';

/// Where HotkeyPad keeps its on-disk state — one folder shared by every
/// store (`LayoutStore`, `SettingsStore`, `CustomIconStore`, ...), each of
/// which just picks its own file or subfolder underneath it.
///
/// macOS and Linux get the XDG convention, `~/.config/HotkeyPad`. Windows has
/// no `$HOME`/`.config` equivalent — `HOME` is normally unset there outside a
/// POSIX-emulating shell like Git Bash, which is exactly why every store
/// silently stopped saving when this code first shipped Windows support
/// reusing the macOS path — so it uses the Windows-native `%AppData%\HotkeyPad`
/// instead.
abstract final class ConfigDir {
  static String? get path {
    if (kIsWeb) return null;
    if (Platform.isWindows) {
      final appData = Platform.environment['AppData'];
      if (appData == null || appData.isEmpty) return null;
      return '$appData\\HotkeyPad';
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home/.config/HotkeyPad';
  }
}
