import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config_dir.dart';
import 'image_decode.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Custom images the user has picked for a deck button, in place of an app
/// icon or the built-in glyph.
///
/// Stored on disk next to `layout.json` (see `layout_store.dart`), one small
/// PNG per id at [HotkeyPad.iconSize]. That id is what a [DeckItem.customIconId]
/// refers to, and it is also what travels over the link as a [RequestIcon]
/// name: the icon transfer path was already keyed by an opaque string, so a
/// custom image needs nothing new there — see host_page.dart's `_sendIcon`.
abstract final class CustomIconStore {
  static const _channel = MethodChannel('btlink/icons');

  /// The native picker is macOS-only for now, the same gap [AppLauncher]
  /// already reports for launching apps on other platforms.
  static bool get supported => !kIsWeb && Platform.isMacOS;

  static Directory? get _directory {
    final dir = ConfigDir.path;
    if (dir == null) return null;
    return Directory('$dir/custom_icons');
  }

  static String _fileName(String id) => '$id.png';

  /// Opens the native file picker and returns whatever bytes the user
  /// picked, unprocessed. Returns null if the user cancelled or the
  /// platform is unsupported.
  ///
  /// Shared with [BackgroundImageStore], which needs the same native panel
  /// but not the square-crop treatment [pickAndProcess] applies below —
  /// only one method channel call site is worth having, since the picker
  /// itself does not know or care what the picked image is used for.
  static Future<Uint8List?> pickRaw() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('pickImage');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens a native file picker and, if the user picked something, crops it
  /// to a centred square and resizes it to [HotkeyPad.iconSize]. Returns null
  /// if the user cancelled, the platform is unsupported, or the file could
  /// not be decoded as an image — none of which are worth surfacing as an
  /// error, the same stance [AppLauncher.icon] takes on a missing icon.
  static Future<Uint8List?> pickAndProcess() async {
    final picked = await pickRaw();
    if (picked == null) return null;
    return cropToSquarePng(picked);
  }

  /// Decodes [bytes] — a raster image, or SVG source (see [ImageDecode]) —
  /// crops the centred square, and re-encodes at [HotkeyPad.iconSize]. A plain
  /// resize would squash a non-square source rather than crop it, and deck
  /// buttons are square.
  ///
  /// Public, not an implementation detail of [pickAndProcess], so it can be
  /// tested directly against synthetic images without a real file picker.
  static Future<Uint8List?> cropToSquarePng(Uint8List bytes) async {
    final Image source;
    try {
      source = await ImageDecode.decodeAny(bytes);
    } catch (_) {
      return null;
    }
    try {
      final side = source.width < source.height ? source.width : source.height;
      final srcRect = Rect.fromLTWH(
        (source.width - side) / 2,
        (source.height - side) / 2,
        side.toDouble(),
        side.toDouble(),
      );
      const size = HotkeyPad.iconSize;
      // No inset: the button already leaves its own margin around the icon
      // box (the grid's cell spacing, plus each app icon's own art), so
      // shrinking the image further on top of that just made a custom icon
      // read as smaller than the built-in ones next to it — the goal is to
      // fill the same box they do, not sit inside it with room to spare.
      const content = size * 1.0;
      // Real app icons are drawn as a rounded square, not a sharp one —
      // without this a custom icon's straight corners stood out (and read as
      // bigger) next to the curved ones either side of it.
      const cornerRadius = content * 0.18;
      const destRect = Rect.fromLTWH(0, 0, content, content);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.clipRRect(RRect.fromRectAndRadius(destRect, const Radius.circular(cornerRadius)));
      canvas.drawImageRect(
        source,
        srcRect,
        destRect,
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        final output = await picture.toImage(size, size);
        try {
          final data = await output.toByteData(format: ImageByteFormat.png);
          return data?.buffer.asUint8List();
        } finally {
          output.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  /// Saves [png] under a freshly generated id and returns it, or null if it
  /// could not be written.
  static Future<String?> save(Uint8List png) async {
    final directory = _directory;
    if (directory == null) return null;
    final id = 'img_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await directory.create(recursive: true);
      await File(
        '${directory.path}/${_fileName(id)}',
      ).writeAsBytes(png, flush: true);
      return id;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes [png] under [id] exactly as given, unlike [save] which always
  /// mints a fresh one — for restoring a backup bundle, whose layout already
  /// points at specific ids and would need rewriting if new ones were
  /// handed out instead.
  static Future<void> writeAtId(String id, Uint8List png) async {
    final directory = _directory;
    if (directory == null) return;
    try {
      await directory.create(recursive: true);
      await File(
        '${directory.path}/${_fileName(id)}',
      ).writeAsBytes(png, flush: true);
    } on FileSystemException {
      // Losing one restored icon is better than failing the whole import.
    }
  }

  static Future<Uint8List?> read(String id) async {
    final directory = _directory;
    if (directory == null) return null;
    final file = File('${directory.path}/${_fileName(id)}');
    try {
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Best-effort: a file that fails to delete just outlives the button that
  /// used it, which costs disk space rather than correctness.
  static Future<void> delete(String id) async {
    final directory = _directory;
    if (directory == null) return;
    try {
      final file = File('${directory.path}/${_fileName(id)}');
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Ignored, as above.
    }
  }
}
