import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:hotkeypad_host/src/background_image_store.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';

/// A solid-colour PNG of the given size, built purely in memory — no real
/// file is needed to exercise the downscale routine.
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

Uint8List _svg(String body) => Uint8List.fromList(utf8.encode(body));

void main() {
  group('BackgroundImageStore.downscale', () {
    test('leaves an image already within bounds untouched in size', () async {
      final png = await _solidPng(400, 300, Colors.blue);

      final result = await BackgroundImageStore.downscale(
        png,
        maxDimension: 1000,
      );
      final size = await _decodedSize(result!);

      expect(size.width, 400);
      expect(size.height, 300);
    });

    test('scales a wide image down, preserving aspect ratio', () async {
      final png = await _solidPng(4000, 2000, Colors.red);

      final result = await BackgroundImageStore.downscale(
        png,
        maxDimension: 1000,
      );
      final size = await _decodedSize(result!);

      expect(size.width, 1000);
      expect(size.height, 500);
    });

    test('scales a tall image down, preserving aspect ratio', () async {
      final png = await _solidPng(1000, 4000, Colors.green);

      final result = await BackgroundImageStore.downscale(
        png,
        maxDimension: 1000,
      );
      final size = await _decodedSize(result!);

      expect(size.width, 250);
      expect(size.height, 1000);
    });

    test('an already-small image is not upscaled', () async {
      // Unlike a square button icon, a background has no minimum size to
      // fill — a small source just stays small.
      final png = await _solidPng(50, 50, Colors.yellow);

      final result = await BackgroundImageStore.downscale(
        png,
        maxDimension: 1000,
      );
      final size = await _decodedSize(result!);

      expect(size.width, 50);
      expect(size.height, 50);
    });

    test('malformed bytes return null instead of throwing', () async {
      final result = await BackgroundImageStore.downscale(
        Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(result, isNull);
    });

    test('an SVG source is rasterized then downscaled like any raster',
        () async {
      final svg = _svg(
        '<svg xmlns="http://www.w3.org/2000/svg" width="3000" '
        'height="1000" viewBox="0 0 3000 1000">'
        '<rect width="3000" height="1000" fill="#0000ff"/></svg>',
      );

      final result = await BackgroundImageStore.downscale(
        svg,
        maxDimension: 300,
      );
      final size = await _decodedSize(result!);

      expect(size.width, 300);
      expect(size.height, 100);
    });
  });
}
