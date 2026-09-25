import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'alpha_bounds.dart';
import 'config_dir.dart';
import 'icon_trim.dart';
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

  /// The native picker is macOS-only for now — unlike [AppLauncher], which
  /// has a Windows implementation of its own, this has no equivalent yet.
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
  /// and re-encodes it as a square PNG at [HotkeyPad.iconSize], in one of two
  /// ways depending on what it is:
  ///
  /// * An opaque picture (a photo, a screenshot) has its centred square
  ///   cropped out and fills the whole box — a plain resize would squash a
  ///   non-square source rather than crop it, and deck buttons are square.
  /// * A logo on a transparent background (see
  ///   [AlphaBounds.hasTransparentBackground]) is set on a white rounded
  ///   plate with a soft drop shadow instead, so it sits next to a real
  ///   macOS app icon (Chrome's, say) as one of them rather than as a bare
  ///   cut-out — see [_drawOnPlate].
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
      final rgba = (await source.toByteData(
        format: ImageByteFormat.rawRgba,
      ))?.buffer.asUint8List();
      final logoBounds =
          rgba != null && AlphaBounds.hasTransparentBackground(rgba)
          ? AlphaBounds.opaqueBounds(rgba, source.width, source.height)
          : null;
      const size = HotkeyPad.iconSize;
      // A plated logo is drawn on the full Big Sur template at twice the
      // size, then trimmed the same way a system app icon is (see
      // AppLauncher.icon) — so the two end up with the same plate size and
      // shadow margin, rather than this having its own copy of the numbers.
      final canvasSize = logoBounds != null ? size * 2 : size;
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      if (logoBounds != null) {
        _drawOnPlate(canvas, source, logoBounds, canvasSize.toDouble());
      } else {
        _drawFilled(canvas, source);
      }
      final picture = recorder.endRecording();
      try {
        final output = await picture.toImage(canvasSize, canvasSize);
        try {
          if (logoBounds != null) {
            return await IconTrim.trimImage(output, size);
          }
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

  static void _drawFilled(Canvas canvas, Image source) {
    final side = source.width < source.height ? source.width : source.height;
    final srcRect = Rect.fromLTWH(
      (source.width - side) / 2,
      (source.height - side) / 2,
      side.toDouble(),
      side.toDouble(),
    );
    // No inset: the button already leaves its own margin around the icon
    // box (the grid's cell spacing, plus each app icon's own art), so
    // shrinking the image further on top of that just made a custom icon
    // read as smaller than the built-in ones next to it — the goal is to
    // fill the same box they do, not sit inside it with room to spare.
    const content = HotkeyPad.iconSize * 1.0;
    // Real app icons are drawn as a rounded square, not a sharp one —
    // without this a custom icon's straight corners stood out (and read as
    // bigger) next to the curved ones either side of it.
    const cornerRadius = content * 0.18;
    const destRect = Rect.fromLTWH(0, 0, content, content);
    canvas.clipRRect(
      RRect.fromRectAndRadius(destRect, const Radius.circular(cornerRadius)),
    );
    canvas.drawImageRect(
      source,
      srcRect,
      destRect,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  /// Geometry of Apple's Big Sur app icon template, as fractions of its
  /// 1024-point canvas: an 824-point plate inset 100 on every side, with a
  /// 185.4-point corner radius and a black 30% shadow dropped 10 points
  /// down with a 10-point blur. `NSWorkspace.icon(forFile:)` hands back
  /// real app icons drawn on exactly this grid, so matching it is what makes
  /// a plated logo line up with them edge for edge.
  static const _plateInset = 100 / 1024;
  static const _plateRadius = 185.4 / 1024;
  static const _shadowOffset = 10 / 1024;
  static const _shadowBlur = 10 / 1024;

  /// How much of the plate the logo's longer side may take. A real icon's
  /// artwork stops short of the plate's edge too (Chrome's circle does);
  /// this leaves a similar breathing room so the logo doesn't touch the
  /// rounded corners.
  static const _logoFraction = 0.72;

  /// Draws a white Big Sur-style plate with its drop shadow, then [source]'s
  /// [logoBounds] — the logo with its own transparent margin trimmed off —
  /// scaled to fit inside it without cropping, centred. A wide logo like
  /// Gmail's envelope keeps both of its sides this way, where the opaque
  /// path's centred square would cut them off.
  static void _drawOnPlate(
    Canvas canvas,
    Image source,
    Rect logoBounds,
    double size,
  ) {
    final plate = Rect.fromLTWH(
      size * _plateInset,
      size * _plateInset,
      size * (1 - _plateInset * 2),
      size * (1 - _plateInset * 2),
    );
    final plateShape = RRect.fromRectAndRadius(
      plate,
      Radius.circular(size * _plateRadius),
    );
    canvas.drawRRect(
      plateShape.shift(Offset(0, size * _shadowOffset)),
      Paint()
        ..color = const Color(0x4D000000)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          // MaskFilter takes a sigma, not a blur radius; this is the usual
          // conversion design tools use.
          size * _shadowBlur * 0.57735 + 0.5,
        ),
    );
    canvas.drawRRect(plateShape, Paint()..color = const Color(0xFFFFFFFF));

    final maxSide = plate.width * _logoFraction;
    final scale = logoBounds.width > logoBounds.height
        ? maxSide / logoBounds.width
        : maxSide / logoBounds.height;
    final dest = Rect.fromCenter(
      center: plate.center,
      width: logoBounds.width * scale,
      height: logoBounds.height * scale,
    );
    canvas.drawImageRect(
      source,
      logoBounds,
      dest,
      Paint()..filterQuality = FilterQuality.high,
    );
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
