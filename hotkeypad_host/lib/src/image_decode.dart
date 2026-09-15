import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_svg/flutter_svg.dart' show SvgBytesLoader, vg;

/// Turns arbitrary user-picked bytes into a decoded [Image], shared by
/// everything downstream that needs one before doing its own thing with it
/// — [CustomIconStore] crops the result to a centred square; a background
/// image just caps its resolution. Decoding (including sniffing for and
/// rasterizing SVG source, which [instantiateImageCodec] cannot handle on
/// its own) is identical either way, so it lives here once rather than
/// twice.
abstract final class ImageDecode {
  /// Decodes [bytes] as a raster image, or rasterizes it as SVG source when
  /// it looks like one. Throws on anything that cannot be decoded either
  /// way — callers are expected to wrap this in their own try/catch, since
  /// what "malformed input" should become (null, a fallback, ...) is a
  /// per-caller decision.
  static Future<Image> decodeAny(Uint8List bytes) =>
      _looksLikeSvg(bytes) ? _rasterizeSvg(bytes) : _decodeRaster(bytes);

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
  /// lands at [targetSide] — a vector has no natural pixel size, unlike a
  /// decoded raster frame, so this stands in for one.
  static Future<Image> _rasterizeSvg(
    Uint8List bytes, {
    double targetSide = 512,
  }) async {
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
}
