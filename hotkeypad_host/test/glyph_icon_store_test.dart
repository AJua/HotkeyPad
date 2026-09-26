import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:hotkeypad_host/src/glyph_icon_store.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

// Note: `flutter test` substitutes real fonts (the system emoji font,
// for the PNG path below) with a deterministic test font, so nothing
// here checks *where* ink actually landed in the emoji PNG — only that
// a real, correctly sized image comes back. Action icons are vector
// path data embedded directly (no font involved), so those checks can
// assert on the actual SVG markup.
Future<({int width, int height})> _decodedSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    return (width: frame.image.width, height: frame.image.height);
  } finally {
    frame.image.dispose();
  }
}

void main() {
  group('GlyphIconStore.handles', () {
    test('no longer claims an emoji id — emoji are saved as custom icons', () {
      expect(GlyphIconStore.handles('emoji:😀'), isFalse);
    });

    test('claims an action id', () {
      expect(GlyphIconStore.handles('action:mute'), isTrue);
    });

    test('does not claim an app name or a custom-icon id', () {
      expect(GlyphIconStore.handles('Google Chrome'), isFalse);
      expect(GlyphIconStore.handles('img_12345'), isFalse);
    });
  });

  group('GlyphIconStore.renderEmojiPng', () {
    test('renders an emoji at the requested square size', () async {
      final png = await GlyphIconStore.renderEmojiPng('😀', size: 64);
      final size = await _decodedSize(png);

      expect(size.width, 64);
      expect(size.height, 64);
    });
  });

  group('GlyphIconStore.render', () {
    test('renders a known action as an SVG at the requested viewBox size, '
        'with colour placeholders for the client to fill in', () async {
      final bytes = await GlyphIconStore.render('action:mute', size: 64);
      final svg = utf8.decode(bytes!);

      expect(svg, contains('viewBox="0 0 64 64"'));
      expect(svg, contains('{{border}}'));
      expect(svg, contains('{{glyph}}'));
      expect(svg, contains('{{bg}}'));
    });

    test('renders every DeckAction as SVG containing real path data', () async {
      for (final action in DeckAction.values) {
        final bytes = await GlyphIconStore.render('action:${action.wire}');
        expect(bytes, isNotNull, reason: 'no icon for ${action.wire}');
        final svg = utf8.decode(bytes!);
        expect(
          svg,
          contains('<path'),
          reason: '${action.wire} has no path element',
        );
      }
    });

    test('returns null for an unrecognised action wire id', () async {
      final png = await GlyphIconStore.render('action:not-a-real-action');

      expect(png, isNull);
    });

    test('returns null for an id it does not handle at all', () async {
      final png = await GlyphIconStore.render('Google Chrome');

      expect(png, isNull);
    });
  });
}
