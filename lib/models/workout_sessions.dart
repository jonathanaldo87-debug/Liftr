class WorkoutSessions {
  final String? sessionId;
  final String? userId;
  final DateTime? sessionDate;
  final String? name;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WorkoutSessions({
    this.sessionId,
    this.userId,
    this.sessionDate,
    this.name,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory WorkoutSessions.fromJson(Map<String, dynamic> j) => WorkoutSessions(
        sessionId: j['session_id'] as String?,
        userId: j['user_id'] as String?,
        sessionDate: j['session_date'] == null ? null : DateTime.parse(j['session_date'] as String),
        name: j['name'] as String?,
        notes: j['notes'] as String?,
        createdAt: j['created_at'] == null ? null : DateTime.parse(j['created_at'] as String),
        updatedAt: j['updated_at'] == null ? null : DateTime.parse(j['updated_at'] as String),
      );
}
