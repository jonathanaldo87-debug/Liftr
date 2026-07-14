import 'package:liftr/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkoutService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  static Future<WorkoutSessions?> getWorkoutSession(DateTime date) async {
    final data = await _db
        .from('workout_sessions')
        .select('session_id, session_date, name, notes, created_at, updated_at')
        .eq('user_id', _userId)
        .eq('session_date', _formatDate(date))
        .maybeSingle();

    if (data == null) return null;
    return WorkoutSessions.fromJson(data);
  }

  static Future<String> createWorkoutSession(WorkoutSessionsPayload payload) async {
    final result = await _db.from('workout_sessions').insert({
      'user_id': _userId,
      'name': payload.name,
      'session_date': _formatDate(payload.sessionDate),
      'notes': payload.notes,
    }).select('session_id').single();
    return result['session_id'] as String;
  }

  static Future<void> updateWorkoutSession(String sessionId, WorkoutSessionsPayload payload) async {
    await _db.from('workout_sessions')
    .update({
      'name': payload.name,
      'notes': payload.notes
    })
    .eq('session_id', sessionId);
  }

  static Future<List<WorkoutExercises>> getWorkoutExercises(String sessionId) async {
    final data = await _db
        .from('workout_exercises')
        .select('exercise_id, session_id, catalog_id, order_index, notes, created_at, catalog_detail:exercise_catalog(catalog_id, name, category, muscle_group, is_global, created_by, created_at)')
        .eq('session_id', sessionId)
        .order('order_index', ascending: true);

    return data.map((e) => WorkoutExercises.fromJson(e)).toList();
  }

  static Future<void> createWorkoutExercise(WorkoutExercisePayload payload) async {
    await _db.from('workout_exercises').insert({
      'session_id': payload.sessionId,
      'catalog_id': payload.catalogId,
      'order_index': payload.orderIndex,
      'notes': payload.notes,
    });
  }

  static Future<void> updateWorkoutExercise(String exerciseId, WorkoutExercisePayload payload) async {
    await _db.from('workout_exercises')
    .update({
      'catalog_id': payload.catalogId,
      'notes': payload.notes
    })
    .eq('exercise_id', exerciseId);
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

  static Future<List<CatalogExercises>> getExerciseCatalog() async {
    final data = await _db
        .from('exercise_catalog')
        .select('catalog_id, name, category, muscle_group, is_global, created_by, created_at')
        .order('name', ascending: true);

    return data.map((e) => CatalogExercises.fromJson(e)).toList();
  }

  static String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
