import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Ready-made deck backgrounds — flat, simple geometric scenes covering the
/// four seasons, a handful of common weather conditions, and one outdoor
/// silhouette — offered in [BackgroundPicker] alongside a user's own picked
/// image, so there is something worth trying before anyone has to go find
/// a picture of their own.
///
/// Rendered procedurally with [Canvas], the same choice `GlyphIconStore`
/// makes for its own built-in glyphs: no binary image assets ship with the
/// app (this repo has never had a `flutter: assets:` section), and every
/// size anyone ever asks for is drawn fresh from the same shape data
/// rather than pre-baked at one resolution and scaled.
abstract final class BuiltinBackgroundStore {
  static const _prefix = 'bgbuiltin:';

  /// The order [BackgroundPicker] shows them in.
  static const ids = [
    'spring',
    'summer',
    'autumn',
    'winter',
    'sunny',
    'cloudy',
    'rainy',
    'snowy',
    'mountains',
  ];

  static bool handles(String id) => id.startsWith(_prefix);

  /// Turns a bare name from [ids] into the wire id [handles] recognizes.
  static String idFor(String name) => '$_prefix$name';

  /// Null for anything [handles] rejects, or a name not in [ids] — the
  /// same "give up, don't guess" stance `GlyphIconStore.render` takes for
  /// an action it doesn't know either.
  static Future<Uint8List?> render(
    String id, {
    int width = 1200,
    int height = 800,
  }) async {
    if (!handles(id)) return null;
    final painter = _painters[id.substring(_prefix.length)];
    if (painter == null) return null;
    return _draw(painter, width, height);
  }

  static Future<Uint8List> _draw(
    void Function(Canvas, Size) painter,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter(canvas, Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static final _painters = <String, void Function(Canvas, Size)>{
    'spring': _paintSpring,
    'summer': _paintSummer,
    'autumn': _paintAutumn,
    'winter': _paintWinter,
    'sunny': _paintSunny,
    'cloudy': _paintCloudy,
    'rainy': _paintRainy,
    'snowy': _paintSnowy,
    'mountains': _paintMountains,
  };

  static void _gradient(
    Canvas canvas,
    Size size,
    List<Color> colors, {
    Alignment begin = Alignment.topCenter,
    Alignment end = Alignment.bottomCenter,
  }) {
    // Gradient.linear only infers even stops for exactly 2 colors —
    // anything else throws unless they're given explicitly.
    final stops = colors.length == 2
        ? null
        : [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        begin.alongSize(size),
        end.alongSize(size),
        colors,
        stops,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  // A fixed seed per scene rather than an unseeded Random: the same id is
  // re-rendered from scratch on every request (nothing here is cached to
  // disk — see the class doc comment), so an unseeded scatter of dots
  // would visibly reshuffle itself on every reconnect.
  static void _paintSpring(Canvas canvas, Size size) {
    _gradient(canvas, size, [const Color(0xFFFFE1EC), const Color(0xFFBBEAC7)]);
    final rnd = Random(1);
    final blossom = Paint()
      ..color = const Color(0xFFFF8FBF).withValues(alpha: 0.6);
    for (var i = 0; i < 16; i++) {
      final r = 14.0 + rnd.nextDouble() * 22;
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        r,
        blossom,
      );
    }
  }

  static void _paintSummer(Canvas canvas, Size size) {
    _gradient(canvas, size, [
      const Color(0xFF1E88C7),
      const Color(0xFF6FE3D6),
      const Color(0xFFF4E3B2),
    ], end: Alignment.bottomCenter);
    final sun = Paint()..color = const Color(0xFFFFD84A);
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.22),
      size.shortestSide * 0.14,
      sun,
    );
    final wave = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.015;
    final waveY = size.height * 0.72;
    final amplitude = size.height * 0.025;
    final path = Path()..moveTo(0, waveY);
    const steps = 40;
    for (var i = 1; i <= steps; i++) {
      final x = size.width * i / steps;
      final y = waveY + sin(i / steps * 4 * pi) * amplitude;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, wave);
  }

  static void _paintAutumn(Canvas canvas, Size size) {
    _gradient(canvas, size, [const Color(0xFFF7A34B), const Color(0xFF9C4B24)]);
    final rnd = Random(2);
    const leafColors = [
      Color(0xFFE0592B),
      Color(0xFFF2B705),
      Color(0xFFB23A1E),
    ];
    for (var i = 0; i < 18; i++) {
      final paint = Paint()
        ..color = leafColors[i % leafColors.length].withValues(alpha: 0.75);
      final center = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      final r = 12.0 + rnd.nextDouble() * 16;
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..quadraticBezierTo(center.dx + r, center.dy, center.dx, center.dy + r)
        ..quadraticBezierTo(center.dx - r, center.dy, center.dx, center.dy - r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  static void _paintWinter(Canvas canvas, Size size) {
    _gradient(canvas, size, [const Color(0xFFDCEEFB), const Color(0xFFF7FBFF)]);
    final rnd = Random(3);
    final snow = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (var i = 0; i < 40; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        2 + rnd.nextDouble() * 3,
        snow,
      );
    }
    final treePaint = Paint()..color = const Color(0xFF3E6B63);
    for (var i = 0; i < 4; i++) {
      final baseX = size.width * (0.15 + i * 0.22);
      final baseY = size.height * 0.92;
      final treeHeight = size.height * 0.16;
      final path = Path()
        ..moveTo(baseX, baseY - treeHeight)
        ..lineTo(baseX - treeHeight * 0.45, baseY)
        ..lineTo(baseX + treeHeight * 0.45, baseY)
        ..close();
      canvas.drawPath(path, treePaint);
    }
  }

  static void _paintSunny(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.72, size.height * 0.3);
    final paint = Paint()
      ..shader = ui.Gradient.radial(center, size.longestSide * 0.9, [
        const Color(0xFFFFE9A8),
        const Color(0xFF5CB8E0),
      ]);
    canvas.drawRect(Offset.zero & size, paint);
    final sun = Paint()..color = const Color(0xFFFFC93C);
    canvas.drawCircle(center, size.shortestSide * 0.16, sun);
    final ray = Paint()
      ..color = const Color(0xFFFFC93C).withValues(alpha: 0.7)
      ..strokeWidth = size.shortestSide * 0.02
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      final inner = size.shortestSide * 0.24;
      final outer = size.shortestSide * 0.32;
      canvas.drawLine(
        center + Offset(cos(angle), sin(angle)) * inner,
        center + Offset(cos(angle), sin(angle)) * outer,
        ray,
      );
    }
  }

  static void _paintCloudy(Canvas canvas, Size size) {
    _gradient(canvas, size, [const Color(0xFF9FB3C8), const Color(0xFFDCE4EC)]);
    final rnd = Random(4);
    // Spread further apart than the naive random spread would give (each
    // cloud gets its own horizontal band) — otherwise a `Random` this
    // small a sample from tends to clump two or three together and leave
    // the rest of the frame empty.
    for (var i = 0; i < 4; i++) {
      final cx = size.width * (0.15 + i * 0.24) + rnd.nextDouble() * 40 - 20;
      final cy = size.height * (0.25 + rnd.nextDouble() * 0.35);
      final scale = 0.55 + rnd.nextDouble() * 0.35;
      _drawCloud(
        canvas,
        Offset(cx, cy),
        size.shortestSide * 0.16 * scale,
        Colors.white,
        alpha: 1,
      );
    }
  }

  /// Draws the whole cloud into an offscreen layer first and composites
  /// that layer at [alpha] in one pass — several overlapping translucent
  /// shapes drawn directly would double up their alpha wherever they
  /// overlap, leaving visible seams along every circle's edge instead of
  /// one smooth, evenly translucent cloud.
  static void _drawCloud(
    Canvas canvas,
    Offset center,
    double r,
    Color color, {
    required double alpha,
  }) {
    canvas.saveLayer(
      Rect.fromCenter(center: center, width: r * 6, height: r * 4),
      Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
    );
    final paint = Paint()..color = color;
    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center + Offset(r * 0.9, r * 0.15), r * 0.75, paint);
    canvas.drawCircle(center + Offset(-r * 0.9, r * 0.2), r * 0.65, paint);
    canvas.drawRect(
      Rect.fromCenter(
        center: center + Offset(0, r * 0.45),
        width: r * 2.4,
        height: r * 0.6,
      ),
      paint,
    );
    canvas.restore();
  }

