import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hotkeypad_host/src/favicon_fetcher.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A [side]-pixel square PNG, transparent except for a red square in the
/// middle — the shape of a typical favicon.
Future<Uint8List> _faviconPng(int side) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(side / 4, side / 4, side / 2, side / 2),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// Wraps [png] in a single-entry .ico container — the format a real
/// `/favicon.ico` is served in. ICO allows a PNG as an entry's payload.
Uint8List _icoWrapping(Uint8List png, int side) {
  final header = ByteData(22)
    ..setUint16(0, 0, Endian.little) // reserved
    ..setUint16(2, 1, Endian.little) // type: icon
    ..setUint16(4, 1, Endian.little) // one entry
    ..setUint8(6, side) // width
    ..setUint8(7, side) // height
    ..setUint8(8, 0) // palette size
    ..setUint8(9, 0) // reserved
    ..setUint16(10, 1, Endian.little) // colour planes
    ..setUint16(12, 32, Endian.little) // bits per pixel
    ..setUint32(14, png.length, Endian.little)
    ..setUint32(18, 22, Endian.little); // payload offset
  return Uint8List.fromList([...header.buffer.asUint8List(), ...png]);
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
  group('FaviconFetcher.iconUris', () {
    test('tries apple-touch-icon, then favicon.ico, at the host root', () {
      expect(
        FaviconFetcher.iconUris('https://mail.google.com/mail/u/0/#inbox'),
        [
          Uri.parse('https://mail.google.com/apple-touch-icon.png'),
          Uri.parse('https://mail.google.com/favicon.ico'),
        ],
      );
    });

    test('takes a bare address as https', () {
      expect(
        FaviconFetcher.iconUris('www.google.com').last,
        Uri.parse('https://www.google.com/favicon.ico'),
      );
    });

    test('keeps plain http and an explicit port', () {
      expect(
        FaviconFetcher.iconUris('http://localhost:8080/app').last,
        Uri.parse('http://localhost:8080/favicon.ico'),
      );
    });

    test('is empty for non-web schemes and empty input', () {
      expect(FaviconFetcher.iconUris('file:///tmp/a.html'), isEmpty);
      expect(FaviconFetcher.iconUris('mailto:a@b.c'), isEmpty);
      expect(FaviconFetcher.iconUris('   '), isEmpty);
    });
  });

  group('FaviconFetcher.fetchIconPng', () {
    test('prefers apple-touch-icon when the site has one', () async {
      final png = await _faviconPng(180);
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.path);
        return http.Response.bytes(png, 200);
      });

      final out = await FaviconFetcher.fetchIconPng(
        'https://example.com/some/page',
        client: client,
      );

      expect(requested, ['/apple-touch-icon.png']);
      final size = await _decodedSize(out!);
      expect(size.width, HotkeyPad.iconSize);
      expect(size.height, HotkeyPad.iconSize);
    });

    test(
      'falls back to a served .ico when there is no apple-touch-icon',
      () async {
        final ico = _icoWrapping(await _faviconPng(32), 32);
        final requested = <String>[];
        final client = MockClient((request) async {
          requested.add(request.url.path);
          return request.url.path == '/favicon.ico'
              ? http.Response.bytes(ico, 200)
              : http.Response('Not found', 404);
        });

        final out = await FaviconFetcher.fetchIconPng(
          'https://example.com',
          client: client,
        );

        expect(requested, ['/apple-touch-icon.png', '/favicon.ico']);
        final size = await _decodedSize(out!);
        expect(size.width, HotkeyPad.iconSize);
      },
    );

    test('falls back when apple-touch-icon is not an image', () async {
      final ico = _icoWrapping(await _faviconPng(32), 32);
      final client = MockClient(
        (request) async => request.url.path == '/favicon.ico'
            ? http.Response.bytes(ico, 200)
            : http.Response('<html>soft 404</html>', 200),
      );

      expect(
        await FaviconFetcher.fetchIconPng(
          'https://example.com',
          client: client,
        ),
        isNotNull,
      );
    });

    test('is null when the site has no icon at all', () async {
      final client = MockClient((_) async => http.Response('Not found', 404));

      expect(
        await FaviconFetcher.fetchIconPng(
          'https://example.com',
          client: client,
        ),
        isNull,
      );
    });

    test('is null when the body is not an image', () async {
      final client = MockClient(
        (_) async => http.Response('<html>login</html>', 200),
      );

      expect(
        await FaviconFetcher.fetchIconPng(
          'https://example.com',
          client: client,
        ),
        isNull,
      );
    });

    test('is null, without a request, when there is no host', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('', 200);
      });

      expect(
        await FaviconFetcher.fetchIconPng('mailto:a@b.c', client: client),
        isNull,
      );
      expect(called, isFalse);
    });

    test('is null when the request fails', () async {
      final client = MockClient((_) async => throw http.ClientException('x'));

      expect(
        await FaviconFetcher.fetchIconPng(
          'https://example.com',
          client: client,
        ),
        isNull,
      );
    });
  });
}
