import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// The key to fetch a rendered icon for, or null when there is nothing to
/// show but a plain letter-avatar placeholder.
///
/// Every case here — a custom image, an app's own icon, or an action's
/// built-in glyph — is rendered by the host and sent over the same
/// [RequestIcon] transfer, so `_DeckButton` only ever has to decide
/// between "there are icon bytes" and "there are not"; it does not draw
/// a `DeckAction`'s glyph itself (though it does still decide *how* to
/// recolor it — see [looksLikeSvgIcon] and [glyphIconColors]). An emoji
/// the user picked on the host is not a case of its own: the host has
/// already rendered it into a custom image, so it arrives here as a
/// [DeckItem.customIconId] like any other. The `action:` prefix is this
/// client's own invention, not part of the protocol (an id is just an
/// opaque string to it) — see `hotkeypad_host`'s `GlyphIconStore`, the
/// other end that parses it.
String? iconKeyFor(DeckItem item) {
  final customIconId = item.customIconId;
  if (customIconId != null) return customIconId;
  if (item is AppItem) return item.name;
  if (item is ActionItem) return 'action:${item.action.wire}';
  return null;
}

/// True for icon bytes that are SVG markup rather than a raster image —
/// see `GlyphIconStore` on the host: an action's glyph is sent this way
/// so its colors can be adapted here, while an app icon and a custom image
/// (an emoji included) are still a plain image the host has already committed to
/// a fixed appearance for. Sniffed by content rather than a wire-level
/// flag, since a [RequestIcon] id is an opaque string as far as the
/// protocol is concerned — nothing else already tells the two apart.
bool looksLikeSvgIcon(Uint8List bytes) {
  for (final byte in bytes) {
    // Skip whatever whitespace might precede an XML declaration or the
    // <svg> tag itself — a PNG's fixed first byte (0x89) never matches
    // either this or '<' (0x3C), so this loop settles the question on
    // the very first byte, whichever it is.
    if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) {
      continue;
    }
    return byte == 0x3C;
  }
  return false;
}

/// The three colors an action's SVG glyph icon (see [looksLikeSvgIcon])
/// should be recolored to, given the deck's current theme and whether a
/// custom background image is showing behind it.
///
/// The border and the glyph both use the same black-or-white-by-brightness
/// logic as [AnalogClock]'s own numbers (its `faceColor`: `Colors.white`
/// in dark mode, `Colors.black87` in light mode) rather than the brand
/// accent — consistent with how every other piece of deck chrome reads
/// against either theme, and it reads as one shape (an outlined glyph)
/// rather than a two-tone one.
///
/// Without a custom background, that alone (on a transparent fill) is
/// what makes an action button read as a drawn icon rather than a photo —
/// the look the icon shipped with before it became recolorable at all,
/// just monochrome now instead of a fixed accent. With a custom
/// background, an arbitrary photo could sit behind it, so a solid scrim
/// is added — white in a light theme, black in a dark one — to stay
/// legible regardless of what the photo itself looks like; since the
/// scrim and the glyph/border would otherwise be the same color and
/// disappear into each other, the scrim always takes the *opposite* of
/// `faceColor`, not the theme's own light/dark choice directly.
///
/// The scrim is fully opaque, not merely translucent, on purpose: Impeller
/// on Android has a real bug (github.com/flutter/flutter, e.g. #158749/
/// #162562) rendering an SVG fill with an in-between alpha (neither fully
/// transparent nor fully opaque) as if it were not there at all —
/// confirmed against a real device, where a `rgba(..., 0.7)` fill quietly
/// painted nothing while the exact same color at alpha 1.0 painted fine.
/// Fully opaque (this) and fully transparent ([Colors.transparent] above)
/// both avoid that code path.
({Color border, Color glyph, Color background}) glyphIconColors({
  required Brightness brightness,
  required bool hasCustomBackground,
}) {
  final dark = brightness == Brightness.dark;
  // Matches AnalogClock's own `faceColor` exactly.
  final faceColor = dark ? Colors.white : Colors.black87;
  if (!hasCustomBackground) {
    return (
      border: faceColor,
      glyph: faceColor,
      background: Colors.transparent,
    );
  }
  final background = dark ? Colors.black : Colors.white;
  return (border: faceColor, glyph: faceColor, background: background);
}

/// Substitutes [glyphIconColors]' output into an SVG template's
/// `{{border}}`/`{{glyph}}`/`{{bg}}` placeholders — see `GlyphIconStore`
/// on the host, which is what puts them there. Plain string replacement,
/// not real templating: the host controls the exact shape of what it
/// sends and always uses these three tokens verbatim.
String recolorGlyphSvg(
  String template, {
  required Color border,
  required Color glyph,
  required Color background,
}) {
  return template
      .replaceAll('{{border}}', _cssColor(border))
      .replaceAll('{{glyph}}', _cssColor(glyph))
      .replaceAll('{{bg}}', _cssColor(background));
}

String _cssColor(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return 'rgba($r, $g, $b, ${color.a.toStringAsFixed(3)})';
}
