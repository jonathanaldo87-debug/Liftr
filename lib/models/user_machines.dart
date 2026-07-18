/// A physical station you train on — one cable stack, one leg press.
///
/// Deliberately not scoped to an exercise: a cable stack serves curls,
/// pushdowns, face pulls and rows alike, so scoping it per exercise would mean
/// registering the same station once per movement. How you *set it up* for a
/// given exercise is a separate thing — see [MachineExerciseSettings].
class UserMachine {
  final String? machineId;

  /// Whatever you call it while standing between two of them.
  final String? label;

  /// The stack's step, once confirmed.
  ///
  /// Null means "not known yet", not "no increment". The app infers a step from
  /// your logged weights and only writes here when you accept or correct it —
  /// so an unconfirmed guess never hardens into a stored fact.
  final double? weightIncrementKg;

  /// The lightest the stack goes. Stacks rarely start at zero, and suggesting a
  /// weight below the bottom pin is worse than suggesting nothing.
  final double? minWeightKg;

  final String? notes;
  final DateTime? createdAt;

  const UserMachine({
    this.machineId,
    this.label,
    this.weightIncrementKg,
    this.minWeightKg,
    this.notes,
    this.createdAt,
  });

  /// What the picker chip shows. Falls back rather than rendering an empty chip.
  String get displayLabel {
    final l = label?.trim();
    return (l == null || l.isEmpty) ? 'Unnamed machine' : l;
  }

  factory UserMachine.fromJson(Map<String, dynamic> j) => UserMachine(
        machineId: j['machine_id'] as String?,
        label: j['label'] as String?,
        // `as double?` would throw: Postgres sends a whole number like 5 as a
        // JSON int, not 5.0. Same reason as ExerciseSets.weightKg.
        weightIncrementKg: (j['weight_increment_kg'] as num?)?.toDouble(),
        minWeightKg: (j['min_weight_kg'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.parse(j['created_at'] as String),
      );
}

/// How one machine is set up for one exercise — seat 4, back pad 2.
///
/// Keyed by the (machine, exercise) pair because a cable row and a cable curl
/// need different seat heights on the same stack.
class MachineExerciseSettings {
  final String? machineId;
  final String? catalogId;

  /// Free key/value: `{"seat": "4", "back pad": "2"}`.
  ///
  /// Not columns, because the vocabulary differs for every machine — seat, pin,
  /// lever arm, foot plate — and columns would mean a migration per machine
  /// type. Rendered as chips without the UI needing to know what the keys mean.
  final Map<String, String> settings;

  final String? notes;

  const MachineExerciseSettings({
    this.machineId,
    this.catalogId,
    this.settings = const {},
    this.notes,
  });

  bool get isEmpty => settings.isEmpty && (notes == null || notes!.isEmpty);

  /// "seat 4 · back pad 2" — the one-line form for the chip under the title.
  String get summary =>
      settings.entries.map((e) => '${e.key} ${e.value}').join(' · ');

  factory MachineExerciseSettings.fromJson(Map<String, dynamic> j) {
    final raw = j['settings'];
    return MachineExerciseSettings(
      machineId: j['machine_id'] as String?,
      catalogId: j['catalog_id'] as String?,
      // jsonb comes back as a Map with dynamic values; everything is rendered as
      // text, so normalise here rather than at every read site.
      settings: raw is Map
          ? raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : const {},
      notes: j['notes'] as String?,
    );
  }
}
