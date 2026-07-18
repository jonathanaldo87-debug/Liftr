/// One leg of a run — a tracked interval, or one typed in after the fact.
///
/// A running session holds one or more of these. "Go again" after finishing a
/// kilometre appends an interval rather than starting a second session, which
/// is also what keeps a second run on the same day from colliding with the
/// unique index on (user, date, discipline) from migration 009.
class DistanceInterval {
  final String? intervalId;
  final String? sessionId;

  /// What you set out to run.
  ///
  /// Null means a free run — you went until you stopped, and there was no
  /// target to fall short of. Deliberately distinct from 0.
  final double? targetDistanceMeters;

  final double actualDistanceMeters;
  final int durationSeconds;

  /// Typed in rather than tracked. A manual entry is a human estimate and a
  /// tracked one carries GPS error; anything comparing them needs to know
  /// which it's looking at.
  final bool loggedManually;

  final int sortOrder;
  final DateTime? createdAt;

  const DistanceInterval({
    this.intervalId,
    this.sessionId,
    this.targetDistanceMeters,
    this.actualDistanceMeters = 0,
    this.durationSeconds = 0,
    this.loggedManually = false,
    this.sortOrder = 1,
    this.createdAt,
  });

  /// A free run has no target, so it can't be short of one.
  bool get isFreeRun => targetDistanceMeters == null;

  /// Whether the target was met. Free runs count as complete — you ran until
  /// you meant to stop, which is the whole point of not setting a target.
  bool get reachedTarget {
    final target = targetDistanceMeters;
    if (target == null) return true;
    return actualDistanceMeters >= target;
  }

  factory DistanceInterval.fromJson(Map<String, dynamic> j) => DistanceInterval(
        intervalId: j['interval_id'] as String?,
        sessionId: j['session_id'] as String?,
        // `as double?` would throw: Postgres sends a whole number like 5000 as
        // a JSON int, not 5000.0. Same reason as ExerciseSets.weightKg.
        targetDistanceMeters: (j['target_distance_meters'] as num?)?.toDouble(),
        actualDistanceMeters:
            (j['actual_distance_meters'] as num?)?.toDouble() ?? 0,
        durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 0,
        loggedManually: j['logged_manually'] as bool? ?? false,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 1,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.parse(j['created_at'] as String),
      );
}

/// Everything the save screen shows about a running session.
class RunTotals {
  final double distanceMeters;
  final int durationSeconds;
  final int intervalCount;

  const RunTotals({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.intervalCount,
  });

  static RunTotals from(Iterable<DistanceInterval> intervals) {
    var distance = 0.0;
    var seconds = 0;
    var count = 0;
    for (final i in intervals) {
      distance += i.actualDistanceMeters;
      seconds += i.durationSeconds;
      count++;
    }
    return RunTotals(
      distanceMeters: distance,
      durationSeconds: seconds,
      intervalCount: count,
    );
  }
}
