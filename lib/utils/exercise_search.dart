import '../models/catalog_exercises.dart';

/// Ranked search over the ~900-exercise catalog.
///
/// The old filter was `name.contains(query)`, which fails the way people
/// actually type: "chest press machine" matched nothing, because no exercise is
/// *named* that — "machine" lives in the equipment column.
///
/// So: every word must appear somewhere in the exercise's name, equipment,
/// category or muscle group — in any order. Common gym shorthand is translated
/// onto the catalog's vocabulary first.
class ExerciseSearch {
  final List<_Indexed> _index;

  ExerciseSearch(List<CatalogExercises> catalog)
      : _index = catalog.map(_Indexed.new).toList();

  /// Multi-word gym phrases the catalog spells differently. Applied to the whole
  /// query string before it's split, so a word pair can be rewritten as a unit.
  ///
  /// Only phrases the catalog *doesn't* use verbatim belong here. "Pec Deck" is
  /// a real exercise name now, so rewriting it would break the exact match it
  /// used to rescue.
  static const Map<String, String> _phrases = {
    'upper chest': 'incline chest',
    'lower chest': 'decline chest',
    'hammer strength': 'machine',
  };

  /// Single-word shorthand. A token only needs to be a *substring* of the
  /// haystack, so most plurals take care of themselves — "quad" already finds
  /// "quads", "ham" finds "hamstrings". These are the cases where the letters
  /// genuinely differ.
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

  /// Best matches for [query], most relevant first.
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
      // Shorter names are the plainer variant: "Barbell Curl" over
      // "Barbell Curls Lying Against An Incline".
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

  /// Name plus every attribute worth searching, lowercased. Built once at load
  /// rather than per keystroke across 900 rows.
  final String haystack;

  _Indexed(this.exercise)
      : name = (exercise.name ?? '').toLowerCase(),
        haystack = [
          exercise.name,
          exercise.equipment,
          exercise.category,
          exercise.muscleGroup,
        ].whereType<String>().join(' ').toLowerCase();

  /// Lower is better; null means no match.
  int? rank(String raw, List<String> tokens) {
    if (name.startsWith(raw)) return 0;
    if (name.contains(raw)) return 1;

    // Name alone satisfies every word — beats a match that leaned on equipment.
    if (tokens.every(name.contains)) return 2;

    // "chest press machine": `machine` comes from the equipment column.
    if (tokens.every(haystack.contains)) return 3;

    return null;
  }
}

class _Scored {
  final _Indexed item;
  final int rank;
  const _Scored(this.item, this.rank);
}
