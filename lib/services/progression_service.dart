import 'package:liftr/models/models.dart';
import 'package:liftr/services/exercise_setup_service.dart';
import 'package:liftr/utils/dates.dart';
import 'package:liftr/utils/progression.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseSessionHistory {
  final String sessionId;
  final DateTime sessionDate;

  final List<ExerciseSets> sets;

  final String? setupId;

  const ExerciseSessionHistory({
    required this.sessionId,
    required this.sessionDate,
    required this.sets,
    required this.setupId,
  });
}

const int kMinSessionsForSuggestion = 2;

class ProgressionHint {
  final ProgressionSuggestion? suggestion;

  final int sessionsSeen;

  final ResolvedIncrement increment;

  final ExerciseSessionHistory lastSession;

  final bool plateau;

  const ProgressionHint({
    required this.suggestion,
    required this.sessionsSeen,
    required this.increment,
    required this.lastSession,
    required this.plateau,
  });

  bool get hasEnoughHistory => sessionsSeen >= kMinSessionsForSuggestion;
}

class ProgressionService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

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

  static Future<ProgressionHint?> hintFor(
    CatalogExercises exercise, {
    String? selectedSetupId,
  }) async {
    final catalogId = exercise.catalogId;
    if (catalogId == null) return null;

    final history = await recentHistory(catalogId, limit: 5);
    if (history.isEmpty) return null;

    final recent = history.first;
    final recentTop = topSet(recent.sets);
    if (recentTop == null) return null;

    final resolved = await increment(
      catalogId: catalogId,
      equipment: exercise.equipment,
      assignedSetupId: selectedSetupId ?? recent.setupId,
    );

    final enough = history.length >= kMinSessionsForSuggestion;

    final suggestion = !enough
        ? null
        : suggestProgression(
            recentTop: recentTop,
            previousTop: topSet(history[1].sets),
            daysSinceLast: _daysSince(recent.sessionDate),
            recentSets: recent.sets,
            increment: resolved.incrementKg,
            minWeightKg: resolved.minWeightKg,
          );

    final topSets = history
        .map((h) => topSet(h.sets))
        .whereType<ExerciseSets>()
        .toList();

    return ProgressionHint(
      suggestion: suggestion,
      sessionsSeen: history.length,
      increment: resolved,
      lastSession: recent,
      plateau: looksLikePlateau(topSets),
    );
  }

  static int _daysSince(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final then = DateTime(date.year, date.month, date.day);
    return today.difference(then).inDays;
  }
}
