import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A ticking analog clock face, styled after iOS StandBy's clock widget —
/// always dark, regardless of the deck's own theme or background, so it
/// reads the same whether the deck behind it is light, dark, or has a
/// photo background.
///
/// Shared between the host's grid editor and the client's own deck — see
/// [DeckGridView] — so a [WidgetItem] looks the same regardless of which
/// one is rendering it; only [width]/[height] differ, driven by whatever
/// row/column span its slot was actually given.
class AnalogClock extends StatefulWidget {
  const AnalogClock({super.key, required this.width, required this.height});

  /// The card's own size — not necessarily square, unlike a single cell:
  /// a span wider than tall (or the reverse) still centers a circular face
  /// within it, via [_ClockPainter]'s own use of the shorter side.
  final double width;
  final double height;

  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Aligned to the next whole second rather than a plain 1s periodic
    // timer, so the second hand doesn't visibly drift against a real
    // clock the longer this stays open.
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    final untilNextSecond = Duration(milliseconds: 1000 - now.millisecond);
    _ticker = Timer(untilNextSecond, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleNextTick();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const margin = 12.0;
    final cardWidth = math.max(widget.width - margin * 2, 0.0);
    final cardHeight = math.max(widget.height - margin * 2, 0.0);
    // The margin is a Padding around the card rather than Container's own
    // `margin` property: Container merges an explicit width/height into a
    // *tight* constraint that would then override — not compose with — a
    // margin's own deflate, so the card wouldn't actually shrink. Sizing
    // the card itself to widget.width/height minus the margin, and only
    // then wrapping it in that much Padding, keeps this explicit rather
    // than depending on whatever constraint happens to reach here.
    return Padding(
      padding: const EdgeInsets.all(margin),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: const Color(0xF01C1C1E),
          borderRadius: BorderRadius.circular(24),
        ),
        // A childless CustomPaint sizes itself to this explicitly — without
        // it, Container's own `alignment` (needed when it had a smaller
        // SizedBox child) would hand it *loose* constraints, and with no
        // child of its own to measure, it would collapse to zero size and
        // paint nothing at all, leaving only the card's plain background.
        child: CustomPaint(
          size: Size(cardWidth, cardHeight),
          painter: _ClockPainter(_now),
        ),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter(this.time);

  final DateTime time;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final tickPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final numberStyle = TextStyle(
      color: Colors.white,
      fontSize: radius * 0.18,
      fontWeight: FontWeight.w600,
    );

    for (var i = 0; i < 60; i++) {
      final angle = i * math.pi / 30;
      final isHour = i % 5 == 0;
      final outer = radius * 0.96;
      final inner = isHour ? radius * 0.84 : radius * 0.91;
      final p1 = center + Offset(math.sin(angle), -math.cos(angle)) * outer;
      final p2 = center + Offset(math.sin(angle), -math.cos(angle)) * inner;
      tickPaint.strokeWidth = isHour ? 2.4 : 1.2;
      canvas.drawLine(p1, p2, tickPaint);
    }

    for (var hour = 1; hour <= 12; hour++) {
      final angle = hour * math.pi / 6;
      final labelRadius = radius * 0.72;
      final offset =
          center + Offset(math.sin(angle), -math.cos(angle)) * labelRadius;
      final painter = TextPainter(
        text: TextSpan(text: '$hour', style: numberStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        offset - Offset(painter.width / 2, painter.height / 2),
      );
    }

    final hourAngle = (time.hour % 12 + time.minute / 60) * math.pi / 6;
    final minuteAngle = (time.minute + time.second / 60) * math.pi / 30;
    final secondAngle = time.second * math.pi / 30;

    _drawHand(
      canvas,
      center,
      hourAngle,
      radius * 0.5,
      Colors.white,
      radius * 0.045,
    );
    _drawHand(
      canvas,
      center,
      minuteAngle,
      radius * 0.72,
      Colors.white,
      radius * 0.032,
    );
    _drawHand(
      canvas,
      center,
      secondAngle,
      radius * 0.78,
      const Color(0xFFFF9F0A),
      radius * 0.014,
    );

    canvas.drawCircle(center, radius * 0.045, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius * 0.02,
      Paint()..color = const Color(0xFFFF9F0A),
    );
  }

  void _drawHand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    Color color,
    double width,
  ) {
    final end = center + Offset(math.sin(angle), -math.cos(angle)) * length;
    canvas.drawLine(
      center,
      end,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ClockPainter oldDelegate) =>
      oldDelegate.time.second != time.second;
}
