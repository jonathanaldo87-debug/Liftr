class WeightPoint {
  final DateTime date;
  final double topWeight;

  const WeightPoint(this.date, this.topWeight);
}

class WorkoutStats {
  final int totalSessions;
  final int totalSets;

  final double totalVolumeKg;

  final int sessionsThisWeek;

  final int streakDays;

  final double? heaviestSetKg;

  const WorkoutStats({
    this.totalSessions = 0,
    this.totalSets = 0,
    this.totalVolumeKg = 0,
    this.sessionsThisWeek = 0,
    this.streakDays = 0,
    this.heaviestSetKg,
  });
}
