import 'dart:io';

import 'package:hotkeypad_host/src/config_dir.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves to a real, platform-appropriate directory', () {
    final path = ConfigDir.path;

    expect(path, isNotNull);
    if (Platform.isWindows) {
      // Not `~/.config` — Windows has no `$HOME`/`.config` convention, and
      // `HOME` is normally unset outside a POSIX-emulating shell, which is
      // exactly why every store silently stopped saving before this used
      // `%AppData%` instead.
      expect(path, endsWith(r'\HotkeyPad'));
      expect(path, isNot(contains('.config')));
      expect(path, startsWith(Platform.environment['AppData']!));
    } else {
      expect(path, endsWith('/.config/HotkeyPad'));
    }
  });
}
