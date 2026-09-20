import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A digital time widget, styled after a phone home screen's own digital
/// clock widget — a large bold time with a smaller date beneath it, both
/// reading directly against the deck's own background rather than a card
/// behind them, the same choice [MonthCalendar] makes and for the same
/// reason.
///
/// Shared between the host's grid editor and the client's own deck — see
/// [AnalogClock]'s own doc comment for why.
class DigitalClock extends StatefulWidget {
  const DigitalClock({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<DigitalClock> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Only the minute is ever shown, so this only has to notice a minute
    // boundary passing — aligned to it rather than a plain periodic timer,
    // same reasoning as AnalogClock's own per-second alignment.
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    final untilNextMinute = Duration(
      seconds: 59 - now.second,
      milliseconds: 1000 - now.millisecond,
    );
    _ticker = Timer(untilNextMinute, () {
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
    final locale = Localizations.localeOf(context).toString();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final timeColor = dark ? Colors.white : Colors.black87;
    final dateColor = dark
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);

    // Hm respects the locale's own 12/24-hour convention, the same way
    // MonthCalendar's yMMMM/narrowWeekdays follow the locale rather than a
    // fixed format.
    final timeText = DateFormat.Hm(locale).format(_now);
    final dateText = DateFormat.MMMEd(locale).format(_now);

    const margin = 12.0;
    final outerWidth = math.max(widget.width - margin * 2, 0.0);
    final outerHeight = math.max(widget.height - margin * 2, 0.0);

    return Semantics(
      label:
          'Clock, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_now))}, $dateText',
      child: Padding(
        padding: const EdgeInsets.all(margin),
        child: SizedBox(
          width: outerWidth,
          height: outerHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // FittedBox rather than a fixed font size: a widget's span can
              // be anywhere from one cell to the whole grid, and the time
              // should fill whatever width it's given rather than clipping
              // on a narrow one or looking tiny on a wide one.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  timeText,
                  style: TextStyle(
                    color: timeColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 56,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  dateText,
                  style: TextStyle(
                    color: dateColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
