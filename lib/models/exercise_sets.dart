class ExerciseSets {
  final String? setId;
  final String? exerciseId;
  final int? setNumber;
  final double? weightKg;
  final int? reps;
  final bool? isCompleted;
  final DateTime? loggedAt;

  const ExerciseSets({
    this.setId,
    this.exerciseId,
    this.setNumber,
    this.weightKg,
    this.reps,
    this.isCompleted,
    this.loggedAt,
  });

  factory ExerciseSets.fromJson(Map<String, dynamic> j) => ExerciseSets(
        setId: j['set_id'] as String?,
        exerciseId: j['exercise_id'] as String?,
        setNumber: j['set_number'] as int?,
        weightKg: j['weight_kg'] as double?,
        reps: j['reps'] as int?,
        isCompleted: j['is_completed'] as bool?,
        loggedAt: j['logged_at'] == null ? null : DateTime.parse(j['logged_at'] as String),
      );
}
