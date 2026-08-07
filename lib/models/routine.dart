import '../utils/run_math.dart';
import 'catalog_exercises.dart';
import 'discipline.dart';

class RoutineExercise {
  final String? routineExerciseId;
  final String? routineId;
  final String catalogId;
  final int orderIndex;

  final CatalogExercises? catalogDetail;

  const RoutineExercise({
    required this.catalogId,
    this.routineExerciseId,
    this.routineId,
    this.orderIndex = 0,
    this.catalogDetail,
  });

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

class RoutineInterval {
  final String? routineIntervalId;
  final String? routineId;

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

class PlannedLeg {
  final int slot;
  final double targetMeters;

  const PlannedLeg({required this.slot, required this.targetMeters});
}

class Routine {
  final String? routineId;
  final String name;
  final String discipline;

  final int sortOrder;

  final bool inCycle;

  final List<RoutineExercise> exercises;

  final List<RoutineInterval> intervals;

  const Routine({
    required this.name,
    this.routineId,
    this.discipline = Discipline.gymKey,
    this.sortOrder = 0,
    this.inCycle = true,
    this.exercises = const [],
    this.intervals = const [],
  });

  int get itemCount => exercises.length + intervals.length;

  bool get isEmpty => itemCount == 0;

  double get totalTargetMeters =>
      intervals.fold(0, (sum, i) => sum + i.targetDistanceMeters);

  List<PlannedLeg> get legs => [
        for (var i = 0; i < intervals.length; i++)
          PlannedLeg(
            slot: i + 1,
            targetMeters: intervals[i].targetDistanceMeters,
          ),
      ];

  List<PlannedLeg> legsFrom(int fromSlot, {Set<int> doneSlots = const {}}) => [
        for (final leg in legs)
          if (leg.slot >= fromSlot && !doneSlots.contains(leg.slot)) leg,
      ];

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
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      inCycle: j['in_cycle'] as bool? ?? true,
      exercises: lines,
      intervals: targets,
    );
  }
}
