import '../utils/run_math.dart';
import 'catalog_exercises.dart';
import 'discipline.dart';

/// One line of a routine: which exercise, and where it sits in the order.
///
/// Carries no weight or rep target. A routine says what to do; the progression
/// hint says how much, from history that's actually yours — a target stored here
/// would be a second source of truth that goes stale the first week you move up.
class RoutineExercise {
  final String? routineExerciseId;
  final String? routineId;
  final String catalogId;
  final int orderIndex;

  /// The catalog row, when the query joined it in. Null on a lean read.
  final CatalogExercises? catalogDetail;

  const RoutineExercise({
    required this.catalogId,
    this.routineExerciseId,
    this.routineId,
    this.orderIndex = 0,
    this.catalogDetail,
  });

  /// What to call this line. Falls back to the id rather than rendering blank if
  /// a routine is somehow read without its join.
  String get name => catalogDetail?.name ?? catalogId;

  factory RoutineExercise.fromJson(Map<String, dynamic> j) => RoutineExercise(
        routineExerciseId: j['routine_exercise_id'] as String?,
        routineId: j['routine_id'] as String?,
        catalogId: j['catalog_id'] as String,
        orderIndex: (j['order_index'] as num?)?.toInt() ?? 0,
        catalogDetail: j['catalog_detail'] == null
            ? null
            : CatalogExercises.fromJson(
                j['catalog_detail'] as Map<String, dynamic>),
      );

  RoutineExercise copyWith({int? orderIndex}) => RoutineExercise(
        catalogId: catalogId,
        routineExerciseId: routineExerciseId,
        routineId: routineId,
        orderIndex: orderIndex ?? this.orderIndex,
        catalogDetail: catalogDetail,
      );
}

/// One planned leg of a distance routine: how far, and where in the order.
///
/// Carries a target and nothing else. It is not a [DistanceInterval] and must
/// never become one on its own — that type means a run that happened, with an
/// actual distance and a duration behind it. The target is handed to the tracker
/// and the run fills in the rest.
class RoutineInterval {
  final String? routineIntervalId;
  final String? routineId;

  /// Metres, matching `distance_intervals.target_distance_meters` so it reaches
  /// the tracker without a conversion in between.
  final double targetDistanceMeters;

  final int orderIndex;

  const RoutineInterval({
    required this.targetDistanceMeters,
    this.routineIntervalId,
    this.routineId,
    this.orderIndex = 0,
  });

  factory RoutineInterval.fromJson(Map<String, dynamic> j) => RoutineInterval(
        routineIntervalId: j['routine_interval_id'] as String?,
        routineId: j['routine_id'] as String?,
        targetDistanceMeters:
            (j['target_distance_meters'] as num?)?.toDouble() ?? 0,
        orderIndex: (j['order_index'] as num?)?.toInt() ?? 0,
      );
}

/// A leg of the day's plan that still needs running: which slot it is, and how
/// far.
///
/// The slot is 1-based and is what a finished run records as its
/// `plan_slot`, so leg 3 stays leg 3 whether you ran it first or last.
class PlannedLeg {
  /// 1-based position in the routine's list.
  final int slot;
  final double targetMeters;

  const PlannedLeg({required this.slot, required this.targetMeters});
}

/// A named exercise list you set up once and fill days from.
///
/// Deliberately not linked to the sessions it produced. Filling a day copies
/// these lines into ordinary `workout_exercises` rows and the relationship ends
/// there — which is what stops editing a routine from rewriting what last
/// month's workouts claim to have contained. Migration 021's header has the
/// long version, and migration 019 has the feature this replaces.
class Routine {
  final String? routineId;
  final String name;
  final String discipline;

  /// Exercises, for a routine whose discipline logs sets. In
  /// [RoutineExercise.orderIndex] order; empty for a distance routine.
  final List<RoutineExercise> exercises;

