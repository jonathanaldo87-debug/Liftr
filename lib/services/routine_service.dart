import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'workout_service.dart';

/// Routines and the week they run on.
///
/// The one thing to hold onto: nothing here writes a link from a session back to
/// the routine that filled it. [fillSession] copies lines out and the
/// relationship ends. See migration 021 for why — the version that did keep that
/// link is the one migration 019 deleted.
class RoutineService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  /// The catalog columns a routine line needs to render. Same list
  /// [WorkoutService.getWorkoutExercises] joins, so a routine row and a logged
  /// row show the same name, icon and subtitle.
  static const _lineCols = 'routine_exercise_id, routine_id, catalog_id, '
      'order_index, catalog_detail:exercise_catalog(catalog_id, name, category, '
      'muscle_group, equipment, is_compound, is_global, created_by, created_at)';

  /// Both child tables are always joined, even though a routine only ever has
  /// one kind. Branching the *query* on logging type would mean fetching the
  /// discipline first and then deciding — two round trips to save reading an
  /// empty array.
  static const _routineCols = 'routine_id, name, discipline, '
      'routine_exercises($_lineCols), '
      'routine_intervals(routine_interval_id, routine_id, '
      'target_distance_meters, order_index)';

  // ── Reading ─────────────────────────────────────────────────

  /// Every routine you've set up, each with its lines already in order.
  ///
  /// One round trip rather than one per routine: the list screen shows each
  /// routine's exercise count, so it needs the lines anyway.
  static Future<List<Routine>> getRoutines() async {
    final data = await _db
        .from('routines')
        .select(_routineCols)
        .eq('user_id', _userId)
        .order('created_at', ascending: true);

    return data.map((j) => Routine.fromJson(j)).toList();
  }

  /// Whether any routine exists at all.
  ///
  /// Deliberately a broader question than "is [getSchedule] empty": you can have
  /// routines built but no weekday assigned yet, and someone in that position
  /// has already found the feature. The home screen's one-time nudge keys off
  /// this so it stops the moment it's served its purpose.
  ///
  /// One column, one row — it's a existence check, not a fetch.
  static Future<bool> hasAny() async {
    final data = await _db
        .from('routines')
        .select('routine_id')
        .eq('user_id', _userId)
        .limit(1);
    return data.isNotEmpty;
  }

  /// The week, keyed 1..7 for Monday..Sunday. Weekdays you haven't assigned are
  /// simply absent — that's what a rest day is.
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

  /// The routine scheduled for [date], or null on a rest day.
  ///
  /// `DateTime.weekday` is already 1..7 Monday-first, which is exactly how the
  /// column is stored — no conversion, deliberately.
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

  // ── Writing ─────────────────────────────────────────────────

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

  /// Deletes a routine, its lines, and any weekday pointing at it — the two
  /// child tables cascade, so a Monday assigned to it becomes a rest day rather
  /// than a dangling reference.
  ///
  /// Sessions already filled from it are untouched. They hold their own
  /// `workout_exercises` rows and never referred back here.
  static Future<void> deleteRoutine(String routineId) async {
    await _db.from('routines').delete().eq('routine_id', routineId);
  }

  /// Replaces a routine's lines with [catalogIds], in the order given.
  ///
  /// Replace rather than diff: the editor lets you reorder, remove and add in
  /// one sitting, and reconciling that into a minimal set of statements would be
  /// a lot of care spent on rows nothing references. `routine_exercise_id` is a
  /// surrogate that nothing outside this table reads, so churning it costs
  /// nothing.
  ///
  /// [catalogIds] may repeat an id — the same movement twice in one routine is
  /// ordinary, and the table's surrogate key allows it.
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

  /// Replaces a distance routine's planned targets, in metres, in order.
  ///
  /// Replace rather than diff, for the same reason [setExercises] does — and an
  /// empty list is meaningful: a distance routine with no targets is "just go
  /// for a run", which the tracker already handles as a free run.
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

  /// Puts [routineId] on [weekday] (1..7), or clears that day when it's null.
  ///
  /// An upsert on the primary key, so assigning a day that's already taken
  /// replaces what was there. That's the (user_id, weekday) key doing its job:
  /// a weekday can't end up with two routines, so the home screen never has to
  /// choose between them.
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

  // ── Filling a day ───────────────────────────────────────────

  /// A distance routine's targets in metres, in order — what the tracker
  /// pre-fills leg by leg.
  ///
  /// Empty for a sets routine, and empty for a distance routine you left blank,
  /// which the tracker already understands as a free run.
  static List<double> plannedTargets(Routine routine) =>
      [for (final i in routine.intervals) i.targetDistanceMeters];

  /// Where an appended exercise starts counting, given what the session already
  /// holds.
  ///
  /// Past the highest index rather than at `length + 1`: a session you've
  /// deleted an exercise out of has gaps, and counting rows would put the new
  /// one on top of an existing position. Nulls are treated as 0, which is what
  /// `order_index`'s own default is.
  ///
  /// Pure, and public, so the arithmetic is testable without a database.
  static int nextOrderIndex(Iterable<int?> existing) {
    var max = 0;
    for (final o in existing) {
      if (o != null && o > max) max = o;
    }
    return max + 1;
  }

  /// Creates [date]'s session if needed and appends [routine]'s exercises to it.
  /// Returns the session id.
  ///
  /// **Sets disciplines only.** A distance routine has nothing this method could
  /// honestly write: `distance_intervals` rows mean runs that happened, so a
  /// planned one would sit at 0 m in 0:00 and count against the day's totals.
  /// Its targets go to the tracker instead — see [plannedTargets] — and the run
  /// writes the rows itself. Migration 022's header has the long version.
  ///
  /// Appends rather than replaces, and deliberately doesn't check for duplicates
  /// — the caller only offers this on a day with nothing logged, and second-
  /// guessing an explicit tap by silently dropping lines would be worse than
  /// honouring it.
  ///
  /// The session is named after the routine only when the day is new. Filling
  /// into a session that already exists leaves its name alone: you may have
  /// renamed it, and a fill shouldn't overwrite that.
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
