import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'workout_service.dart';

class RoutineService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  static const _lineCols = 'routine_exercise_id, routine_id, catalog_id, '
      'order_index, catalog_detail:exercise_catalog(catalog_id, name, category, '
      'muscle_group, equipment, is_compound, is_global, created_by, created_at)';

  static const _routineCols = 'routine_id, name, discipline, sort_order, '
      'in_cycle, routine_exercises($_lineCols), '
      'routine_intervals(routine_interval_id, routine_id, '
      'target_distance_meters, order_index)';

  static Future<List<Routine>> getRoutines({String? discipline}) async {
    var query = _db.from('routines').select(_routineCols).eq('user_id', _userId);

    if (discipline != null) query = query.eq('discipline', discipline);

    final data = await query
        .order('discipline', ascending: true)
        .order('sort_order', ascending: true);

    return data.map((j) => Routine.fromJson(j)).toList();
  }

  static Routine? nextAfter(List<Routine> cycle, String? lastId) {
    if (cycle.isEmpty) return null;
    if (lastId == null) return cycle.first;

    final at = cycle.indexWhere((r) => r.routineId == lastId);
    if (at < 0) return cycle.first;

    return cycle[(at + 1) % cycle.length];
  }

  static Future<Map<String, Routine>> nextByDiscipline() async {
    final cycles = <String, List<Routine>>{};
    for (final r in await getRoutines()) {
      if (!r.inCycle || r.routineId == null) continue;
      cycles.putIfAbsent(r.discipline, () => []).add(r);
    }

    final out = <String, Routine>{};
    for (final entry in cycles.entries) {
      final lastId = await lastRoutineId(
        entry.key,
        [for (final r in entry.value) r.routineId!],
      );

      final next = nextAfter(entry.value, lastId);
      if (next != null) out[entry.key] = next;
    }
    return out;
  }

  static Future<String?> lastRoutineId(
    String discipline,
    List<String> withinCycle,
  ) async {
    if (withinCycle.isEmpty) return null;

    final data = await _db
        .from('workout_sessions')
        .select('routine_id')
        .eq('user_id', _userId)
        .eq('discipline', discipline)
        .inFilter('routine_id', withinCycle)
        .order('session_date', ascending: false)
        .limit(1);

    if (data.isEmpty) return null;
    return data.first['routine_id'] as String?;
  }

  static Future<String> createRoutine(
    String name, {
    String discipline = Discipline.gymKey,
  }) async {
    final siblings = await _db
        .from('routines')
        .select('sort_order')
        .eq('user_id', _userId)
        .eq('discipline', discipline);

    final order = nextOrderIndex(
      [for (final row in siblings) (row['sort_order'] as num?)?.toInt()],
    );

    final result = await _db
        .from('routines')
        .insert({
          'user_id': _userId,
          'name': name,
          'discipline': discipline,
          'sort_order': order,
        })
        .select('routine_id')
        .single();
    return result['routine_id'] as String;
  }

  static Future<void> setCycleOrder(List<String> routineIds) async {
    for (var i = 0; i < routineIds.length; i++) {
      await _db
          .from('routines')
          .update({'sort_order': i + 1}).eq('routine_id', routineIds[i]);
    }
  }

  static Future<void> setInCycle(String routineId, bool value) async {
    await _db
        .from('routines')
        .update({'in_cycle': value}).eq('routine_id', routineId);
  }

  static Future<void> renameRoutine(String routineId, String name) async {
    await _db.from('routines').update({
      'name': name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('routine_id', routineId);
  }

  static Future<void> deleteRoutine(String routineId) async {
    await _db.from('routines').delete().eq('routine_id', routineId);
  }

  static Future<void> setExercises(
      String routineId, List<String> catalogIds) async {
    await _db.from('routine_exercises').delete().eq('routine_id', routineId);

    if (catalogIds.isNotEmpty) {
      await _db.from('routine_exercises').insert([
        for (var i = 0; i < catalogIds.length; i++)
          {
            'routine_id': routineId,
            'catalog_id': catalogIds[i],
            'order_index': i + 1,
          },
      ]);
    }

    await _touch(routineId);
  }

  static Future<void> setIntervals(
      String routineId, List<double> targetMeters) async {
    await _db.from('routine_intervals').delete().eq('routine_id', routineId);

    if (targetMeters.isNotEmpty) {
      await _db.from('routine_intervals').insert([
        for (var i = 0; i < targetMeters.length; i++)
          {
            'routine_id': routineId,
            'target_distance_meters': targetMeters[i],
            'order_index': i + 1,
          },
      ]);
    }

    await _touch(routineId);
  }

  static Future<void> _touch(String routineId) => _db.from('routines').update({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('routine_id', routineId);

  static Future<void> _tag(String sessionId, String? routineId) async {
    if (routineId == null) return;
    await _db
        .from('workout_sessions')
        .update({'routine_id': routineId}).eq('session_id', sessionId);
  }

  static Future<void> tagSession(DateTime date, Routine routine) async {
    final session = await WorkoutService.getWorkoutSession(
      date,
      discipline: routine.discipline,
    );

    final sessionId = session?.sessionId;
    if (sessionId == null) return;

    await _tag(sessionId, routine.routineId);
  }

  static int nextOrderIndex(Iterable<int?> existing) {
    var max = 0;
    for (final o in existing) {
      if (o != null && o > max) max = o;
    }
    return max + 1;
  }

  static Future<String> fillSession(DateTime date, Routine routine) async {
    final existing = await WorkoutService.getWorkoutSession(
      date,
      discipline: routine.discipline,
    );

    final sessionId = existing?.sessionId ??
        await WorkoutService.getOrCreateSession(
          date,
          routine.name,
          discipline: routine.discipline,
        );

    await _tag(sessionId, routine.routineId);

    if (routine.exercises.isEmpty) return sessionId;

    final already = await WorkoutService.getWorkoutExercises(sessionId);
    var order = nextOrderIndex([for (final e in already) e.orderIndex]);

    await _db.from('workout_exercises').insert([
      for (final line in routine.exercises)
        {
          'session_id': sessionId,
          'catalog_id': line.catalogId,
          'order_index': order++,
        },
    ]);

    return sessionId;
  }
}
