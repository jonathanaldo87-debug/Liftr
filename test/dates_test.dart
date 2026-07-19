import 'package:flutter_test/flutter_test.dart';
import 'package:liftr/utils/dates.dart';

void main() {
  group('name tables', () {
    test('cover every month and weekday', () {
      expect(kMonthsShort.length, 12);
      expect(kMonthsUpper.length, 12);
      expect(kWeekdaysFull.length, 7);
      expect(kWeekdaysUpper.length, 7);
    });

    test('are indexed so month 1 is January and weekday 1 is Monday', () {
      // Dart's DateTime.weekday runs 1 = Monday .. 7 = Sunday, so a table that
      // starts on Sunday would be off by one every day of the week.
      final jan1 = DateTime(2026, 1, 1);
      expect(kMonthsShort[jan1.month - 1], 'Jan');

      final monday = DateTime(2026, 7, 20); // a Monday
      expect(monday.weekday, DateTime.monday);
      expect(kWeekdaysFull[monday.weekday - 1], 'Monday');

      final sunday = DateTime(2026, 7, 19);
      expect(sunday.weekday, DateTime.sunday);
      expect(kWeekdaysFull[sunday.weekday - 1], 'Sunday');
    });

    test('uppercase tables match the short ones', () {
      for (var i = 0; i < 12; i++) {
        expect(kMonthsUpper[i], kMonthsShort[i].toUpperCase());
      }
    });
  });

  group('isSameDay', () {
    test('ignores the time of day', () {
      expect(
        isSameDay(DateTime(2026, 7, 19, 6), DateTime(2026, 7, 19, 23, 59)),
        isTrue,
      );
    });

    test('compares the year, so last March 3rd is not this one', () {
      // The bug this replaced: a copy that checked only month and day made
      // every March 3rd read as "Today".
      expect(isSameDay(DateTime(2025, 3, 3), DateTime(2026, 3, 3)), isFalse);
    });

    test('is false for nulls rather than throwing', () {
      expect(isSameDay(null, DateTime(2026, 7, 19)), isFalse);
      expect(isSameDay(DateTime(2026, 7, 19), null), isFalse);
      expect(isSameDay(null, null), isFalse);
    });
  });

  group('isToday', () {
    test('takes an injected clock so it does not depend on when tests run', () {
      final now = DateTime(2026, 7, 19, 14);
      expect(isToday(DateTime(2026, 7, 19, 5), now: now), isTrue);
      expect(isToday(DateTime(2026, 7, 18, 23, 59), now: now), isFalse);
      expect(isToday(null, now: now), isFalse);
    });
  });

  group('formats', () {
    final d = DateTime(2026, 7, 19);

    test('shortDate and its uppercase twin', () {
      expect(shortDate(d), 'Jul 19');
      expect(shortDateUpper(d), 'JUL 19');
    });

    test('longDate carries the year', () {
      expect(longDate(d), 'Jul 19, 2026');
    });

    test('monthYear', () {
      expect(monthYear(d), 'Jul 2026');
    });

    test('weekdayDate names the day', () {
      expect(weekdayDate(d), 'Sunday, Jul 19');
    });

    test('dayLabel says Today only when it is', () {
      expect(dayLabel(d, now: d), 'Today');
      expect(dayLabel(d, now: DateTime(2026, 7, 20)), 'Jul 19');
      expect(dayLabel(d, now: DateTime(2025, 7, 19)), 'Jul 19');
    });

    test('handles both ends of the year without falling off the table', () {
      expect(shortDate(DateTime(2026, 1, 1)), 'Jan 1');
      expect(shortDate(DateTime(2026, 12, 31)), 'Dec 31');
    });
  });

  group('isoDate', () {
    test('pads to yyyy-MM-dd', () {
      expect(isoDate(DateTime(2026, 7, 19)), '2026-07-19');
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(isoDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('never shifts the day the way toIso8601String would', () {
      // A local 00:30 must stay on its own date. Converting to UTC first would
      // roll it back a day for anyone east of UTC — and silently log a workout
      // against yesterday.
      final earlyMorning = DateTime(2026, 7, 19, 0, 30);
      expect(isoDate(earlyMorning), '2026-07-19');

      final lateNight = DateTime(2026, 7, 19, 23, 30);
      expect(isoDate(lateNight), '2026-07-19');
    });
  });
}
