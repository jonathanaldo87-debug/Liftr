class WorkoutSessionsPayload {
  final DateTime sessionDate;
  final String name;
  final String? notes;
  final DateTime? updatedAt;

  const WorkoutSessionsPayload({
    required this.sessionDate,
    required this.name,
    this.notes,
    this.updatedAt,
  });
}
