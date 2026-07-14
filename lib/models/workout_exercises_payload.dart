class WorkoutExercisePayload {
  final String? sessionId;
  final String? catalogId;
  final String? notes;
  final int? orderIndex;

  const WorkoutExercisePayload({
    this.sessionId,
    this.catalogId,
    this.notes,
    this.orderIndex,
  });
}