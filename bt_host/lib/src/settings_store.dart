import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:bt_link_protocol/bt_link_protocol.dart';

/// Host preferences that are not the layout.
///
/// Kept in its own file so writing a layout cannot clobber them and vice
/// versa.
abstract final class SettingsStore {
  /// Used when there is no filesystem — the web build, which exists only to
  /// develop the editor UI.
  static ({DeckTheme theme, bool showLabels})? _inMemory;

  static File? get _file {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return File('$home/.config/BTLink/settings.json');
  }

  static Future<({DeckTheme theme, bool showLabels})> load() async {
    const fallback = (theme: DeckTheme.system, showLabels: true);
    final file = _file;
    if (file == null) return _inMemory ?? fallback;
    try {
      if (!file.existsSync()) return fallback;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return fallback;
      return (
        theme: DeckTheme.fromWire(decoded['theme'] as String?),
        showLabels: decoded['showLabels'] as bool? ?? true,
      );
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> save({
    required DeckTheme theme,
    required bool showLabels,
  }) async {
    final file = _file;
    if (file == null) {
      _inMemory = (theme: theme, showLabels: showLabels);
      return;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'theme': theme.wire, 'showLabels': showLabels}),
        flush: true,
      );
    } on FileSystemException {
      // Losing a preference is better than taking the app down.
    }
  }
}
