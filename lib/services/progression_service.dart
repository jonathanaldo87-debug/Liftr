import 'package:liftr/models/models.dart';
import 'package:liftr/services/exercise_setup_service.dart';
import 'package:liftr/utils/dates.dart';
import 'package:liftr/utils/progression.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One past appearance of an exercise: the sets done, the day, and which setup
/// they were logged on (usually none — see migration 017).
///
/// The unit the progression rule reasons over. Sets arrive ordered by set
/// number so [setStructure] and [topSet] can be handed them directly.
class ExerciseSessionHistory {
  final String sessionId;
  final DateTime sessionDate;

  /// This exercise's sets that day, in set-number order.
  final List<ExerciseSets> sets;

  /// `workout_exercises.setup_id` — the stack it was recorded on, or null for
  /// "not said", which is the common and honest case.
  final String? setupId;

  const ExerciseSessionHistory({
    required this.sessionId,
    required this.sessionDate,
    required this.sets,
    required this.setupId,
  });
}

/// Everything the hint card needs, assembled once so the screen renders without
/// re-querying: the suggestion itself, the increment it was sized with (so the
/// card can nudge the user to record a setup when it defaulted), the last
/// session to summarise, and whether the lift has plateaued.
class ProgressionHint {
  /// The next-time suggestion, or null when history exists but nothing was
  /// rankable (e.g. the last session logged no reps).
  final ProgressionSuggestion? suggestion;

  /// How the sizing step was chosen — [ResolvedIncrement.isDefaulted] and
  /// [ResolvedIncrement.isAmbiguous] drive the "set this up for a sharper
  /// suggestion" note.
  final ResolvedIncrement increment;

  /// The most recent session, for the "last time: 40×12, 40×10" summary line.
  final ExerciseSessionHistory lastSession;

  /// Estimated strength has gone flat across recent sessions — show the extra
  /// deload/rep-range warning beneath the suggestion.
  final bool plateau;

  const ProgressionHint({
    required this.suggestion,
    required this.increment,
    required this.lastSession,
    required this.plateau,
  });
}

