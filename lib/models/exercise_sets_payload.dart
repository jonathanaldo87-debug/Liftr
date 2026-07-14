class ExerciseSetsPayload {
  final String? exerciseId;
  final int? setNumber;
  final double? weightKg;
  final int? reps;

  const ExerciseSetsPayload({
    this.exerciseId,
    this.setNumber,
    this.weightKg,
    this.reps,
  });

  factory ExerciseSetsPayload.fromJson(Map<String, dynamic> j) => ExerciseSetsPayload(
        exerciseId: j['exercise_id'] as String?,
        setNumber: j['set_number'] as int?,
        weightKg: j['weight_kg'] as double?,
        reps: j['reps'] as int?,
      );
}
