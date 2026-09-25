import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotkeypad_host/src/alpha_bounds.dart';

/// A [width]×[height] RGBA buffer, transparent everywhere except the
/// pixels [opaque] marks, which get full alpha.
Uint8List _rgba(int width, int height, bool Function(int x, int y) opaque) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (opaque(x, y)) bytes[(x + y * width) * 4 + 3] = 255;
    }
  }
  return bytes;
}

void main() {
  group('AlphaBounds.hasTransparentBackground', () {
    test('a fully opaque image is not a transparent logo', () {
      final rgba = _rgba(10, 10, (_, _) => true);

      expect(AlphaBounds.hasTransparentBackground(rgba), isFalse);
    });

    test('a logo in the middle of an empty canvas is', () {
      final rgba = _rgba(10, 10, (x, y) => x >= 3 && x < 7 && y >= 3 && y < 7);

      expect(AlphaBounds.hasTransparentBackground(rgba), isTrue);
    });

    test('a single stray transparent pixel in a photo does not count', () {
      final rgba = _rgba(10, 10, (x, y) => !(x == 0 && y == 0));

      expect(AlphaBounds.hasTransparentBackground(rgba), isFalse);
    });

    test('an empty buffer is not a transparent logo', () {
      expect(AlphaBounds.hasTransparentBackground(Uint8List(0)), isFalse);
    });
  });

  group('AlphaBounds.opaqueBounds', () {
    test('trims the transparent margin down to the logo', () {
      final rgba = _rgba(20, 10, (x, y) => x >= 4 && x < 16 && y >= 2 && y < 7);

      expect(
        AlphaBounds.opaqueBounds(rgba, 20, 10),
        const Rect.fromLTRB(4, 2, 16, 7),
      );
    });

    test('ignores faint pixels below the threshold', () {
      final rgba = _rgba(10, 10, (x, y) => x == 5 && y == 5);
      // A near-invisible haze in the corner, like leftover anti-aliasing.
      rgba[3] = 5;

      expect(
        AlphaBounds.opaqueBounds(rgba, 10, 10),
        const Rect.fromLTRB(5, 5, 6, 6),
      );
    });

    test('is null when nothing is visible', () {
      expect(
        AlphaBounds.opaqueBounds(_rgba(4, 4, (_, _) => false), 4, 4),
        isNull,
      );
    });
  });

  group('AlphaBounds.plateCrop', () {
    /// A 100×100 canvas with an opaque plate from 20 to 80, and a faint
    /// shadow reaching 2px past it on the sides and 6px past it below —
    /// the shape of a Big Sur icon, margin and all.
    Uint8List bigSurLike() {
      final rgba = _rgba(
        100,
        100,
        (x, y) => x >= 20 && x < 80 && y >= 20 && y < 80,
      );
      for (var y = 20; y < 86; y++) {
        for (var x = 18; x < 82; x++) {
          final alpha = (x + y * 100) * 4 + 3;
          if (rgba[alpha] == 0) rgba[alpha] = 40;
        }
      }
      return rgba;
    }

    test('keeps the plate centred and the whole shadow inside', () {
      final crop = AlphaBounds.plateCrop(bigSurLike(), 100, 100)!;

      // Plate 60px wide, padded by the farthest shadow reach (6px below)
      // on every side, around the plate's own centre.
      expect(
        crop,
        Rect.fromCenter(center: const Offset(50, 50), width: 72, height: 72),
      );
    });

    test('a faint haze below the shadow threshold is trimmed away', () {
      final rgba = bigSurLike();
      rgba[3] = 2;

      expect(
        AlphaBounds.plateCrop(rgba, 100, 100),
        Rect.fromCenter(center: const Offset(50, 50), width: 72, height: 72),
      );
    });

    test('a full-bleed icon has nothing to trim', () {
      final rgba = _rgba(100, 100, (_, _) => true);

      expect(AlphaBounds.plateCrop(rgba, 100, 100), isNull);
    });

    test('an empty image has nothing to trim', () {
      expect(
        AlphaBounds.plateCrop(_rgba(10, 10, (_, _) => false), 10, 10),
        isNull,
      );
    });
  });
}
