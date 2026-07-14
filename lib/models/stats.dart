import 'workout_sessions.dart';

/// One point on the exercise progress chart: the heaviest set you hit on a
/// given day. Top-set-per-day is the standard way to read strength progress —
/// plotting every set just turns the line into noise.
class WeightPoint {
  final DateTime date;
  final double topWeight;

  const WeightPoint(this.date, this.topWeight);
}

/// A session plus how many exercises it holds, for the Log tab.
class SessionSummary {
  final WorkoutSessions session;
  final int exerciseCount;

  const SessionSummary({required this.session, required this.exerciseCount});
}

/// Everything the Progress tab shows, in one round trip.
class WorkoutStats {
  final int totalSessions;
  final int totalSets;

  /// Sum of weight × reps across every set, in kg.
  final double totalVolumeKg;

  /// Sessions logged in the last 7 days.
  final int sessionsThisWeek;

  /// Consecutive days ending today (or yesterday) that have a session.
  /// Counting from yesterday keeps the streak alive until you've trained today.
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
