import 'package:liftr/models/models.dart';
import 'package:liftr/utils/dates.dart';
import 'package:liftr/utils/setup_timeline.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  static const _sessionCols = 'session_id, session_date, name, notes, '
      'discipline, routine_id, created_at, updated_at';

  static Future<List<Discipline>> getDisciplines() async {
    try {
      final data = await _db
          .from('disciplines')
          .select('discipline_key, label, emoji, description, sort_order, '
              'logging_type')
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final list = data.map((j) => Discipline.fromJson(j)).toList();
      if (list.isEmpty) return const [_gymFallback];
      return list;
    } catch (_) {
      try {
        final data = await _db
            .from('disciplines')
            .select('discipline_key, label, emoji, description, sort_order')
            .eq('is_active', true)
            .order('sort_order', ascending: true);

        final list = data.map((j) => Discipline.fromJson(j)).toList();
        if (list.isNotEmpty) return list;
      } catch (_) {
      }
      return const [_gymFallback];
    }
  }

  static const _gymFallback =
      Discipline(key: Discipline.gymKey, label: 'Gym', emoji: '🏋️');

  static Future<WorkoutSessions?> getWorkoutSession(
    DateTime date, {
    String discipline = Discipline.gymKey,
  }) async {
    final data = await _db
        .from('workout_sessions')
        .select(_sessionCols)
        .eq('user_id', _userId)
        .eq('session_date', _formatDate(date))
        .eq('discipline', discipline)
        .order('created_at', ascending: true)
        .limit(1);

    if (data.isEmpty) return null;
    return WorkoutSessions.fromJson(data.first);
  }

  static Future<List<WorkoutSessions>> getSessionsForDate(DateTime date) async {
    final data = await _db
        .from('workout_sessions')
        .select(_sessionCols)
        .eq('user_id', _userId)
        .eq('session_date', _formatDate(date))
        .order('created_at', ascending: true);

    return data.map((j) => WorkoutSessions.fromJson(j)).toList();
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
          'discipline': payload.discipline,
        })
        .select('session_id')
        .single();
    return result['session_id'] as String;
  }

  static Future<String> getOrCreateSession(
    DateTime date,
    String name, {
    String discipline = Discipline.gymKey,
  }) async {
    final existing = await getWorkoutSession(date, discipline: discipline);
    final id = existing?.sessionId;
    if (id != null) return id;

    try {
      return await createWorkoutSession(
        WorkoutSessionsPayload(
          sessionDate: date,
          name: name,
          discipline: discipline,
        ),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final raced = await getWorkoutSession(date, discipline: discipline);
        final racedId = raced?.sessionId;
        if (racedId != null) return racedId;
      }
      rethrow;
    }
  }

  static Future<void> updateWorkoutSession(
      String sessionId, WorkoutSessionsPayload payload) async {
    await _db.from('workout_sessions').update({
      'name': payload.name,
      'notes': payload.notes,
    }).eq('session_id', sessionId);
  }

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

  static Future<List<WorkoutExercises>> getWorkoutExercises(
      String sessionId) async {
    final data = await _db
        .from('workout_exercises')
        .select('exercise_id, session_id, catalog_id, order_index, notes, '
            'created_at, setup_id, catalog_detail:exercise_catalog(catalog_id, '
            'name, category, muscle_group, equipment, is_compound, is_global, '
            'created_by, created_at)')
        .eq('session_id', sessionId)
        .order('order_index', ascending: true);

    return data.map((e) => WorkoutExercises.fromJson(e)).toList();
  }

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

  static List<T> reordered<T>(List<T> items, int from, int to) {
    if (from < 0 || from >= items.length) return items;

    final target = (to > from ? to - 1 : to).clamp(0, items.length - 1);
    if (target == from) return items;

    final out = [...items];
    out.insert(target, out.removeAt(from));
    return out;
  }

  static Future<void> setExerciseOrder(List<String> exerciseIds) async {
    for (var i = 0; i < exerciseIds.length; i++) {
      await _db
          .from('workout_exercises')
          .update({'order_index': i + 1}).eq('exercise_id', exerciseIds[i]);
    }
  }

  static Future<void> updateExerciseNotes(
      String exerciseId, String? notes) async {
    await _db
        .from('workout_exercises')
        .update({'notes': notes}).eq('exercise_id', exerciseId);
  }

  static Future<void> deleteWorkoutExercise(String exerciseId) async {
    await _db.from('exercise_sets').delete().eq('exercise_id', exerciseId);
    await _db.from('workout_exercises').delete().eq('exercise_id', exerciseId);
  }

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

  static Future<void> addSet(
      String exerciseId, double weightKg, int reps) async {
    final existing = await getExerciseSets(exerciseId);
    final nextNumber = existing.isEmpty
        ? 1
        : (existing
                .map((s) => s.setNumber ?? 0)
                .reduce((a, b) => a > b ? a : b)) +
            1;

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

  static Future<ExerciseSets?> getLastSetForExercise(
    String catalogId, {
    SetupScope? scope,
  }) async {
    try {
      final data = await _db
          .from('exercise_sets')
          .select(
              'set_id, exercise_id, set_number, weight_kg, reps, logged_at, '
              'workout_exercises!inner(catalog_id, '
              'workout_sessions!inner(user_id, session_date))')
          .eq('workout_exercises.catalog_id', catalogId)
          .eq('workout_exercises.workout_sessions.user_id', _userId);

      final dated = <({DateTime date, ExerciseSets set})>[];
      for (final row in data) {
        final date = _sessionDateOf(row);
        if (date == null) continue;
        if (scope != null && !scope.includes(date)) continue;

        dated.add((date: date, set: ExerciseSets.fromJson(row)));
      }
      if (dated.isEmpty) return null;

      dated.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return (b.set.setNumber ?? 0).compareTo(a.set.setNumber ?? 0);
      });

      return dated.first.set;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _sessionDateOf(Map<String, dynamic> row) {
    final exercise = row['workout_exercises'] as Map<String, dynamic>?;
    final session = exercise?['workout_sessions'] as Map<String, dynamic>?;
    final date = session?['session_date'] as String?;

    return date == null ? null : DateTime.parse(date);
  }

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

  static Future<List<CatalogExercises>> getExerciseCatalog() async {
    final data = await _db
        .from('exercise_catalog')
        .select('catalog_id, name, category, muscle_group, equipment, '
            'is_compound, is_global, created_by, created_at')
        .order('name', ascending: true)
        .limit(2000);

    return data.map((e) => CatalogExercises.fromJson(e)).toList();
  }

  static Future<List<CatalogExercises>> getRecentExercises(
      {int limit = 8}) async {
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

  static Future<List<WeightPoint>> getExerciseHistory(
    String catalogId, {
    SetupScope? scope,
  }) async {
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

        final sessionDate = _sessionDateOf(row);
        if (sessionDate == null) continue;
        if (scope != null && !scope.includes(sessionDate)) continue;

        final date = isoDate(sessionDate);
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
      streakWeeks: weekStreak(dates, today),
      heaviestSetKg: heaviest,
    );
  }

  static int weekStreak(Set<DateTime> days, DateTime today) {
    if (days.isEmpty) return 0;

    final trained = {for (final d in days) weekStart(d)};

    var cursor = weekStart(today);
    if (!trained.contains(cursor)) {
      cursor = _previousWeek(cursor);
      if (!trained.contains(cursor)) return 0;
    }

    var streak = 0;
    while (trained.contains(cursor)) {
      streak++;
      cursor = _previousWeek(cursor);
    }
    return streak;
  }

  static DateTime _previousWeek(DateTime week) =>
      weekStart(week.subtract(const Duration(days: 1)));

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _formatDate(DateTime d) => isoDate(d);
}
