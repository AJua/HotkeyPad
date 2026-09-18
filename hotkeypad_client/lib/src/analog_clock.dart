import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A ticking analog clock face, styled after iOS StandBy's clock widget —
/// always dark, regardless of the deck's own theme or background, so it
/// reads the same whether the deck behind it is light, dark, or has a
/// photo background.
class AnalogClock extends StatefulWidget {
  const AnalogClock({super.key, this.size = 168, this.height});

  /// The clock face's own diameter — independent of [height], which only
  /// stretches the card around it.
  final double size;

  /// The card's total height, so it can be made flush with the deck's own
  /// slots — see [_DeckPageState._gridHeight]. Null keeps the card's
  /// height to just the face plus its padding, same as before this
  /// existed.
  final double? height;

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
    final untilNextSecond = Duration(
      milliseconds: 1000 - now.millisecond,
    );
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
    return Container(
      width: widget.size + 36,
      height: widget.height ?? widget.size + 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xF01C1C1E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: _ClockPainter(_now)),
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

    final hourAngle =
        (time.hour % 12 + time.minute / 60) * math.pi / 6;
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