/// Builds the weight/rep hint shown before a gym set is logged, from the user's
/// own recent history for that exercise. Rule-based — no LLM, no effort input.
///
/// The arithmetic is pure and lives in `utils/progression.dart`; this class is
/// the IO around it — fetching the history and the setup — plus the wiring that
/// turns them into a suggestion.
///
/// Fail-soft throughout: a hint is an enhancement, and failing to build one must
/// never block logging. Every fetch returns empty/neutral rather than throwing,
/// so the screen simply shows no hint.
class ProgressionService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  /// The user's most recent sessions *before today* in which this exercise
  /// appears, newest first, at most [limit].
  ///
  /// Earlier days only: what you're logging right now isn't history to compare
  /// against, and today's session is the one you're logging into. This used to
  /// filter on `is_active = false` for the same reason, which stopped meaning
  /// anything once the app dropped the active-session flag — every row would
  /// have passed it, today's included, and the hint would have started
  /// comparing you against the sets you'd just entered.
  ///
  /// Gym only: running has no sets. There's one gym session per day (a unique
  /// index guarantees it), so `session_date` is an unambiguous ordering.
  ///
  /// Returns an empty list on any failure or when the exercise is new to the
  /// user — the caller reads that as "no hint".
  static Future<List<ExerciseSessionHistory>> recentHistory(
    String catalogId, {
    int limit = 2,
  }) async {
    try {
      final data = await _db
          .from('workout_exercises')
          .select('setup_id, '
              'exercise_sets(set_id, exercise_id, set_number, weight_kg, reps, '
              'logged_at), '
              'workout_sessions!inner(session_id, session_date, user_id, '
              'discipline)')
          .eq('catalog_id', catalogId)
          .eq('workout_sessions.user_id', _userId)
          .eq('workout_sessions.discipline', 'gym')
          .lt('workout_sessions.session_date', isoDate(DateTime.now()));

      // Group by session, since an exercise can in principle appear more than
      // once in a day; merge those sets and keep any setup that was recorded.
      final bySession = <String, ExerciseSessionHistory>{};
      for (final row in data) {
        final session = row['workout_sessions'] as Map<String, dynamic>?;
        final sessionId = session?['session_id'] as String?;
        final dateStr = session?['session_date'] as String?;
        if (sessionId == null || dateStr == null) continue;

        final rawSets = (row['exercise_sets'] as List?) ?? const [];
        final sets = rawSets
            .whereType<Map<String, dynamic>>()
            .map(ExerciseSets.fromJson)
            .toList()
          ..sort((a, b) => (a.setNumber ?? 0).compareTo(b.setNumber ?? 0));

        final existing = bySession[sessionId];
        if (existing == null) {
          bySession[sessionId] = ExerciseSessionHistory(
            sessionId: sessionId,
            sessionDate: DateTime.parse(dateStr),
            sets: sets,
            setupId: row['setup_id'] as String?,
          );
        } else {
          bySession[sessionId] = ExerciseSessionHistory(
            sessionId: sessionId,
            sessionDate: existing.sessionDate,
            sets: [...existing.sets, ...sets]
              ..sort((a, b) => (a.setNumber ?? 0).compareTo(b.setNumber ?? 0)),
            setupId: existing.setupId ?? row['setup_id'] as String?,
          );
        }
      }

      final sessions = bySession.values.toList()
        ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
      return sessions.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The weight step to size this exercise's suggestion by, with the story of
  /// where it came from so the hint can explain itself.
  ///
  /// Bodyweight (from `exercise_catalog.equipment`) short-circuits to a null
  /// step. Otherwise it loads the applicable setups and defers the choice to the
  /// pure [resolveIncrement].
  ///
  /// [assignedSetupId] is the setup a specific logged set was done on, when the
  /// caller has it (from [ExerciseSessionHistory.setupId]); pass null to resolve
  /// purely from the applicable setups.
  static Future<ResolvedIncrement> increment({
    required String catalogId,
    required String? equipment,
    String? assignedSetupId,
  }) async {
    final isBodyweight = (equipment ?? '').toLowerCase().trim() == 'bodyweight';
    if (isBodyweight) {
      return resolveIncrement(
        setups: const [],
        isBodyweight: true,
      );
    }

    final setups = await ExerciseSetupService.getSetups(
      catalogId: catalogId,
      equipment: equipment,
    );

    return resolveIncrement(
      setups: setups,
      assignedSetupId: assignedSetupId,
      isBodyweight: false,
    );
  }

  /// The full hint for the exercise being logged, or null when there's no
  /// history to build one from — a new lift, or a failed load. The screen reads
  /// null as "show no hint, log freely".
  ///
  /// Fetches up to five recent sessions: the last two drive the smoothed up/down
  /// decision, and all five feed plateau detection. The day gap and the
  /// increment are resolved here — the only clock and IO the pure rule needs —
  /// then handed to [suggestProgression].
  static Future<ProgressionHint?> hintFor(CatalogExercises exercise) async {
    final catalogId = exercise.catalogId;
    if (catalogId == null) return null;

    final history = await recentHistory(catalogId, limit: 5);
    if (history.isEmpty) return null;

    final recent = history.first;
    final recentTop = topSet(recent.sets);
    if (recentTop == null) return null; // last session logged nothing rankable

    final resolved = await increment(
      catalogId: catalogId,
      equipment: exercise.equipment,
      assignedSetupId: recent.setupId,
    );

    final suggestion = suggestProgression(
      recentTop: recentTop,
      previousTop: history.length > 1 ? topSet(history[1].sets) : null,
      daysSinceLast: _daysSince(recent.sessionDate),
      recentSets: recent.sets,
      increment: resolved.incrementKg,
    );

    final topSets = history
        .map((h) => topSet(h.sets))
        .whereType<ExerciseSets>()
        .toList();

    return ProgressionHint(
      suggestion: suggestion,
      increment: resolved,
      lastSession: recent,
      plateau: looksLikePlateau(topSets),
    );
  }

  /// Whole days between [date] and today, both taken at day granularity so a
  /// session late yesterday and one early today read as one day apart, not zero.
  static int _daysSince(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final then = DateTime(date.year, date.month, date.day);
    return today.difference(then).inDays;
  }
}
