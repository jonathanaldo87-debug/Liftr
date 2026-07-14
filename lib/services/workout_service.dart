import 'package:liftr/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  static User? get currentUser => _db.auth.currentUser;

  // ── Sessions ────────────────────────────────────────────────

  /// The session logged on [date], or null.
  ///
  /// Deliberately not `.maybeSingle()`: that throws if a day somehow holds more
  /// than one session, which would take the whole home screen down. Taking the
  /// oldest keeps the screen up even if a duplicate slipped in before migration
  /// 006 added the unique index.
  static Future<WorkoutSessions?> getWorkoutSession(DateTime date) async {
    final data = await _db
        .from('workout_sessions')
        .select('session_id, session_date, name, notes, created_at, updated_at')
        .eq('user_id', _userId)
        .eq('session_date', _formatDate(date))
        .order('created_at', ascending: true)
        .limit(1);

    if (data.isEmpty) return null;
    return WorkoutSessions.fromJson(data.first);
  }

  static Future<String> createWorkoutSession(
      WorkoutSessionsPayload payload) async {
    final result = await _db
        .from('workout_sessions')
        .insert({
          'user_id': _userId,
          'name': payload.name,
          'session_date': _formatDate(payload.sessionDate),
          'notes': payload.notes,
        })
        .select('session_id')
        .single();
    return result['session_id'] as String;
  }

  /// The session for [date], creating it with [name] if there isn't one yet.
  ///
  /// Adding an exercise must never mint a second session for the same day. It
  /// used to, which is what broke adding a second exercise to a workout.
  static Future<String> getOrCreateSession(DateTime date, String name) async {
    final existing = await getWorkoutSession(date);
    final id = existing?.sessionId;
    if (id != null) return id;

    return createWorkoutSession(
      WorkoutSessionsPayload(sessionDate: date, name: name),
    );
  }

  static Future<void> updateWorkoutSession(
      String sessionId, WorkoutSessionsPayload payload) async {
    await _db.from('workout_sessions').update({
      'name': payload.name,
      'notes': payload.notes,
    }).eq('session_id', sessionId);
  }

  /// Deletes the session and everything hanging off it.
  ///
  /// Children go first and explicitly. If the foreign keys happen to cascade
  /// this is redundant but harmless; if they don't, it's the only thing keeping
  /// orphaned sets out of the database.
  static Future<void> deleteWorkoutSession(String sessionId) async {
    final exercises = await _db
        .from('workout_exercises')
        .select('exercise_id')
        .eq('session_id', sessionId);

    for (final e in exercises) {
      await _db
          .from('exercise_sets')
          .delete()
          .eq('exercise_id', e['exercise_id'] as String);
    }

    await _db.from('workout_exercises').delete().eq('session_id', sessionId);
    await _db.from('workout_sessions').delete().eq('session_id', sessionId);
  }

  /// Dates in [from]..[to] that have a session, as `yyyy-MM-dd`.
  /// Drives the dots on the calendar strip.
  static Future<Set<String>> getSessionDates(DateTime from, DateTime to) async {
    try {
      final data = await _db
          .from('workout_sessions')
          .select('session_date')
          .eq('user_id', _userId)
          .gte('session_date', _formatDate(from))
          .lte('session_date', _formatDate(to));

      return data.map((r) => r['session_date'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Sessions newest-first, each with its exercise count, for the Log tab.
  static Future<List<SessionSummary>> getSessionHistory({int limit = 50}) async {
    final data = await _db
        .from('workout_sessions')
        .select('session_id, session_date, name, notes, created_at, updated_at, '
            'workout_exercises(exercise_id)')
        .eq('user_id', _userId)
        .order('session_date', ascending: false)
        .limit(limit);

    return data
        .map((j) => SessionSummary(
              session: WorkoutSessions.fromJson(j),
              exerciseCount: (j['workout_exercises'] as List?)?.length ?? 0,
            ))
        .toList();
  }

  // ── Exercises in a session ──────────────────────────────────

  static Future<List<WorkoutExercises>> getWorkoutExercises(
      String sessionId) async {
    final data = await _db
        .from('workout_exercises')
        .select('exercise_id, session_id, catalog_id, order_index, notes, '
            'created_at, catalog_detail:exercise_catalog(catalog_id, name, '
            'category, muscle_group, equipment, is_compound, is_global, '
            'created_by, created_at)')
        .eq('session_id', sessionId)
        .order('order_index', ascending: true);

    return data.map((e) => WorkoutExercises.fromJson(e)).toList();
  }

  /// Appends an exercise to a session and returns its id.
  ///
  /// The order index is derived here rather than passed in — the caller has no
  /// reliable way to know what's already in the session, and hardcoding it (as
  /// the add screen did) left every exercise sitting at position 1.
  static Future<String> createWorkoutExercise(
      WorkoutExercisePayload payload) async {
    final sessionId = payload.sessionId;
    if (sessionId == null) throw Exception('sessionId is required');

    final order = payload.orderIndex ?? await _nextOrderIndex(sessionId);

    final result = await _db
        .from('workout_exercises')
        .insert({
          'session_id': sessionId,
          'catalog_id': payload.catalogId,
          'order_index': order,
          'notes': payload.notes,
        })
        .select('exercise_id')
        .single();

    return result['exercise_id'] as String;
  }

  static Future<int> _nextOrderIndex(String sessionId) async {
    final rows = await _db
        .from('workout_exercises')
        .select('order_index')
        .eq('session_id', sessionId)
        .order('order_index', ascending: false)
        .limit(1);

    if (rows.isEmpty) return 1;
    return ((rows.first['order_index'] as num?)?.toInt() ?? 0) + 1;
  }

  static Future<void> updateExerciseNotes(
      String exerciseId, String? notes) async {
    await _db
        .from('workout_exercises')
        .update({'notes': notes})
        .eq('exercise_id', exerciseId);
  }

  static Future<void> deleteWorkoutExercise(String exerciseId) async {
    await _db.from('exercise_sets').delete().eq('exercise_id', exerciseId);
    await _db.from('workout_exercises').delete().eq('exercise_id', exerciseId);
  }

  // ── Sets ────────────────────────────────────────────────────

  static Future<List<ExerciseSets>> getExerciseSets(String exerciseId) async {
    final sets = await _db
        .from('exercise_sets')
        .select('set_id, exercise_id, set_number, weight_kg, reps, logged_at')
        .eq('exercise_id', exerciseId)
        .order('set_number', ascending: true);

    return sets.map((s) => ExerciseSets.fromJson(s)).toList();
  }

  static Future<void> createExerciseSets(ExerciseSetsPayload payload) async {
    await _db.from('exercise_sets').insert({
      'exercise_id': payload.exerciseId,
      'set_number': payload.setNumber,
      'weight_kg': payload.weightKg,
      'reps': payload.reps,
    });
  }

  /// Logs the next set on an exercise, numbering it for you.
  static Future<void> addSet(
      String exerciseId, double weightKg, int reps) async {
    final existing = await getExerciseSets(exerciseId);
    final nextNumber = existing.isEmpty
        ? 1
        : (existing.map((s) => s.setNumber ?? 0).reduce((a, b) => a > b ? a : b)) + 1;

    await createExerciseSets(ExerciseSetsPayload(
      exerciseId: exerciseId,
      setNumber: nextNumber,
      weightKg: weightKg,
      reps: reps,
    ));
  }

  static Future<void> updateExerciseSet(
      String setId, double weightKg, int reps) async {
    await _db.from('exercise_sets').update({
      'weight_kg': weightKg,
      'reps': reps,
    }).eq('set_id', setId);
  }

  /// The most recent set logged for a catalog exercise, across every session.
  ///
  /// Seeds the weight/reps fields when you open a lift you haven't touched yet
  /// today, so the common case ("same as last time") is zero typing. Null when
  /// you've never logged this exercise.
  static Future<ExerciseSets?> getLastSetForExercise(String catalogId) async {
    try {
      final data = await _db
          .from('exercise_sets')
          .select('set_id, exercise_id, set_number, weight_kg, reps, logged_at, '
              'workout_exercises!inner(catalog_id, '
              'workout_sessions!inner(user_id))')
          .eq('workout_exercises.catalog_id', catalogId)
          .eq('workout_exercises.workout_sessions.user_id', _userId)
          .order('logged_at', ascending: false)
          .limit(1);

      if (data.isEmpty) return null;
      return ExerciseSets.fromJson(data.first);
    } catch (_) {
      return null;
    }
  }

  /// Deletes a set, then closes the gap it left in the numbering — otherwise
  /// deleting set 2 of 3 leaves you with sets numbered 1 and 3.
  static Future<void> deleteExerciseSet(String setId, String exerciseId) async {
    await _db.from('exercise_sets').delete().eq('set_id', setId);

    final remaining = await getExerciseSets(exerciseId);
    for (var i = 0; i < remaining.length; i++) {
      final want = i + 1;
      final s = remaining[i];
      if (s.setNumber == want || s.setId == null) continue;
      await _db
          .from('exercise_sets')
          .update({'set_number': want}).eq('set_id', s.setId!);
    }
  }

  // ── Catalog ─────────────────────────────────────────────────

  /// The whole catalog (~120 rows), for the exercise picker.
  ///
  /// Small enough to fetch once and search on the device — no per-keystroke
  /// round trip.
  static Future<List<CatalogExercises>> getExerciseCatalog() async {
    final data = await _db
        .from('exercise_catalog')
        .select('catalog_id, name, category, muscle_group, equipment, '
            'is_compound, is_global, created_by, created_at')
        .order('name', ascending: true)
        .limit(2000); // PostgREST caps at 1000 by default

    return data.map((e) => CatalogExercises.fromJson(e)).toList();
  }

  /// Exercises this user logged most recently, most recent first, de-duplicated.
  ///
  /// Shown when the exercise field is empty — most sessions repeat the same
  /// lifts, so this turns the common case into zero typing.
  ///
  /// Returns an empty list rather than throwing: recents are a convenience, and
  /// failing to load them must never block the picker.
  static Future<List<CatalogExercises>> getRecentExercises({int limit = 8}) async {
    try {
      final data = await _db
          .from('workout_exercises')
          .select('catalog_id, created_at, '
              'exercise_catalog!inner(catalog_id, name, category, muscle_group, '
              'equipment, is_compound, is_global, created_by, created_at), '
              'workout_sessions!inner(user_id)')
          .eq('workout_sessions.user_id', _userId)
          .order('created_at', ascending: false)
          .limit(60);

      final seen = <String>{};
      final recent = <CatalogExercises>[];
      for (final row in data) {
        final detail = row['exercise_catalog'] as Map<String, dynamic>?;
        final id = detail?['catalog_id'] as String?;
        if (detail == null || id == null || !seen.add(id)) continue;
        recent.add(CatalogExercises.fromJson(detail));
        if (recent.length >= limit) break;
      }
      return recent;
    } catch (_) {
      return const [];
    }
  }

  // ── Progress ────────────────────────────────────────────────

  /// Heaviest set per day for one catalog exercise, oldest first.
  ///
  /// This is what the detail chart plots. It replaces the hardcoded stub the
  /// screen used to show, which displayed the same fake numbers for every lift.
  static Future<List<WeightPoint>> getExerciseHistory(String catalogId) async {
    try {
      final data = await _db
          .from('exercise_sets')
          .select('weight_kg, workout_exercises!inner(catalog_id, '
              'workout_sessions!inner(user_id, session_date))')
          .eq('workout_exercises.catalog_id', catalogId)
          .eq('workout_exercises.workout_sessions.user_id', _userId);

      final topPerDay = <String, double>{};
      for (final row in data) {
        final weight = (row['weight_kg'] as num?)?.toDouble();
        if (weight == null) continue;

        final exercise = row['workout_exercises'] as Map<String, dynamic>?;
        final session = exercise?['workout_sessions'] as Map<String, dynamic>?;
        final date = session?['session_date'] as String?;
        if (date == null) continue;

        if (weight > (topPerDay[date] ?? double.negativeInfinity)) {
          topPerDay[date] = weight;
        }
      }

      final days = topPerDay.keys.toList()..sort();
      return days
          .map((d) => WeightPoint(DateTime.parse(d), topPerDay[d]!))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Everything the Progress tab shows.
  static Future<WorkoutStats> getStats() async {
    final sessions = await _db
        .from('workout_sessions')
        .select('session_date')
        .eq('user_id', _userId);

    final sets = await _db
        .from('exercise_sets')
        .select('weight_kg, reps, workout_exercises!inner('
            'workout_sessions!inner(user_id))')
        .eq('workout_exercises.workout_sessions.user_id', _userId);

    var volume = 0.0;
    double? heaviest;
    for (final s in sets) {
      final weight = (s['weight_kg'] as num?)?.toDouble() ?? 0;
      final reps = (s['reps'] as num?)?.toInt() ?? 0;
      volume += weight * reps;
      if (heaviest == null || weight > heaviest) heaviest = weight;
    }

    final dates = sessions
        .map((s) => DateTime.parse(s['session_date'] as String))
        .map(_dayOnly)
        .toSet();

    final today = _dayOnly(DateTime.now());
    final weekAgo = today.subtract(const Duration(days: 6));
    final thisWeek = dates.where((d) => !d.isBefore(weekAgo)).length;

    return WorkoutStats(
      totalSessions: dates.length,
      totalSets: sets.length,
      totalVolumeKg: volume,
      sessionsThisWeek: thisWeek,
      streakDays: _streak(dates, today),
      heaviestSetKg: heaviest,
    );
  }

  /// Consecutive trained days ending today, or ending yesterday if today isn't
  /// logged yet — a streak shouldn't read as broken just because it's 9am.
  static int _streak(Set<DateTime> days, DateTime today) {
    var cursor = today;
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }

    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
