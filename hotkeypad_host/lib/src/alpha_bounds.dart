import 'dart:typed_data';
import 'dart:ui';

/// Pure decisions about an image's alpha channel, taken over raw RGBA bytes
/// (as [Image.toByteData] with [ImageByteFormat.rawRgba] returns them) so
/// they can be tested against hand-built pixel buffers without decoding
/// anything.
abstract final class AlphaBounds {
  /// Whether [rgba] reads as a logo on a transparent background rather than
  /// an opaque picture. A photo can still carry a stray anti-aliased pixel
  /// or two below full alpha, so this asks for a meaningful share of the
  /// image to be see-through — [minFraction] of it — not just any pixel.
  static bool hasTransparentBackground(
    Uint8List rgba, {
    double minFraction = 0.05,
  }) {
    final pixels = rgba.length ~/ 4;
    if (pixels == 0) return false;
    var transparent = 0;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] < 250) transparent++;
    }
    return transparent / pixels >= minFraction;
  }

  /// The smallest rect, in pixels, holding every pixel whose alpha is at
  /// least [threshold] — the logo itself, without the empty margin a
  /// downloaded PNG or SVG tends to carry around it. Right and bottom are
  /// exclusive, the same as [Rect.fromLTRB] over pixel edges. Null when
  /// nothing reaches the threshold at all.
  static Rect? opaqueBounds(
    Uint8List rgba,
    int width,
    int height, {
    int threshold = 16,
  }) {
    var left = width, top = height, right = -1, bottom = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width * 4;
      for (var x = 0; x < width; x++) {
        if (rgba[row + x * 4 + 3] < threshold) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    if (right < 0) return null;
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right + 1.0,
      bottom + 1.0,
    );
  }

  /// The square to crop [rgba] to so its artwork fills the box without
  /// losing the drop shadow drawn around it — the job macOS's own Big
  /// Sur-style icons need, since they bake in a transparent margin (about
  /// 10% of each edge) around a rounded plate and its shadow.
  ///
  /// The plate is found at [plateThreshold], high enough that the faint
  /// shadow falls outside it; the shadow at [shadowThreshold], low enough to
  /// catch nearly all of it. The square stays centred on the plate and
  /// reaches out as far as the shadow does on its farthest side, on every
  /// side — a shadow falls mostly downward, and cropping to its own lopsided
  /// bounds would push the plate off centre.
  ///
  /// Null when there is nothing to trim: no plate at all, or one whose
  /// shadow already reaches the image's edges, as a full-bleed legacy icon
  /// does.
  static Rect? plateCrop(
    Uint8List rgba,
    int width,
    int height, {
    int plateThreshold = 128,
    int shadowThreshold = 4,
  }) {
    final plate = opaqueBounds(rgba, width, height, threshold: plateThreshold);
    final shadow = opaqueBounds(
      rgba,
      width,
      height,
      threshold: shadowThreshold,
    );
    if (plate == null || shadow == null) return null;
    final pad = [
      plate.left - shadow.left,
      plate.top - shadow.top,
      shadow.right - plate.right,
      shadow.bottom - plate.bottom,
    ].reduce((a, b) => a > b ? a : b);
    final plateSide = plate.width > plate.height ? plate.width : plate.height;
    final side = plateSide + pad * 2;
    final imageSide = width < height ? width : height;
    if (side >= imageSide) return null;
    return Rect.fromCenter(center: plate.center, width: side, height: side);
  }
}
