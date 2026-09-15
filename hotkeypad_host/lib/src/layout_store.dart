import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Persists the deck layout on the host.
///
/// The host owns the layout, so this is the only copy that matters; the
/// client caches what it is sent but never edits it.
abstract final class LayoutStore {
  /// Shown before anything has ever been saved, so a first install is not
  /// a blank grid — a handful of stock Apple apps to start from.
  static final _defaultLayout =
      DeckLayout.fromJson({
        'columns': 3,
        'rows': 2,
        'pages': 1,
        'slots': [
          'app:App Store',
          'app:Finder',
          'app:Safari',
          'app:Maps',
          'app:Mail',
          'app:Calendar',
        ],
      })!;

  /// Used when there is no filesystem — the web build, which exists only to
  /// develop the editor UI.
  static DeckLayout? _inMemory;

  static File? get _file {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return File('$home/.config/HotkeyPad/layout.json');
  }

  static Future<DeckLayout> load() async {
    final file = _file;
    if (file == null) return _inMemory ??= _defaultLayout;
    try {
      if (!file.existsSync()) return _defaultLayout;
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
