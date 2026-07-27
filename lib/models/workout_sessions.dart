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

  // There is no `is_active` here, and none in the database either as of
  // migration 020.
  //
  // It recorded no time and routed no data — nothing keyed off it but a banner,
  // and half the UI (the run card) always ignored it in favour of the date. The
  // date is the mode now: today is live, the past is history until unlocked.

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WorkoutSessions({
    this.sessionId,
    this.userId,
    this.sessionDate,
    this.name,
    this.notes,
    this.discipline = Discipline.gymKey,
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
        createdAt: j['created_at'] == null
            ? null
            : DateTime.parse(j['created_at'] as String),
        updatedAt: j['updated_at'] == null
            ? null
            : DateTime.parse(j['updated_at'] as String),
      );
}
