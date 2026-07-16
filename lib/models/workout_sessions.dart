import 'discipline.dart';

class WorkoutSessions {
  final String? sessionId;
  final String? userId;
  final DateTime? sessionDate;
  final String? name;
  final String? notes;

  /// Which discipline this session belongs to — a `disciplines.discipline_key`
  /// ('gym', 'running', …). Defaults to gym: every session logged before
  /// migration 009 was a gym session.
  final String discipline;

  /// The session you're on right now. At most one per user — the database
  /// enforces it with a partial unique index (migration 010).
  ///
  /// Not a timer: nothing records when it started or ended. It only answers
  /// "which session am I currently in", and gates starting another.
  final bool isActive;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WorkoutSessions({
    this.sessionId,
    this.userId,
    this.sessionDate,
    this.name,
    this.notes,
    this.discipline = Discipline.gymKey,
    this.isActive = false,
    this.createdAt,
    this.updatedAt,
  });

  factory WorkoutSessions.fromJson(Map<String, dynamic> j) => WorkoutSessions(
        sessionId: j['session_id'] as String?,
        userId: j['user_id'] as String?,
        sessionDate: j['session_date'] == null
            ? null
            : DateTime.parse(j['session_date'] as String),
        name: j['name'] as String?,
        notes: j['notes'] as String?,
        discipline: j['discipline'] as String? ?? Discipline.gymKey,
        isActive: j['is_active'] as bool? ?? false,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.parse(j['created_at'] as String),
        updatedAt: j['updated_at'] == null
            ? null
            : DateTime.parse(j['updated_at'] as String),
      );
}
