import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'protocol.dart';

/// Host preferences that are not the layout.
///
/// Kept in its own file so writing a layout cannot clobber them and vice
/// versa.
abstract final class SettingsStore {
  /// Used when there is no filesystem — the web build, which exists only to
  /// develop the editor UI.
  static DeckTheme? _inMemory;

  static File? get _file {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return File('$home/Library/Application Support/BTLink/settings.json');
  }

  static Future<DeckTheme> loadTheme() async {
    final file = _file;
    if (file == null) return _inMemory ?? DeckTheme.system;
    try {
      if (!file.existsSync()) return DeckTheme.system;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return DeckTheme.system;
      return DeckTheme.fromWire(decoded['theme'] as String?);
    } catch (_) {
      return DeckTheme.system;
    }
  }

  static Future<void> saveTheme(DeckTheme theme) async {
    final file = _file;
    if (file == null) {
      _inMemory = theme;
      return;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'theme': theme.wire}), flush: true);
    } on FileSystemException {
      // Losing a preference is better than taking the app down.
    }
  }
}
