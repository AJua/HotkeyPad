import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

import 'deck_icons.dart';

/// Renders an emoji, or a [DeckAction]'s own built-in glyph, as a PNG —
/// the client no longer draws either of these itself. Every icon on the
/// wire is bytes to display now, the same as an app's icon or a custom
/// image, so a mute button and a 🎉 button both go through here instead
/// of a client-side font choice the host doesn't control. See
/// host_page.dart's `_sendIcon`, which tries the app/custom-icon/
/// background stores first and only reaches this one once none of them
/// claim the id.
abstract final class GlyphIconStore {
  static const _emojiPrefix = 'emoji:';
  static const _actionPrefix = 'action:';

  /// True for an [id] shaped like something this store can render — see
  /// `hotkeypad_client`'s `iconKeyFor`, which is what builds ids in this
  /// shape in the first place.
  static bool handles(String id) =>
      id.startsWith(_emojiPrefix) || id.startsWith(_actionPrefix);

  /// Renders [id], or returns null if it is not one this store handles,
  /// or names a [DeckAction] this build does not recognise (an id from a
  /// newer client, say).
  static Future<Uint8List?> render(
    String id, {
    int size = HotkeyPad.iconSize,
  }) async {
    final emoji = id.startsWith(_emojiPrefix)
        ? id.substring(_emojiPrefix.length)
        : null;
    if (emoji != null) return _renderGlyph(text: emoji, size: size);

    if (!id.startsWith(_actionPrefix)) return null;
    final wire = id.substring(_actionPrefix.length);
    DeckAction? action;
    for (final candidate in DeckAction.values) {
      if (candidate.wire == wire) {
        action = candidate;
        break;
      }
    }
    if (action == null) return null;

    // The exact IconData the host's own layout editor already shows next
    // to this action in its picker (deck_icons.dart) — reused rather than
    // a second copy, so the two can never drift apart.
    final icon = deckFallbackIcon(ActionItem(action));
    return _renderGlyph(
      text: String.fromCharCode(icon.codePoint),
      fontFamily: icon.fontFamily,
      fontPackage: icon.fontPackage,
      size: size,
    );
  }

  /// The app's own brand color rather than something theme-aware: a deck
  /// button's tint background is picked client-side, per label, so there
  /// is no host-side notion of "the current theme" to render against —
  /// see the client's own `_DeckButton`, which now treats every icon as
  /// a plain PNG and no longer special-cases one for theming. A fixed
  /// dark grey used to fill this glyph, but a glyph icon has no tinted
  /// background behind it any more (unlike the old client-drawn one),
  /// so in dark mode that read as almost invisible against the deck's
  /// own dark background — [HotkeyPad.themeSeedColor] is saturated
  /// enough to stay visible against either theme's background.
  static const _glyphColor = HotkeyPad.themeSeedColor;

  /// Border width and corner rounding as a fraction of [_renderGlyph]'s
  /// own `size`, matching [CustomIconStore]'s `cornerRadius` convention
  /// (`size * 0.18`) so a glyph icon reads as the same rounded-square
  /// shape as every other icon on a deck — this is the one shape with no
  /// bitmap of its own to imply that shape, so it is drawn explicitly.
  static const _borderWidthFraction = 0.0297; // 66% of the original 0.045
  static const _cornerRadiusFraction = 0.18;

  /// A fixed pixel margin, not a fraction of `size` like the two above:
  /// baked into the PNG itself so the border never sits flush against
  /// the edge of whatever box eventually displays it.
  static const _marginPx = 3.0;

  static Future<Uint8List> _renderGlyph({
    required String text,
    String? fontFamily,
    String? fontPackage,
    required int size,
  }) async {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size * 0.7,
          fontFamily: fontFamily,
          package: fontPackage,
          // Ignored by a colour emoji glyph, which paints its own colours
          // regardless — only meaningful for the monochrome action icons.
          color: _glyphColor,
        ),
      ),
    )..layout();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final borderWidth = size * _borderWidthFraction;
    final inset = _marginPx + borderWidth / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, size - inset * 2, size - inset * 2),
        Radius.circular(size * _cornerRadiusFraction),
      ),
      Paint()
        ..color = _glyphColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    painter.paint(
      canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2),
    );
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(size, size);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }
}
