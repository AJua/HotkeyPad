import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Everything this store persists, bundled together because [load] and
/// [save] only ever deal in the whole set at once — every field here rides
/// the same [SetAppearance] message to the client (see host_page.dart's
/// `_broadcastAppearance`).
typedef Appearance = ({
  DeckTheme theme,
  bool showLabels,
  bool showAppBar,
  bool showPageDots,
  String? backgroundImageId,
  double backgroundOpacity,
  BackgroundFit backgroundFit,
});

/// Host preferences that are not the layout.
///
/// Kept in its own file so writing a layout cannot clobber them and vice
/// versa.
abstract final class SettingsStore {
  /// Used when there is no filesystem — the web build, which exists only to
  /// develop the editor UI.
  static Appearance? _inMemory;

  static File? get _file {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return File('$home/.config/HotkeyPad/settings.json');
  }

  static const _fallback = (
    theme: DeckTheme.system,
    showLabels: true,
    showAppBar: true,
    showPageDots: true,
    backgroundImageId: null,
    backgroundOpacity: 1.0,
    backgroundFit: BackgroundFit.cover,
  );

  static Future<Appearance> load() async {
    final file = _file;
    if (file == null) return _inMemory ?? _fallback;
    try {
      if (!file.existsSync()) return _fallback;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return _fallback;
      return (
        theme: DeckTheme.fromWire(decoded['theme'] as String?),
        showLabels: decoded['showLabels'] as bool? ?? true,
        showAppBar: decoded['showAppBar'] as bool? ?? true,
        showPageDots: decoded['showPageDots'] as bool? ?? true,
        backgroundImageId: decoded['backgroundImageId'] as String?,
        backgroundOpacity:
            (decoded['backgroundOpacity'] as num?)?.toDouble() ?? 1.0,
        backgroundFit: BackgroundFit.fromWire(
          decoded['backgroundFit'] as String?,
        ),
      );
    } catch (_) {
      return _fallback;
    }
  }

  static Future<void> save({
    required DeckTheme theme,
    required bool showLabels,
    bool showAppBar = true,
    bool showPageDots = true,
    String? backgroundImageId,
    double backgroundOpacity = 1.0,
    BackgroundFit backgroundFit = BackgroundFit.cover,
  }) async {
    final appearance = (
      theme: theme,
      showLabels: showLabels,
      showAppBar: showAppBar,
      showPageDots: showPageDots,
      backgroundImageId: backgroundImageId,
      backgroundOpacity: backgroundOpacity,
      backgroundFit: backgroundFit,
    );
    final file = _file;
    if (file == null) {
      _inMemory = appearance;
      return;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'theme': theme.wire,
          'showLabels': showLabels,
          'showAppBar': showAppBar,
          'showPageDots': showPageDots,
          // Written even when null — this is a settings file, not the wire
          // protocol, so there is no older-reader compatibility reason to
          // omit the key rather than store an explicit null.
          'backgroundImageId': backgroundImageId,
          'backgroundOpacity': backgroundOpacity,
          'backgroundFit': backgroundFit.wire,
        }),
        flush: true,
      );
    } on FileSystemException {
      // Losing a preference is better than taking the app down.
    }
  }
}
