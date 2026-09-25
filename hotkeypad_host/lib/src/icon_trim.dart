import 'dart:typed_data';
import 'dart:ui';

import 'alpha_bounds.dart';

/// Crops an icon down to its plate and shadow (see [AlphaBounds.plateCrop])
/// and renders the result at a given pixel size. Shared by system app icons
/// and plated custom logos, so the two come out the same size next to each
/// other on a deck.
abstract final class IconTrim {
  /// Decodes [png], trims it, and re-encodes at [size]. When there is
  /// nothing to trim the image is still scaled to [size], so callers can
  /// always ask for a larger render than they need and rely on getting
  /// [size] back. Returns [png] unchanged if it cannot be decoded.
  static Future<Uint8List> trimPng(Uint8List png, int size) async {
    final Image source;
    try {
      final codec = await instantiateImageCodec(png);
      source = (await codec.getNextFrame()).image;
    } catch (_) {
      return png;
    }
    try {
      return await trimImage(source, size) ?? png;
    } finally {
      source.dispose();
    }
  }

  /// [trimPng] for an already-decoded [source]; does not dispose it.
  static Future<Uint8List?> trimImage(Image source, int size) async {
    final rgba = (await source.toByteData(
      format: ImageByteFormat.rawRgba,
    ))?.buffer.asUint8List();
    final crop =
        (rgba == null
            ? null
            : AlphaBounds.plateCrop(rgba, source.width, source.height)) ??
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble());
    final recorder = PictureRecorder();
    Canvas(recorder).drawImageRect(
      source,
      crop,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
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
  }
}
