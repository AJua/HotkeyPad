import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A month calendar grid, styled after iOS StandBy's calendar widget —
/// today circled in the app's own accent color, the card itself a dark or
/// light card following [Theme.of]'s own brightness — see [AnalogClock]'s
/// own doc comment for why.
///
/// Shared between the host's grid editor and the client's own deck — see
/// [AnalogClock]'s own doc comment for why.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  Timer? _midnightCheck;
  DateTime _today = _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  @override
  void initState() {
    super.initState();
    // A deck left open across midnight should still show the right day —
    // checked well below the cost of a full redraw loop, since a month
    // grid only ever needs to change once every 24 hours.
    _midnightCheck = Timer.periodic(const Duration(minutes: 1), (_) {
      final today = _dateOnly(DateTime.now());
      if (today != _today && mounted) setState(() => _today = today);
    });
  }

  @override
  void dispose() {
    _midnightCheck?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final materialL10n = MaterialLocalizations.of(context);
    final today = _today;
    final firstOfMonth = DateTime(today.year, today.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(today.year, today.month);

    // DateTime.weekday is 1 (Monday) .. 7 (Sunday); Flutter's own
    // firstDayOfWeekIndex is 0 (Sunday) .. 6 (Saturday) — both need
    // rebasing onto the same 0-based, locale-correct week start before
    // the leading blank cells can be counted.
    final firstWeekdaySunday0 = firstOfMonth.weekday % 7;
    final weekStart = materialL10n.firstDayOfWeekIndex;
    final leadingBlanks = (firstWeekdaySunday0 - weekStart + 7) % 7;

    final weekdayLabels = List<String>.generate(
      7,
      (i) => materialL10n.narrowWeekdays[(weekStart + i) % 7],
    );

    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? Colors.white : Colors.black87;
    final secondaryTextColor = dark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.5);
    final dayTextColor = dark
        ? Colors.white.withValues(alpha: 0.85)
        : Colors.black.withValues(alpha: 0.85);

    const margin = 12.0;
    final outerWidth = math.max(widget.width - margin * 2, 0.0);
    final outerHeight = math.max(widget.height - margin * 2, 0.0);
    // See AnalogClock's own doc comment on _blockScale for why this exists
    // and why it doesn't change how much of the grid this widget reserves.
    const blockScale = 0.9;
    final cardWidth = outerWidth * blockScale;
    final cardHeight = outerHeight * blockScale;
    // The margin is a Padding around the block rather than Container's own
    // `margin` property — see AnalogClock's own doc comment for why.
    //
    // A summary label on top of (not instead of) the day grid's own Text
    // widgets — those already read fine individually, but a screen reader
    // landing here otherwise has no single "what is this and which month"
    // announcement before it starts reading day numbers one by one.
    return Semantics(
      label: 'Calendar, ${DateFormat.yMMMMd(locale).format(today)}',
      child: Padding(
        padding: const EdgeInsets.all(margin),
        // No card behind the grid: it reads directly against the deck's own
        // background, the same as every other button — dark/light still
        // decides the text's own colors above, just not a backing fill.
        child: SizedBox(
          width: outerWidth,
          height: outerHeight,
          child: Center(
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: Column(
                // A card this size is usually taller than the header + weekday
                // row + day grid need, so the extra room is centered rather than
                // left pinned to the top.
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat.yMMMM(locale).format(today),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final label in weekdayLabels)
                        Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                        ),
                    itemCount: leadingBlanks + daysInMonth,
                    itemBuilder: (context, index) {
                      if (index < leadingBlanks) return const SizedBox.shrink();
                      final day = index - leadingBlanks + 1;
                      final isToday = day == today.day;
                      return Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: isToday
                              ? BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                )
                              : null,
                          child: Text(
                            '$day',
                            style: TextStyle(
                              color: isToday
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : dayTextColor,
                              fontSize: 12,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
