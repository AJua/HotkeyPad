import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A ticking analog clock face, styled after iOS StandBy's clock widget —
/// a dark card in dark mode, a light one in light mode, following
/// [Theme.of]'s own brightness rather than the deck's background image
/// (which can be light or dark regardless of the theme) — same reasoning
/// as [MonthCalendar]'s own card.
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

  /// The rendered block's own size relative to what [margin] leaves —
  /// shrinks the visible face without reserving any more of the grid than
  /// before, the leftover simply becoming extra breathing room around it.
  static const _blockScale = 0.9;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const margin = 12.0;
    final outerWidth = math.max(widget.width - margin * 2, 0.0);
    final outerHeight = math.max(widget.height - margin * 2, 0.0);
    final faceWidth = outerWidth * _blockScale;
    final faceHeight = outerHeight * _blockScale;
    // The margin is a Padding around the block rather than Container's own
    // `margin` property: Container merges an explicit width/height into a
    // *tight* constraint that would then override — not compose with — a
    // margin's own deflate, so the block wouldn't actually shrink. Sizing
    // the block itself to widget.width/height minus the margin, and only
    // then wrapping it in that much Padding, keeps this explicit rather
    // than depending on whatever constraint happens to reach here.
    return Padding(
      padding: const EdgeInsets.all(margin),
      // No card behind the face: it reads directly against the deck's own
      // background, the same as every other button — dark/light still
      // decides the face's own colors below, just not a backing fill.
      child: SizedBox(
        width: outerWidth,
        height: outerHeight,
        // Center, not the outer SizedBox, is what actually shrinks the
        // face by _blockScale — the outer SizedBox still claims the full
        // outerWidth x outerHeight so nothing else in the grid reflows.
        child: Center(
          child: SizedBox(
            width: faceWidth,
            height: faceHeight,
            // A childless CustomPaint sizes itself to this explicitly —
            // without it, Center's own loose constraint would leave it
            // nothing to measure against and it would collapse to zero
            // size, painting nothing.
            child: CustomPaint(
              size: Size(faceWidth, faceHeight),
              painter: _ClockPainter(
                _now,
                dark: dark,
                accent: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Deliberately not a copy of iOS StandBy's own clock face: needle-shaped
/// (tapered, not blunt-rectangular) hands read their exact angle more
/// precisely at a glance, the 12/3/6/9 cardinal points are emphasized so
/// orientation doesn't require reading every number, and the accent comes
/// from the app's own theme rather than a fixed brand color.
class _ClockPainter extends CustomPainter {
  _ClockPainter(this.time, {required this.dark, required this.accent});

  final DateTime time;
  final bool dark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final faceColor = dark ? Colors.white : Colors.black87;
    final tickPaint = Paint()..color = faceColor.withValues(alpha: 0.9);

    // A thin ring tracking progress through the current hour — a glance
    // reads "how far into the hour" without doing the minute-hand math,
    // and it's the one element with no equivalent on the face this is
    // otherwise styled after.
    final progress = (time.minute + time.second / 60) / 60;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.985),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.026
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < 60; i++) {
      final angle = i * math.pi / 30;
      final isHour = i % 5 == 0;
      // The 12/3/6/9 points get their own longer, bolder mark so the four
      // main compass directions stand out before reading any number.
      final isCardinal = i % 15 == 0;
      final outer = radius * 0.94;
      final inner = isCardinal
          ? radius * 0.79
          : isHour
          ? radius * 0.82
          : radius * 0.90;
      final p1 = center + Offset(math.sin(angle), -math.cos(angle)) * outer;
      final p2 = center + Offset(math.sin(angle), -math.cos(angle)) * inner;
      tickPaint.strokeWidth = isCardinal
          ? 4.0
          : isHour
          ? 3.0
          : 1.6;
      canvas.drawLine(p1, p2, tickPaint);
    }

    for (var hour = 1; hour <= 12; hour++) {
      final angle = hour * math.pi / 6;
      final isCardinal = hour % 3 == 0;
      final labelRadius = radius * 0.68;
      final offset =
          center + Offset(math.sin(angle), -math.cos(angle)) * labelRadius;
      final painter = TextPainter(
        text: TextSpan(
          text: '$hour',
          style: TextStyle(
            color: faceColor,
            fontSize: isCardinal ? radius * 0.21 : radius * 0.17,
            fontWeight: isCardinal ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
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

    // Tapered needles rather than uniform-width bars: the point at the tip
    // is what makes reading the exact angle unambiguous.
    _drawTaperedHand(
      canvas,
      center,
      hourAngle,
      length: radius * 0.5,
      baseWidth: radius * 0.115,
      tipWidth: radius * 0.03,
      color: faceColor,
    );
    _drawTaperedHand(
      canvas,
      center,
      minuteAngle,
      length: radius * 0.74,
      baseWidth: radius * 0.085,
      tipWidth: radius * 0.02,
      color: faceColor,
    );
    _drawHairlineHand(
      canvas,
      center,
      secondAngle,
      length: radius * 0.78,
      color: accent,
      width: radius * 0.018,
    );

    canvas.drawCircle(center, radius * 0.05, Paint()..color = faceColor);
    canvas.drawCircle(center, radius * 0.022, Paint()..color = accent);
  }

  /// A hand shaped like a needle — wide at the pivot, narrowing to a point
  /// at the tip — rather than iOS StandBy's own uniform-width bar.
  void _drawTaperedHand(
    Canvas canvas,
    Offset center,
    double angle, {
    required double length,
    required double baseWidth,
    required double tipWidth,
    required Color color,
  }) {
    final dir = Offset(math.sin(angle), -math.cos(angle));
    final perp = Offset(-dir.dy, dir.dx);
    final tip = center + dir * length;
    final baseHalf = baseWidth / 2;
    final tipHalf = tipWidth / 2;
    final path = Path()
      ..moveTo(center.dx + perp.dx * baseHalf, center.dy + perp.dy * baseHalf)
      ..lineTo(tip.dx + perp.dx * tipHalf, tip.dy + perp.dy * tipHalf)
      ..lineTo(tip.dx - perp.dx * tipHalf, tip.dy - perp.dy * tipHalf)
      ..lineTo(center.dx - perp.dx * baseHalf, center.dy - perp.dy * baseHalf)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  /// The second hand: thin enough that a needle shape would add nothing,
  /// so it stays a plain hairline — same treatment as before, just in the
  /// theme's own accent rather than a fixed color.
  void _drawHairlineHand(
    Canvas canvas,
    Offset center,
    double angle, {
    required double length,
    required Color color,
    required double width,
  }) {
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
      oldDelegate.time.second != time.second ||
      oldDelegate.dark != dark ||
      oldDelegate.accent != accent;
}
