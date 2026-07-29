library;

String trimWeight(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final oneDecimal = v.toStringAsFixed(1);
  return double.parse(oneDecimal) == v ? oneDecimal : v.toStringAsFixed(2);
}

String titleCase(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';

  return s
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .map(_capitalizeWord)
      .join(' ');
}

String _capitalizeWord(String word) => word
    .split('-')
    .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
    .join('-');

String detailLine(Iterable<String?> parts) =>
    parts.map(titleCase).where((p) => p.isNotEmpty).join(' · ');

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