  static void _paintRainy(Canvas canvas, Size size) {
    _gradient(canvas, size, [const Color(0xFF4A5568), const Color(0xFF232B36)]);
    _drawCloud(
      canvas,
      Offset(size.width * 0.3, size.height * 0.22),
      size.shortestSide * 0.2,
      Colors.white,
      alpha: 0.18,
    );
    _drawCloud(
      canvas,
      Offset(size.width * 0.68, size.height * 0.16),
      size.shortestSide * 0.16,
      Colors.white,
      alpha: 0.18,
    );
    final rnd = Random(5);
    final drop = Paint()
      ..color = const Color(0xFFAFC9E8).withValues(alpha: 0.55)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 30; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = size.height * (0.4 + rnd.nextDouble() * 0.55);
      final length = 24.0 + rnd.nextDouble() * 20;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - length * 0.25, y + length),
        drop,
      );
    }
  }

  static void _paintSnowy(Canvas canvas, Size size) {
    _gradient(canvas, size, [const Color(0xFFB9CBE0), const Color(0xFFEFF4F9)]);
    final ground = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.86, size.width, size.height * 0.14),
      ground,
    );
    final rnd = Random(6);
    final flakePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 22; i++) {
      final center = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height * 0.8,
      );
      final r = 6.0 + rnd.nextDouble() * 6;
      for (var a = 0; a < 3; a++) {
        final angle = a * pi / 3;
        canvas.drawLine(
          center - Offset(cos(angle), sin(angle)) * r,
          center + Offset(cos(angle), sin(angle)) * r,
          flakePaint,
        );
      }
    }
  }

  static void _paintMountains(Canvas canvas, Size size) {
    _gradient(canvas, size, [const Color(0xFFF7B4A0), const Color(0xFFF2E0A8)]);
    final sun = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.38),
      size.shortestSide * 0.12,
      sun,
    );
    const layers = [
      (color: Color(0xFF8E7FB0), heightFactor: 0.55),
      (color: Color(0xFF6C5B96), heightFactor: 0.4),
      (color: Color(0xFF453A6B), heightFactor: 0.28),
    ];
    for (final layer in layers) {
      final path = Path()
        ..moveTo(0, size.height)
        ..lineTo(0, size.height * (1 - layer.heightFactor * 0.4));
      final peaks = 4;
      for (var i = 0; i <= peaks; i++) {
        final x = size.width * (i / peaks);
        final peakUp = i.isOdd;
        final y = size.height * (1 - layer.heightFactor * (peakUp ? 1 : 0.55));
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = layer.color);
    }
  }
}
