import '../models/catalog_exercises.dart';

class ExerciseSearch {
  final List<_Indexed> _index;

  ExerciseSearch(List<CatalogExercises> catalog)
      : _index = catalog.map(_Indexed.new).toList();

  static const Map<String, String> _phrases = {
    'upper chest': 'incline chest',
    'lower chest': 'decline chest',
    'hammer strength': 'machine',
  };

  static const Map<String, String> _words = {
    'db': 'dumbbell',
    'bb': 'barbell',
    'bw': 'bodyweight',
    'ohp': 'overhead press',
    'rdl': 'romanian deadlift',
    'pec': 'chest',
    'pecs': 'chest',
    'delt': 'shoulders',
    'delts': 'shoulders',
    'lats': 'back',
    'traps': 'shrug',
    'tris': 'triceps',
    'bis': 'biceps',
  };

  List<CatalogExercises> search(String query, {int limit = 40}) {
    final raw = query.trim().toLowerCase();
    if (raw.isEmpty) return const [];

    final expanded = _expand(raw);
    final tokens = expanded.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];

    final scored = <_Scored>[];
    for (final item in _index) {
      final rank = item.rank(raw, tokens);
      if (rank != null) scored.add(_Scored(item, rank));
    }

    scored.sort((a, b) {
      if (a.rank != b.rank) return a.rank - b.rank;
      final byLength = a.item.name.length - b.item.name.length;
      if (byLength != 0) return byLength;
      return a.item.name.compareTo(b.item.name);
    });

    return scored.take(limit).map((s) => s.item.exercise).toList();
  }

  static String _expand(String query) {
    var out = query;
    _phrases.forEach((from, to) => out = out.replaceAll(from, to));

    return out
        .split(RegExp(r'\s+'))
        .map((t) => _words[t] ?? t)
        .join(' ');
  }
}

class _Indexed {
  final CatalogExercises exercise;
  final String name;

  final String haystack;

  _Indexed(this.exercise)
      : name = (exercise.name ?? '').toLowerCase(),
        haystack = [
          exercise.name,
          exercise.equipment,
          exercise.category,
          exercise.muscleGroup,
        ].whereType<String>().join(' ').toLowerCase();

  int? rank(String raw, List<String> tokens) {
    if (name.startsWith(raw)) return 0;
    if (name.contains(raw)) return 1;

    if (tokens.every(name.contains)) return 2;

    if (tokens.every(haystack.contains)) return 3;

    return null;
  }
}

class _Scored {
  final _Indexed item;
  final int rank;
  const _Scored(this.item, this.rank);
}
