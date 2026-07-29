class DistanceInterval {
  final String? intervalId;
  final String? sessionId;

  final double? targetDistanceMeters;

  final double actualDistanceMeters;
  final int durationSeconds;

  final bool loggedManually;

  final int sortOrder;

  final int? planSlot;

  final DateTime? createdAt;

  const DistanceInterval({
    this.intervalId,
    this.sessionId,
    this.targetDistanceMeters,
    this.actualDistanceMeters = 0,
    this.durationSeconds = 0,
    this.loggedManually = false,
    this.sortOrder = 1,
    this.planSlot,
    this.createdAt,
  });

  bool get isFreeRun => targetDistanceMeters == null;

  bool get reachedTarget {
    final target = targetDistanceMeters;
    if (target == null) return true;
    return actualDistanceMeters >= target;
  }

  factory DistanceInterval.fromJson(Map<String, dynamic> j) => DistanceInterval(
        intervalId: j['interval_id'] as String?,
        sessionId: j['session_id'] as String?,
        targetDistanceMeters: (j['target_distance_meters'] as num?)?.toDouble(),
        actualDistanceMeters:
            (j['actual_distance_meters'] as num?)?.toDouble() ?? 0,
        durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 0,
        loggedManually: j['logged_manually'] as bool? ?? false,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 1,
        planSlot: (j['plan_slot'] as num?)?.toInt(),
        createdAt: j['created_at'] == null
            ? null
            : DateTime.parse(j['created_at'] as String),
      );
}

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