  /// Planned targets, for a routine whose discipline logs distance. In order;
  /// empty for a sets routine.
  ///
  /// A routine holds one kind or the other, chosen by its discipline's
  /// `logging_type` — the same branch a day's session already takes between
  /// `workout_exercises` and `distance_intervals`.
  final List<RoutineInterval> intervals;

  const Routine({
    required this.name,
    this.routineId,
    this.discipline = Discipline.gymKey,
    this.exercises = const [],
    this.intervals = const [],
  });

  /// How many things are planned, whichever kind they are.
  ///
  /// Deliberately one number: every caller that shows a count ("6 exercises",
  /// "4 intervals") wants "is this routine empty" and "how big is it", and
  /// neither question cares which table the rows came from.
  int get itemCount => exercises.length + intervals.length;

  bool get isEmpty => itemCount == 0;

  /// Everything the planned legs add up to, in metres. 0 for a sets routine.
  double get totalTargetMeters =>
      intervals.fold(0, (sum, i) => sum + i.targetDistanceMeters);

  /// Every leg of the plan, whether run or not, as slot + target.
  ///
  /// 1-based, because that's what a run records in `plan_slot` and what the
  /// card labels rows with.
  List<PlannedLeg> get legs => [
        for (var i = 0; i < intervals.length; i++)
          PlannedLeg(
            slot: i + 1,
            targetMeters: intervals[i].targetDistanceMeters,
          ),
      ];

  /// The legs still to run at or after [fromSlot], skipping any already in
  /// [doneSlots].
  ///
  /// What the tracker is handed when you tap Start on a leg: that leg first,
  /// then whatever else remains ahead of it, so its own "add another interval"
  /// flow keeps moving through the plan without you returning to the card.
  ///
  /// Forward only — tapping leg 3 does not queue up legs 1 and 2 behind it.
  /// Going back for a leg you skipped is a deliberate act, so it stays a
  /// deliberate tap.
  List<PlannedLeg> legsFrom(int fromSlot, {Set<int> doneSlots = const {}}) => [
        for (final leg in legs)
          if (leg.slot >= fromSlot && !doneSlots.contains(leg.slot)) leg,
      ];

  /// A one-line summary of what's in it, worded for whichever kind it holds.
  ///
  /// A single target reads better as the distance than as a count — "5 km" says
  /// more than "1 interval". Several go back to counting, with the total, since
  /// listing them would outgrow the line.
  String get summary {
    if (intervals.isNotEmpty) {
      if (intervals.length == 1) {
        return formatDistance(intervals.first.targetDistanceMeters);
      }
      return '${intervals.length} intervals · '
          '${formatDistance(totalTargetMeters)}';
    }
    if (exercises.isNotEmpty) {
      return '${exercises.length} exercise${exercises.length == 1 ? '' : 's'}';
    }
    return 'Nothing in it yet';
  }

  factory Routine.fromJson(Map<String, dynamic> j) {
    final rawExercises = (j['routine_exercises'] as List?) ?? const [];
    final lines = rawExercises
        .whereType<Map<String, dynamic>>()
        .map(RoutineExercise.fromJson)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final rawIntervals = (j['routine_intervals'] as List?) ?? const [];
    final targets = rawIntervals
        .whereType<Map<String, dynamic>>()
        .map(RoutineInterval.fromJson)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return Routine(
      routineId: j['routine_id'] as String?,
      name: j['name'] as String? ?? '',
      discipline: j['discipline'] as String? ?? Discipline.gymKey,
      exercises: lines,
      intervals: targets,
    );
  }
}

/// The week: which routine each weekday runs, keyed 1..7 for Monday..Sunday.
///
/// The numbering matches `DateTime.weekday` and `kWeekdaysFull` exactly, so
/// nothing has to convert between them — a day is looked up with
/// `schedule[date.weekday]` and that's the whole of it.
///
/// A weekday absent from the map is a rest day. That's the only thing "rest"
/// ever means here, which is why it needs no representation of its own.
typedef WeeklySchedule = Map<int, Routine>;
