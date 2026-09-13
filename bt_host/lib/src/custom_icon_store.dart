import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgBytesLoader, vg;

import 'package:bt_link_protocol/bt_link_protocol.dart';

/// Custom images the user has picked for a deck button, in place of an app
/// icon or the built-in glyph.
///
/// Stored on disk next to `layout.json` (see `layout_store.dart`), one small
/// PNG per id at [BtLink.iconSize]. That id is what a [DeckItem.customIconId]
/// refers to, and it is also what travels over the link as a [RequestIcon]
/// name: the icon transfer path was already keyed by an opaque string, so a
/// custom image needs nothing new there — see host_page.dart's `_sendIcon`.
abstract final class CustomIconStore {
  static const _channel = MethodChannel('btlink/icons');

  /// The native picker is macOS-only for now, the same gap [AppLauncher]
  /// already reports for launching apps on other platforms.
  static bool get supported => !kIsWeb && Platform.isMacOS;

  static Directory? get _directory {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return Directory('$home/.config/BTLink/custom_icons');
  }

  static String _fileName(String id) => '$id.png';

  /// Opens a native file picker and, if the user picked something, crops it
  /// to a centred square and resizes it to [BtLink.iconSize]. Returns null
  /// if the user cancelled, the platform is unsupported, or the file could
  /// not be decoded as an image — none of which are worth surfacing as an
  /// error, the same stance [AppLauncher.icon] takes on a missing icon.
  static Future<Uint8List?> pickAndProcess() async {
    if (!supported) return null;
    final Uint8List? picked;
    try {
      picked = await _channel.invokeMethod<Uint8List>('pickImage');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    if (picked == null) return null;
    return cropToSquarePng(picked);
  }

  /// Decodes [bytes] — a raster image, or SVG source, sniffed by
  /// [_looksLikeSvg] since that's the one format [instantiateImageCodec]
  /// cannot handle on its own — crops the centred square, and re-encodes at
  /// [BtLink.iconSize]. A plain resize would squash a non-square source
  /// rather than crop it, and deck buttons are square.
  ///
  /// Public, not an implementation detail of [pickAndProcess], so it can be
  /// tested directly against synthetic images without a real file picker.
  static Future<Uint8List?> cropToSquarePng(Uint8List bytes) async {
    final Image source;
    try {
      source = _looksLikeSvg(bytes)
          ? await _rasterizeSvg(bytes)
          : await _decodeRaster(bytes);
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
      const size = BtLink.iconSize;
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

  /// Sniffs [bytes] for SVG source rather than trying to parse it properly —
  /// a real parse only to reject non-SVG input would be wasted work, since
  /// [_decodeRaster] already handles every other format this app needs to
  /// accept. Looks at a small prefix so a large photo isn't fully decoded as
  /// text just to rule it out.
  static bool _looksLikeSvg(Uint8List bytes) {
    final prefixLength = bytes.length < 2048 ? bytes.length : 2048;
    final String prefix;
    try {
      prefix = utf8.decode(bytes.sublist(0, prefixLength), allowMalformed: true);
    } catch (_) {
      return false;
    }
    return prefix.toLowerCase().contains('<svg');
  }

  static Future<Image> _decodeRaster(Uint8List bytes) async {
    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Rasterizes SVG source into an [Image], scaled so its larger dimension
  /// lands at a comfortable working resolution — [cropToSquarePng] then
  /// crops and resizes it exactly like any other decoded image, so a vector
  /// icon goes through the same centred-square treatment as a photo.
  ///
  /// A vector has no natural pixel size, unlike a raster frame; [targetSide]
  /// stands in for one, chosen well above [BtLink.iconSize] so the crop
  /// below still has real detail to work with.
  static Future<Image> _rasterizeSvg(Uint8List bytes) async {
    const targetSide = 512.0;
    final pictureInfo = await vg.loadPicture(SvgBytesLoader(bytes), null);
    try {
      final svgSize = pictureInfo.size;
      final side = svgSize.width > svgSize.height
          ? svgSize.width
          : svgSize.height;
      // A missing width/height/viewBox leaves size at zero; fall back to
      // drawing it at face value rather than dividing by zero.
      final scale = side > 0 ? targetSide / side : 1.0;
      final width = (svgSize.width * scale).round().clamp(1, 4096);
      final height = (svgSize.height * scale).round().clamp(1, 4096);

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale);
      canvas.drawPicture(pictureInfo.picture);
      final scaledPicture = recorder.endRecording();
      try {
        return await scaledPicture.toImage(width, height);
      } finally {
        scaledPicture.dispose();
      }
    } finally {
      pictureInfo.picture.dispose();
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
