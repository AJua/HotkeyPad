import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'protocol.dart';

/// Persists the deck layout on the host.
///
/// The host owns the layout, so this is the only copy that matters; the
/// client caches what it is sent but never edits it.
abstract final class LayoutStore {
  /// Used when there is no filesystem — the web build, which exists only to
  /// develop the editor UI.
  static DeckLayout? _inMemory;

  static File? get _file {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return File('$home/Library/Application Support/BTLink/layout.json');
  }

  static Future<DeckLayout> load() async {
    final file = _file;
    if (file == null) return _inMemory ??= DeckLayout.empty();
    try {
      if (!file.existsSync()) return DeckLayout.empty();
      final decoded = jsonDecode(await file.readAsString());
      return DeckLayout.fromJson(decoded) ?? DeckLayout.empty();
    } catch (_) {
      // A corrupt layout should not stop the service from starting.
      return DeckLayout.empty();
    }
  }

  static Future<void> save(DeckLayout layout) async {
    final file = _file;
    if (file == null) {
      _inMemory = layout;
      return;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(layout.toJson()), flush: true);
    } on FileSystemException {
      // Losing the layout on disk is better than taking the app down.
    }
  }
}
