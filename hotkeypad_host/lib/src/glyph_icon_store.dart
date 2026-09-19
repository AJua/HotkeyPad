import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Renders an emoji as a PNG, or a [DeckAction]'s own built-in glyph as an
/// SVG — the client no longer draws either of these itself. See
/// host_page.dart's `_sendIcon`, which tries the app/custom-icon/
/// background stores first and only reaches this one once none of them
/// claim the id.
///
/// The two formats aren't a historical accident: an emoji is already a
/// multi-colour glyph with nothing sensible to recolour, so it stays a
/// plain PNG rendered once. An action's glyph is a single flat shape whose
/// border, fill, and background need to adapt to whatever theme or custom
/// background the *client* is showing it against — something only the
/// client knows — so it is sent as an SVG with colour placeholders
/// (`{{border}}`, `{{glyph}}`, `{{bg}}`) for the client to substitute at
/// display time (see `hotkeypad_client`'s `recolorGlyphSvg`), rather than
/// a colour baked in once here.
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
    if (emoji != null) return _renderEmojiPng(emoji, size: size);

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
    return _renderActionSvg(action, size: size);
  }

  /// A fixed dark colour rather than something theme-aware: an emoji's own
  /// colours are what it is drawn for, so this only ever paints the
  /// invisible-until-something-goes-wrong fallback glyph a font substitutes
  /// when it cannot render the requested emoji at all, plus the border —
  /// [HotkeyPad.themeSeedColor] stays visible against either theme's
  /// background, unlike a plain dark grey.
  static const _emojiColor = HotkeyPad.themeSeedColor;

  /// Border width and corner rounding as a fraction of `size`, matching
  /// [CustomIconStore]'s `cornerRadius` convention (`size * 0.18`) so a
  /// glyph icon reads as the same rounded-square shape as every other icon
  /// on a deck — this is the one shape with no bitmap of its own to imply
  /// that shape, so it is drawn explicitly. Shared between the emoji PNG
  /// and the action SVG so the two look consistent next to each other.
  static const _borderWidthFraction = 0.0297; // 66% of the original 0.045
  static const _cornerRadiusFraction = 0.18;

  /// A fixed pixel margin, not a fraction of `size` like the two above:
  /// baked into the icon itself so the border never sits flush against
  /// the edge of whatever box eventually displays it.
  static const _marginPx = 3.0;

  static Future<Uint8List> _renderEmojiPng(
    String emoji, {
    required int size,
  }) async {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: size * 0.7, color: _emojiColor),
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
        ..color = _emojiColor
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

  /// Official Material Icons path data (24x24 viewBox), from
  /// https://github.com/google/material-design-icons — the exact same
  /// glyphs [DeckAction] used to render as a font character client-side,
  /// now embedded as vector outlines instead, since a font glyph cannot be
  /// dropped into an SVG's `fill` without the font itself travelling with
  /// it.
  static const _actionPaths = <DeckAction, String>{
    DeckAction.playPause: 'M8 5v14l11-7z',
    DeckAction.next: 'M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z',
    DeckAction.previous: 'M6 6h2v12H6zm3.5 6l8.5 6V6z',
    DeckAction.volumeUp:
        'M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 '
        '2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 '
        '5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z',
    DeckAction.volumeDown:
        'M18.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 '
        '2.5-4.02zM5 9v6h4l5 5V4L9 9H5z',
    DeckAction.mute:
        'M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm'
        '2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 '
        '12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 '
        '4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 '
        '1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 '
        '3zM12 4L9.91 6.09 12 8.18V4z',
  };

  static Uint8List _renderActionSvg(DeckAction action, {required int size}) {
    final borderWidth = size * _borderWidthFraction;
    final inset = _marginPx + borderWidth / 2;
    final boxSize = size - inset * 2;
    final cornerRadius = size * _cornerRadiusFraction;

    // The path data above is drawn on a 24x24 grid; scaled and centred to
    // match the same size * 0.7 fill fraction the emoji PNG's font size
    // used, for a consistent glyph size between the two icon kinds.
    final iconScale = (size * 0.7) / 24;
    final iconOffset = (size - 24 * iconScale) / 2;

    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size">'
        '<rect x="$inset" y="$inset" width="$boxSize" height="$boxSize" '
        'rx="$cornerRadius" fill="{{bg}}" stroke="{{border}}" '
        'stroke-width="$borderWidth"/>'
        '<path transform="translate($iconOffset $iconOffset) '
        'scale($iconScale)" d="${_actionPaths[action]}" fill="{{glyph}}"/>'
        '</svg>';
    return Uint8List.fromList(utf8.encode(svg));
  }
}
