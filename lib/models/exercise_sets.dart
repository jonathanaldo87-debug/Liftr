class ExerciseSets {
  final String? setId;
  final String? exerciseId;
  final int? setNumber;
  final double? weightKg;
  final int? reps;
  final DateTime? loggedAt;

  const ExerciseSets({
    this.setId,
    this.exerciseId,
    this.setNumber,
    this.weightKg,
    this.reps,
    this.loggedAt,
  });

  double get volume => (weightKg ?? 0) * (reps ?? 0);

  factory ExerciseSets.fromJson(Map<String, dynamic> j) => ExerciseSets(
        setId: j['set_id'] as String?,
        exerciseId: j['exercise_id'] as String?,
        setNumber: (j['set_number'] as num?)?.toInt(),
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        reps: (j['reps'] as num?)?.toInt(),
        loggedAt: j['logged_at'] == null
            ? null
            : DateTime.parse(j['logged_at'] as String),
      );
}
