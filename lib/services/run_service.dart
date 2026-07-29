import 'package:liftr/models/models.dart';
import 'package:liftr/services/workout_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RunService {
  static final _db = Supabase.instance.client;

  static const String disciplineKey = 'running';

  static const _intervalCols =
      'interval_id, session_id, target_distance_meters, '
      'actual_distance_meters, duration_seconds, logged_manually, '
      'sort_order, plan_slot, created_at';

  static Future<List<DistanceInterval>> getIntervals(String sessionId) async {
    final data = await _db
        .from('distance_intervals')
        .select(_intervalCols)
        .eq('session_id', sessionId)
        .order('sort_order', ascending: true);

    return data.map((j) => DistanceInterval.fromJson(j)).toList();
  }

  static Future<String> addInterval(
    String sessionId, {
    double? targetDistanceMeters,
    required double actualDistanceMeters,
    required int durationSeconds,
    bool loggedManually = false,
    int? planSlot,
  }) async {
    final order = await _nextSortOrder(sessionId);

    final result = await _db
        .from('distance_intervals')
        .insert({
          'session_id': sessionId,
          'target_distance_meters': targetDistanceMeters,
          'actual_distance_meters': actualDistanceMeters,
          'duration_seconds': durationSeconds,
          'logged_manually': loggedManually,
          'sort_order': order,
          'plan_slot': planSlot,
        })
        .select('interval_id')
        .single();

    return result['interval_id'] as String;
  }

  static Future<int> _nextSortOrder(String sessionId) async {
    final rows = await _db
        .from('distance_intervals')
        .select('sort_order')
        .eq('session_id', sessionId)
        .order('sort_order', ascending: false)
        .limit(1);

    if (rows.isEmpty) return 1;
    return ((rows.first['sort_order'] as num?)?.toInt() ?? 0) + 1;
  }

  static Future<void> updateInterval(
    String intervalId, {
    required double actualDistanceMeters,
    required int durationSeconds,
  }) async {
    await _db.from('distance_intervals').update({
      'actual_distance_meters': actualDistanceMeters,
      'duration_seconds': durationSeconds,
    }).eq('interval_id', intervalId);
  }

  static Future<void> deleteInterval(String intervalId) async {
    await _db.from('distance_intervals').delete().eq('interval_id', intervalId);
  }

  static Future<String> getOrCreateRunSession(
    DateTime date, {
    String name = 'Run',
  }) =>
      WorkoutService.getOrCreateSession(date, name, discipline: disciplineKey);

  static Future<String> logManualRun({
    required DateTime date,
    required double distanceMeters,
    required int durationSeconds,
    String? name,
    String? notes,
  }) async {
    final sessionId = await getOrCreateRunSession(
      date,
      name: (name == null || name.trim().isEmpty) ? 'Run' : name.trim(),
    );

    await addInterval(
      sessionId,
      actualDistanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      loggedManually: true,
    );

    if (notes != null && notes.trim().isNotEmpty) {
      await _db
          .from('workout_sessions')
          .update({'notes': notes.trim()}).eq('session_id', sessionId);
    }

    return sessionId;
  }

  static Future<RunTotals> getTotals(String sessionId) async {
    final intervals = await getIntervals(sessionId);
    return RunTotals.from(intervals);
  }

  static Future<void> discardSession(String sessionId) =>
      WorkoutService.deleteWorkoutSession(sessionId);
}
