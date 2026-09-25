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
  /// and re-encodes it as a square PNG at [HotkeyPad.iconSize], styled as a
  /// Big Sur app icon — a rounded plate with a soft drop shadow — so it sits
  /// next to a real macOS app icon (Chrome's, say) as one of them. What goes
  /// on the plate depends on the source:
  ///
  /// * A logo on a transparent background (see
  ///   [AlphaBounds.hasTransparentBackground]) is placed whole on a white
  ///   plate — see [_drawLogoOnPlate].
  /// * An opaque picture (a photo, a site's apple-touch-icon) becomes the
  ///   plate itself: its centred square is cropped out and clipped to the
  ///   plate's shape — see [_drawPictureAsPlate]. A plain resize would
  ///   squash a non-square source rather than crop it.
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
      // Drawn on the full Big Sur template at twice the size, then trimmed
      // the same way a system app icon is (see AppLauncher.icon) — so the
      // two end up with the same plate size and shadow margin, rather than
      // this having its own copy of the numbers.
      const size = HotkeyPad.iconSize;
      const canvasSize = size * 2;
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      if (logoBounds != null) {
        _drawLogoOnPlate(canvas, source, logoBounds, canvasSize.toDouble());
      } else {
        _drawPictureAsPlate(canvas, source, canvasSize.toDouble());
      }
      final picture = recorder.endRecording();
      try {
        final output = await picture.toImage(canvasSize, canvasSize);
        try {
          return await IconTrim.trimImage(output, size, inset: _plateTrimInset);
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

  /// Geometry of Apple's Big Sur app icon template, as fractions of its
  /// 1024-point canvas: an 824-point plate inset 100 on every side, with a
  /// 185.4-point corner radius and a black 30% shadow dropped 10 points
  /// down with a 10-point blur. `NSWorkspace.icon(forFile:)` hands back
  /// real app icons drawn on exactly this grid, so matching it is what makes
  /// a custom icon line up with them edge for edge.
  static const _plateInset = 100 / 1024;
  static const _plateRadius = 185.4 / 1024;
  static const _shadowOffset = 10 / 1024;
  static const _shadowBlur = 10 / 1024;

  /// Extra margin per side after trimming, in output pixels. This plate's
  /// shadow is shorter than the one baked into real macOS icons, so trimming
  /// it leaves a narrower margin and the plate came out wider than Chrome's
  /// (~119px at a 128px icon). Tuned by eye on a real deck to 1.5px at
  /// 128 — a 118px plate, a touch smaller than Chrome's, which read as
  /// right next to it — and scaled with the icon size from there.
  static const _plateTrimInset = HotkeyPad.iconSize * 1.5 / 128;

  /// How much of the plate the logo's longer side may take. A real icon's
  /// artwork stops short of the plate's edge too (Chrome's circle does);
  /// this leaves a similar breathing room so the logo doesn't touch the
  /// rounded corners.
  static const _logoFraction = 0.72;

  /// The rounded plate of the Big Sur template on a [size]-point canvas.
  static RRect _plateShape(double size) => RRect.fromRectAndRadius(
    Rect.fromLTWH(
      size * _plateInset,
      size * _plateInset,
      size * (1 - _plateInset * 2),
      size * (1 - _plateInset * 2),
    ),
    Radius.circular(size * _plateRadius),
  );

  static void _drawPlateShadow(Canvas canvas, RRect plate, double size) {
    canvas.drawRRect(
      plate.shift(Offset(0, size * _shadowOffset)),
      Paint()
        ..color = const Color(0x4D000000)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          // MaskFilter takes a sigma, not a blur radius; this is the usual
          // conversion design tools use.
          size * _shadowBlur * 0.57735 + 0.5,
        ),
    );
  }

  /// Draws a white Big Sur-style plate with its drop shadow, then [source]'s
  /// [logoBounds] — the logo with its own transparent margin trimmed off —
  /// scaled to fit inside it without cropping, centred. A wide logo like
  /// Gmail's envelope keeps both of its sides this way, where
  /// [_drawPictureAsPlate]'s centred square would cut them off.
  static void _drawLogoOnPlate(
    Canvas canvas,
    Image source,
    Rect logoBounds,
    double size,
  ) {
    final plateShape = _plateShape(size);
    final plate = plateShape.outerRect;
    _drawPlateShadow(canvas, plateShape, size);
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

  /// Draws the plate's drop shadow, then [source]'s centred square clipped
  /// to the plate's shape — the picture is the plate, the way an app icon's
  /// artwork is.
  static void _drawPictureAsPlate(Canvas canvas, Image source, double size) {
    final side = source.width < source.height ? source.width : source.height;
    final srcRect = Rect.fromLTWH(
      (source.width - side) / 2,
      (source.height - side) / 2,
      side.toDouble(),
      side.toDouble(),
    );
    final plateShape = _plateShape(size);
    _drawPlateShadow(canvas, plateShape, size);
    canvas.save();
    canvas.clipRRect(plateShape);
    canvas.drawImageRect(
      source,
      srcRect,
      plateShape.outerRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
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
