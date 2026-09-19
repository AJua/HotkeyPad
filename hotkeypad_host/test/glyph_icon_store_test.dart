import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:hotkeypad_host/src/glyph_icon_store.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

// Note: `flutter test` substitutes real fonts (Material Icons, the
// system emoji font) with a deterministic test font, so nothing here
// checks *where* ink actually landed — only that a real, correctly
// sized PNG comes back. The real glyph shapes are only ever real fonts
// in the built app, verified there instead (see the session's manual
// on-device check when this was written).
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
    test('claims an emoji id', () {
      expect(GlyphIconStore.handles('emoji:😀'), isTrue);
    });

    test('claims an action id', () {
      expect(GlyphIconStore.handles('action:mute'), isTrue);
    });

    test('does not claim an app name or a custom-icon id', () {
      expect(GlyphIconStore.handles('Google Chrome'), isFalse);
      expect(GlyphIconStore.handles('img_12345'), isFalse);
    });
  });

  group('GlyphIconStore.render', () {
    test('renders an emoji at the requested square size', () async {
      final png = await GlyphIconStore.render('emoji:😀', size: 64);
      final size = await _decodedSize(png!);

      expect(size.width, 64);
      expect(size.height, 64);
    });

    test('renders a known action at the requested square size', () async {
      final png = await GlyphIconStore.render('action:mute', size: 64);
      final size = await _decodedSize(png!);

      expect(size.width, 64);
      expect(size.height, 64);
    });

    test('renders every DeckAction without throwing', () async {
      for (final action in DeckAction.values) {
        final png = await GlyphIconStore.render('action:${action.wire}');
        expect(png, isNotNull, reason: 'no icon for ${action.wire}');
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
