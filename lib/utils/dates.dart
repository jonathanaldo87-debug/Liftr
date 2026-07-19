/// Date names and the handful of date formats the app actually shows.
///
/// The month array had been copy-pasted seven times across four files, and the
/// "Today, or else Jul 19" helper three times — once with the year comparison
/// missing, so any March 3rd read as "Today". That's the real cost of the
/// duplication: the copies drift, and the broken one looks exactly like the
/// working ones.
///
/// Pure and dependency-free, so it's testable without a widget tree. Deliberately
/// not `intl`: these are four fixed formats in one language, and adding a
/// localisation dependency to render "Jul 19" would be the larger commitment.
library;

/// Short month names, indexed by `month - 1`.
const kMonthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Uppercase months, for the section headers that shout.
const kMonthsUpper = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// Weekday names, indexed by `weekday - 1` — Dart's `DateTime.weekday` is
/// 1 = Monday through 7 = Sunday, so Monday leads rather than Sunday.
const kWeekdaysFull = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

/// Uppercase short weekdays, for the calendar strip.
const kWeekdaysUpper = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// Whether two dates fall on the same day.
///
/// Compares the year as well as the month and day. One of the copies this
/// replaced didn't, which made every March 3rd "Today".
bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Whether [d] is today. Takes [now] so tests don't depend on the wall clock.
bool isToday(DateTime? d, {DateTime? now}) =>
    isSameDay(d, now ?? DateTime.now());

/// "Jul 19".
String shortDate(DateTime d) => '${kMonthsShort[d.month - 1]} ${d.day}';

/// "JUL 19" — the section-header form.
String shortDateUpper(DateTime d) => '${kMonthsUpper[d.month - 1]} ${d.day}';

/// "Jul 19, 2026". The year is worth spelling out on a screen you reached by
/// picking a date, where "Jul 19" alone leaves you wondering which one.
String longDate(DateTime d) => '${kMonthsShort[d.month - 1]} ${d.day}, ${d.year}';

/// "Jul 2026".
String monthYear(DateTime d) => '${kMonthsShort[d.month - 1]} ${d.year}';

/// "Saturday, Jul 19".
String weekdayDate(DateTime d) =>
    '${kWeekdaysFull[d.weekday - 1]}, ${shortDate(d)}';

/// "Today" when it is, "Jul 19" otherwise.
String dayLabel(DateTime d, {DateTime? now}) =>
    isToday(d, now: now) ? 'Today' : shortDate(d);

/// `2026-07-19` — the wire format Postgres `date` columns expect.
///
/// Built by hand rather than via `toIso8601String()`, which would append a time
/// and a zone the column doesn't want, and would shift the day for anyone east
/// of UTC.
String isoDate(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');
