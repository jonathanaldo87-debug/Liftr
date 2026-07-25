/// Display formatting for catalog values and weights.
///
/// The catalog stores `equipment`, `category` and `muscle_group` lowercase —
/// that's the canonical form the import wrote, and what the name_key normalizer
/// and the icon lookups both key off. Capitalizing is a *display* concern, so it
/// happens here rather than in the database.
library;

/// A weight with no more decimals than it needs: 70 → "70", 72.5 → "72.5",
/// 1.25 → "1.25".
///
/// Two decimals rather than one, because 1.25 is a real step on real plate sets
/// and rounding it to "1.3" is worse than cosmetic here: the setup sheet puts
/// this string straight back into the step field, so a rounded display would
/// save 1.3 kg as the step and every suggestion built on it would be
/// unloadable.
String trimWeight(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final oneDecimal = v.toStringAsFixed(1);
  return double.parse(oneDecimal) == v ? oneDecimal : v.toStringAsFixed(2);
}

/// "bodyweight" → "Bodyweight", "lower_back" → "Lower Back".
String titleCase(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';

  // Underscores are separators in muscle_group ("lower_back"), not characters
  // anyone wants to read.
  return s
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .map(_capitalizeWord)
      .join(' ');
}

/// Hyphenated words capitalize on both sides, so "t-bar" reads "T-Bar".
String _capitalizeWord(String word) => word
    .split('-')
    .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
    .join('-');

/// The "Machine · Chest" line under an exercise name. Empty parts drop out
/// rather than leaving a dangling separator.
String detailLine(Iterable<String?> parts) =>
    parts.map(titleCase).where((p) => p.isNotEmpty).join(' · ');

/// The icon for an exercise.
///
/// Keyed off `muscle_group` (chest, back, quads, …), not `category`. The curated
/// catalog redefined `category` as a movement pattern — push / pull / legs /
/// core — so the old body-part switch would fall through to the default on
/// nearly every row. `category` remains as a coarse fallback.
String exerciseEmoji(String? category, String? muscleGroup) {
  switch ((muscleGroup ?? '').toLowerCase()) {
    case 'chest':
      return '🏋️';
    case 'back':
      return '🔙';
    case 'lower_back':
      return '🔙';
    case 'shoulders':
      return '🤸';
    case 'biceps':
    case 'triceps':
    case 'forearms':
      return '💪';
    case 'quads':
    case 'hamstrings':
    case 'calves':
      return '🦵';
    case 'glutes':
      return '🍑';
    case 'abs':
      return '🧘';
    case 'neck':
      return '🙆';
  }

  switch ((category ?? '').toLowerCase()) {
    case 'push':
      return '🏋️';
    case 'pull':
      return '🔙';
    case 'legs':
      return '🦵';
    case 'core':
      return '🧘';
    case 'cardio':
      return '🏃';
    default:
      return '🏋️';
  }
}
