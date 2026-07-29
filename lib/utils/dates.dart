library;

const kMonthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const kMonthsUpper = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

const kWeekdaysFull = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

const kWeekdaysUpper = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool isToday(DateTime? d, {DateTime? now}) =>
    isSameDay(d, now ?? DateTime.now());

bool isFutureDay(DateTime d, {DateTime? now}) =>
    _midnight(d).isAfter(_midnight(now ?? DateTime.now()));

bool isPastDay(DateTime d, {DateTime? now}) =>
    _midnight(d).isBefore(_midnight(now ?? DateTime.now()));

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

String shortDate(DateTime d) => '${kMonthsShort[d.month - 1]} ${d.day}';

String shortDateUpper(DateTime d) => '${kMonthsUpper[d.month - 1]} ${d.day}';

String longDate(DateTime d) => '${kMonthsShort[d.month - 1]} ${d.day}, ${d.year}';

String monthYear(DateTime d) => '${kMonthsShort[d.month - 1]} ${d.year}';

String weekdayDate(DateTime d) =>
    '${kWeekdaysFull[d.weekday - 1]}, ${shortDate(d)}';

String dayLabel(DateTime d, {DateTime? now}) =>
    isToday(d, now: now) ? 'Today' : shortDate(d);

String isoDate(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');
