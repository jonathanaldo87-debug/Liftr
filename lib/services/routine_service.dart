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

  static const _routineCols = 'routine_id, name, discipline, '
      'routine_exercises($_lineCols), '
      'routine_intervals(routine_interval_id, routine_id, '
      'target_distance_meters, order_index)';

  static Future<List<Routine>> getRoutines() async {
    final data = await _db
        .from('routines')
        .select(_routineCols)
        .eq('user_id', _userId)
        .order('created_at', ascending: true);

    return data.map((j) => Routine.fromJson(j)).toList();
  }

  static Future<bool> hasAny() async {
    final data = await _db
        .from('routines')
        .select('routine_id')
        .eq('user_id', _userId)
        .limit(1);
    return data.isNotEmpty;
  }

  static Future<WeeklySchedule> getSchedule() async {
    final data = await _db
        .from('routine_days')
        .select('weekday, routines($_routineCols)')
        .eq('user_id', _userId);

    final out = <int, Routine>{};
    for (final row in data) {
      final weekday = (row['weekday'] as num?)?.toInt();
      final routine = row['routines'];
      if (weekday == null || routine is! Map<String, dynamic>) continue;
      out[weekday] = Routine.fromJson(routine);
    }
    return out;
  }

  static Future<Routine?> routineFor(DateTime date) async {
    final data = await _db
        .from('routine_days')
        .select('routines($_routineCols)')
        .eq('user_id', _userId)
        .eq('weekday', date.weekday)
        .limit(1);

    if (data.isEmpty) return null;
    final routine = data.first['routines'];
    if (routine is! Map<String, dynamic>) return null;
    return Routine.fromJson(routine);
  }

  static Future<String> createRoutine(
    String name, {
    String discipline = Discipline.gymKey,
  }) async {
    final result = await _db
        .from('routines')
        .insert({
          'user_id': _userId,
          'name': name,
          'discipline': discipline,
        })
        .select('routine_id')
        .single();
    return result['routine_id'] as String;
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

  static Future<void> assignDay(int weekday, String? routineId) async {
    if (routineId == null) {
      await _db
          .from('routine_days')
          .delete()
          .eq('user_id', _userId)
          .eq('weekday', weekday);
      return;
    }

    await _db.from('routine_days').upsert({
      'user_id': _userId,
      'weekday': weekday,
      'routine_id': routineId,
    }, onConflict: 'user_id,weekday');
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
