import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bt_host/src/custom_icon_store.dart';
import 'package:bt_link_protocol/bt_link_protocol.dart';
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

void main() {
  group('CustomIconStore.cropToSquarePng', () {
    test('a wide image comes out exactly iconSize square', () async {
      final png = await _solidPng(300, 100, Colors.blue);

      final cropped = await CustomIconStore.cropToSquarePng(png);
      final size = await _decodedSize(cropped!);

      expect(size.width, BtLink.iconSize);
      expect(size.height, BtLink.iconSize);
    });

    test('a tall image comes out exactly iconSize square', () async {
      final png = await _solidPng(100, 300, Colors.red);

      final cropped = await CustomIconStore.cropToSquarePng(png);
      final size = await _decodedSize(cropped!);

      expect(size.width, BtLink.iconSize);
      expect(size.height, BtLink.iconSize);
    });

    test('an already-square image still comes out at iconSize', () async {
      final png = await _solidPng(200, 200, Colors.green);

      final cropped = await CustomIconStore.cropToSquarePng(png);
      final size = await _decodedSize(cropped!);

      expect(size.width, BtLink.iconSize);
      expect(size.height, BtLink.iconSize);
    });

    test(
      'an image smaller than iconSize is upscaled, not left small',
      () async {
        final png = await _solidPng(32, 32, Colors.yellow);

        final cropped = await CustomIconStore.cropToSquarePng(png);
        final size = await _decodedSize(cropped!);

        expect(size.width, BtLink.iconSize);
        expect(size.height, BtLink.iconSize);
      },
    );

    test('malformed bytes return null instead of throwing', () async {
      final cropped = await CustomIconStore.cropToSquarePng(
        Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(cropped, isNull);
    });
  });
}
