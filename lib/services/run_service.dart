import 'package:liftr/models/models.dart';
import 'package:liftr/services/workout_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Running sessions and the intervals inside them.
///
/// Sits alongside [WorkoutService] rather than inside it: a run and a gym
/// workout share the session parent but nothing else, and folding distance
/// logic into the class that owns sets and reps is how that shared parent stops
/// being shared. Session creation itself is delegated, not duplicated.
class RunService {
  static final _db = Supabase.instance.client;

  static const String disciplineKey = 'running';

  static const _intervalCols =
      'interval_id, session_id, target_distance_meters, '
      'actual_distance_meters, duration_seconds, logged_manually, '
      'sort_order, created_at';

  // ── Intervals ───────────────────────────────────────────────

  static Future<List<DistanceInterval>> getIntervals(String sessionId) async {
    final data = await _db
        .from('distance_intervals')
        .select(_intervalCols)
        .eq('session_id', sessionId)
        .order('sort_order', ascending: true);

    return data.map((j) => DistanceInterval.fromJson(j)).toList();
  }

  /// Appends an interval to a session and returns its id.
  ///
  /// The sort order is derived here rather than passed in — the caller has just
  /// finished running and has no reliable idea what else is already in the
  /// session, which is exactly the mistake `createWorkoutExercise` was written
  /// to stop making for exercises.
  static Future<String> addInterval(
    String sessionId, {
    double? targetDistanceMeters,
    required double actualDistanceMeters,
    required int durationSeconds,
    bool loggedManually = false,
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

  /// Corrects a logged interval.
  ///
  /// Only the distance and the time: the name and notes belong to the session,
  /// which several intervals share, so editing one leg must not quietly rewrite
  /// the label on all of them.
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

  // ── Sessions ────────────────────────────────────────────────

  /// The running session for [date], creating it if there isn't one.
  ///
  /// Reuses [WorkoutService.getOrCreateSession] rather than inserting directly,
  /// because migration 009 allows exactly one session per (user, date,
  /// discipline). A second run on the same day is another interval on the same
  /// session — inserting a fresh one would simply fail against that index.
  static Future<String> getOrCreateRunSession(
    DateTime date, {
    String name = 'Run',
  }) =>
      WorkoutService.getOrCreateSession(date, name, discipline: disciplineKey);

  /// Logs a run that already happened, in one call.
  ///
  /// The whole manual path: find or make the day's running session, append the
  /// interval, done. No live tracking, no active-session flag — you're
  /// recording history, not starting something.
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

  /// Totals across a session's intervals — what the save screen shows.
  static Future<RunTotals> getTotals(String sessionId) async {
    final intervals = await getIntervals(sessionId);
    return RunTotals.from(intervals);
  }

  /// Throws away a session and its intervals.
  ///
  /// Delegated so there is one delete path for sessions, not two that drift.
  /// The intervals go with it via the cascade in migration 013.
  static Future<void> discardSession(String sessionId) =>
      WorkoutService.deleteWorkoutSession(sessionId);
}
