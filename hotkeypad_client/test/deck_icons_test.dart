import 'dart:convert';
import 'dart:typed_data';

import 'package:hotkeypad_client/src/deck_icons.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iconKeyFor', () {
    test('an app with nothing custom is keyed by its own name', () {
      expect(iconKeyFor(const AppItem('Chrome')), 'Chrome');
    });

    test('a custom icon id wins over an app name', () {
      expect(
        iconKeyFor(const AppItem('Chrome', customIconId: 'img_1')),
        'img_1',
      );
    });

    test('an emoji wins over both a custom icon id and an app name', () {
      expect(
        iconKeyFor(const AppItem('Chrome', emoji: '🎉', customIconId: 'img_1')),
        'emoji:🎉',
      );
    });

    test('an action with nothing custom is keyed by its own wire id, not '
        'drawn as a local glyph any more', () {
      expect(iconKeyFor(const ActionItem(DeckAction.mute)), 'action:mute');
      expect(iconKeyFor(const ActionItem(DeckAction.volumeUp)), 'action:volup');
    });

    test('an action with a custom icon id is keyed by that instead', () {
      expect(
        iconKeyFor(
          const ActionItem(DeckAction.playPause, customIconId: 'img_2'),
        ),
        'img_2',
      );
    });

    test('an item with no icon of its own and no emoji has no key at all', () {
      expect(
        iconKeyFor(const ShellItem(command: 'echo hi', label: 'Hi')),
        isNull,
      );
    });
  });

  group('looksLikeSvgIcon', () {
    test('a PNG is never mistaken for SVG', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
      expect(looksLikeSvgIcon(png), isFalse);
    });

    test('SVG markup starting with the tag itself is recognised', () {
      final svg = Uint8List.fromList(utf8.encode('<svg></svg>'));
      expect(looksLikeSvgIcon(svg), isTrue);
    });

    test('leading whitespace before the tag is skipped over', () {
      final svg = Uint8List.fromList(utf8.encode('  \n<svg></svg>'));
      expect(looksLikeSvgIcon(svg), isTrue);
    });

    test('empty bytes are not SVG', () {
      expect(looksLikeSvgIcon(Uint8List(0)), isFalse);
    });
  });

  group('glyphIconColors', () {
    test('no custom background: transparent, clock-style border and glyph', () {
      final light = glyphIconColors(
        brightness: Brightness.light,
        hasCustomBackground: false,
      );
      expect(light.background, Colors.transparent);
      // Both match AnalogClock's own faceColor exactly.
      expect(light.border, Colors.black87);
      expect(light.glyph, Colors.black87);

      final dark = glyphIconColors(
        brightness: Brightness.dark,
        hasCustomBackground: false,
      );
      expect(dark.border, Colors.white);
      expect(dark.glyph, Colors.white);
    });

    test('custom background in light theme gets a fully opaque white scrim, '
        'opposite the black border/glyph', () {
      final colors = glyphIconColors(
        brightness: Brightness.light,
        hasCustomBackground: true,
      );
      expect(colors.border, Colors.black87);
      expect(colors.background, isNot(Colors.transparent));
      expect(colors.background.r, 1.0);
      expect(colors.background.g, 1.0);
      expect(colors.background.b, 1.0);
      // Not merely translucent — see glyphIconColors' own doc comment for
      // the Impeller/Android bug this specifically works around.
      expect(colors.background.a, 1.0);
    });

    test('custom background in dark theme gets a fully opaque black scrim, '
        'opposite the white border/glyph', () {
      final colors = glyphIconColors(
        brightness: Brightness.dark,
        hasCustomBackground: true,
      );
      expect(colors.border, Colors.white);
      expect(colors.background, isNot(Colors.transparent));
      expect(colors.background.r, 0.0);
      expect(colors.background.g, 0.0);
      expect(colors.background.b, 0.0);
      expect(colors.background.a, 1.0);
    });
  });

  group('recolorGlyphSvg', () {
    test('substitutes all three placeholders', () {
      const template =
          '<rect fill="{{bg}}" stroke="{{border}}"/>'
          '<path fill="{{glyph}}"/>';

      final result = recolorGlyphSvg(
        template,
        border: const Color(0xFFFF0000),
        glyph: const Color(0xFF00FF00),
        background: const Color(0xFF0000FF),
      );

      expect(result, isNot(contains('{{')));
      expect(result, contains('rgba(255, 0, 0, 1.000)'));
      expect(result, contains('rgba(0, 255, 0, 1.000)'));
      expect(result, contains('rgba(0, 0, 255, 1.000)'));
    });

    test('a transparent color still substitutes, with alpha 0', () {
      final result = recolorGlyphSvg(
        '{{bg}}',
        border: Colors.black,
        glyph: Colors.black,
        background: Colors.transparent,
      );

      expect(result, 'rgba(0, 0, 0, 0.000)');
    });
  });
}
