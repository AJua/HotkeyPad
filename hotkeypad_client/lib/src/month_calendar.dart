import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A month calendar grid, styled after iOS StandBy's calendar widget —
/// today circled in the app's own accent color. Always dark, for the same
/// reason as [AnalogClock]: it needs to read the same regardless of the
/// deck's own background.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({super.key, this.width = 220});

  final double width;

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

    return Container(
      width: widget.width,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xF01C1C1E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.yMMMM(locale).format(today),
            style: const TextStyle(
              color: Colors.white,
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
                        color: Colors.white.withValues(alpha: 0.5),
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                          : Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
