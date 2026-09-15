import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:hotkeypad_host/src/custom_icon_store.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';

/// A solid-colour PNG of the given size, built purely in memory — no real
/// file is needed to exercise the crop/resize routine.
Future<Uint8List> _solidPng(int width, int height, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
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

Future<({int width, int height})> _decodedSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    return (width: frame.image.width, height: frame.image.height);
  } finally {
    frame.image.dispose();
  }
}

/// The colour at the exact centre of the decoded image — enough to confirm
/// an SVG was actually rasterized into recognisable content, not just
/// resized to the right dimensions.
Future<ui.Color> _centerColor(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset =
        ((image.width ~/ 2) + (image.height ~/ 2) * image.width) * 4;
    final bytes = data!.buffer.asUint8List();
    return ui.Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  } finally {
    frame.image.dispose();
  }
}

Uint8List _svg(String body) => Uint8List.fromList(utf8.encode(body));

/// The alpha channel at a fractional position within the decoded image —
/// (0, 0) is the top-left corner, (0.5, 0.5) the centre.
Future<int> _alphaAt(Uint8List bytes, double fx, double fy) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final x = (image.width * fx).floor().clamp(0, image.width - 1);
    final y = (image.height * fy).floor().clamp(0, image.height - 1);
    final offset = (x + y * image.width) * 4;
    return data!.buffer.asUint8List()[offset + 3];
  } finally {
    frame.image.dispose();
  }
}

void main() {
  group('CustomIconStore.cropToSquarePng', () {
    test('a wide image comes out exactly iconSize square', () async {
      final png = await _solidPng(300, 100, Colors.blue);

      final cropped = await CustomIconStore.cropToSquarePng(png);
      final size = await _decodedSize(cropped!);

      expect(size.width, HotkeyPad.iconSize);
      expect(size.height, HotkeyPad.iconSize);
    });

    test('a tall image comes out exactly iconSize square', () async {
      final png = await _solidPng(100, 300, Colors.red);

      final cropped = await CustomIconStore.cropToSquarePng(png);
      final size = await _decodedSize(cropped!);

      expect(size.width, HotkeyPad.iconSize);
      expect(size.height, HotkeyPad.iconSize);
    });

    test('an already-square image still comes out at iconSize', () async {
      final png = await _solidPng(200, 200, Colors.green);

      final cropped = await CustomIconStore.cropToSquarePng(png);
      final size = await _decodedSize(cropped!);

      expect(size.width, HotkeyPad.iconSize);
      expect(size.height, HotkeyPad.iconSize);
    });

    test(
      'an image smaller than iconSize is upscaled, not left small',
      () async {
        final png = await _solidPng(32, 32, Colors.yellow);

        final cropped = await CustomIconStore.cropToSquarePng(png);
        final size = await _decodedSize(cropped!);

        expect(size.width, HotkeyPad.iconSize);
        expect(size.height, HotkeyPad.iconSize);
      },
    );

    test('malformed bytes return null instead of throwing', () async {
      final cropped = await CustomIconStore.cropToSquarePng(
        Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(cropped, isNull);
    });

    test(
      'a source that fills its own canvas comes out edge to edge, with '
      'rounded rather than square corners',
      () async {
        // A custom icon should fill the same button box a real app icon
        // does, not sit inside it with room to spare — so a source that
        // already fills its own canvas (a photo, or a logo drawn right to
        // the edges of its SVG) is scaled to fill this one too. The one
        // exception is the corners: real app icons are drawn as a rounded
        // square, so this clips to the same shape rather than leaving a
        // sharp right angle.
        final png = await _solidPng(200, 200, Colors.orange);

        final cropped = await CustomIconStore.cropToSquarePng(png);

        // However big the rounding is, the farthest point of a square from
        // an inscribed circle is always its corner, so this is transparent
        // regardless of the exact radius.
        expect(await _alphaAt(cropped!, 0.02, 0.02), 0);
        // The centre, and a point right at the middle of an edge — away
        // from every corner — are both inside the rounded rect's flat
        // sides and therefore opaque: the source really does reach the
        // edge, it is only the corners that are clipped.
        expect(await _alphaAt(cropped, 0.5, 0.5), greaterThan(0));
        expect(await _alphaAt(cropped, 0.03, 0.5), greaterThan(0));
      },
    );

    group('SVG source', () {
      test('a wide SVG comes out iconSize square', () async {
        final svg = _svg(
          '<svg xmlns="http://www.w3.org/2000/svg" width="300" '
          'height="100" viewBox="0 0 300 100">'
          '<rect width="300" height="100" fill="#0000ff"/></svg>',
        );

        final cropped = await CustomIconStore.cropToSquarePng(svg);
        final size = await _decodedSize(cropped!);

        expect(size.width, HotkeyPad.iconSize);
        expect(size.height, HotkeyPad.iconSize);
      });

      test('a tall SVG comes out iconSize square', () async {
        final svg = _svg(
          '<svg xmlns="http://www.w3.org/2000/svg" width="100" '
          'height="300" viewBox="0 0 100 300">'
          '<rect width="100" height="300" fill="#ff0000"/></svg>',
        );

        final cropped = await CustomIconStore.cropToSquarePng(svg);
        final size = await _decodedSize(cropped!);

        expect(size.width, HotkeyPad.iconSize);
        expect(size.height, HotkeyPad.iconSize);
      });

      test('an SVG is actually rasterized, not just resized', () async {
        final svg = _svg(
          '<svg xmlns="http://www.w3.org/2000/svg" width="200" '
          'height="200" viewBox="0 0 200 200">'
          '<rect width="200" height="200" fill="#00ff00"/></svg>',
        );

        final cropped = await CustomIconStore.cropToSquarePng(svg);
        final color = await _centerColor(cropped!);

        // Color's r/g/b are normalised 0.0-1.0, not the old 0-255 ints.
        expect(color.g, greaterThan(0.78));
        expect(color.r, lessThan(0.2));
        expect(color.b, lessThan(0.2));
      });

      test(
        'an SVG with neither a viewBox nor width/height returns null '
        'instead of throwing',
        () async {
          // The underlying parser requires one or the other to establish a
          // viewport; without either, this is malformed input the same as
          // any other undecodable file.
          final svg = _svg(
            '<svg xmlns="http://www.w3.org/2000/svg">'
            '<rect width="10" height="10" fill="#000"/></svg>',
          );

          final cropped = await CustomIconStore.cropToSquarePng(svg);

          expect(cropped, isNull);
        },
      );

      test('malformed SVG source returns null instead of throwing', () async {
        final svg = _svg('<svg xmlns="http://www.w3.org/2000/svg"><rect fill="');

        final cropped = await CustomIconStore.cropToSquarePng(svg);

        expect(cropped, isNull);
      });

      test('a raster image is never mistaken for SVG', () async {
        // Sanity check that the sniff in cropToSquarePng doesn't fire on a
        // plain photo just because its bytes happen to contain other text.
        final png = await _solidPng(64, 64, Colors.purple);

        final cropped = await CustomIconStore.cropToSquarePng(png);

        expect(cropped, isNotNull);
      });
    });
  });
}
