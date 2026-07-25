/// A station you train on, and how it's set for one exercise.
///
/// The split matters and it's physical: the **step** belongs to the station —
/// a cable stack moves in 5s whatever you do on it — while the **seat height**
/// belongs to the station *and* the exercise together, because a cable row and
/// a cable curl are different heights on the same stack.
///
/// So one of these is loaded per exercise you're looking at, carrying the
/// station's own facts plus that exercise's settings for it. Two rows behind
/// it (`user_setup` and `user_setup_exercise`, migration 018), one object in
/// front, because every screen wants both halves at once.
class ExerciseSetup {
  final String? setupId;

  /// What you call it while standing between the two of them: "5 kg cable".
  ///
  /// Optional, and usually absent — with one station of a given kind there is
  /// nothing to tell apart, and making you name it would be a field to fill for
  /// no answer.
  final String? label;

  /// Which family this station serves: cable, dumbbell, barbell, machine. Not a
  /// label — it's what decides the exercises this setup is offered on.
  final String? equipment;

  /// Set only for machines, where it pins the station to one exercise.
  ///
  /// Null means "every exercise using this equipment", which is the normal case:
  /// you have one dumbbell rack and one plate set, so entering their step once
  /// is the whole point. A gym has a dozen distinct machines though, and leaving
  /// those unpinned would put a dozen chips on every machine exercise.
  final String? catalogId;

  /// The step this station's weight moves in. Required — see [isUsable].
  ///
  /// It's the number the app reads rather than you: the difference between
  /// telling you to go up and telling you to try 62.5 kg.
  final double? weightIncrementKg;

  /// The lightest the stack goes. Nothing sets this yet; it's the floor a
  /// "drop the weight" suggestion would need so it can't point below the bottom
  /// pin.
  final double? minWeightKg;

  /// How this station is set for the exercise it was loaded against — seat 4,
  /// back pad 2. Empty for a station you've never recorded settings on here,
  /// which is every barbell and dumbbell.
  final Map<String, String> settings;

  const ExerciseSetup({
    this.setupId,
    this.label,
    this.equipment,
    this.catalogId,
    this.weightIncrementKg,
    this.minWeightKg,
    this.settings = const {},
  });

  /// Whether this setup can do the job it exists for.
  ///
  /// A station with no step can't produce a loadable suggestion, so the editor
  /// won't save one. This is the same invariant, readable from the outside.
  bool get isUsable => (weightIncrementKg ?? 0) > 0;

  /// Serves every exercise of its equipment, rather than just one.
  bool get isShared => catalogId == null;

  /// "seat 4 · back pad 2" — this exercise's settings, without the station name.
  String get settingsSummary =>
      settings.entries.map((e) => '${e.key} ${e.value}').join(' · ');

  ExerciseSetup withSettings(Map<String, String> s) => ExerciseSetup(
        setupId: setupId,
        label: label,
        equipment: equipment,
        catalogId: catalogId,
        weightIncrementKg: weightIncrementKg,
        minWeightKg: minWeightKg,
        settings: s,
      );

  factory ExerciseSetup.fromJson(Map<String, dynamic> j) => ExerciseSetup(
        setupId: j['setup_id'] as String?,
        label: j['label'] as String?,
        equipment: j['equipment'] as String?,
        catalogId: j['catalog_id'] as String?,
        // `as double?` would throw: Postgres sends a whole number like 5 as a
        // JSON int, not 5.0. Same reason as ExerciseSets.weightKg.
        weightIncrementKg: (j['weight_increment_kg'] as num?)?.toDouble(),
        minWeightKg: (j['min_weight_kg'] as num?)?.toDouble(),
      );

  /// jsonb comes back as a Map with dynamic values; everything is rendered as
  /// text, so normalise here rather than at every read site.
  static Map<String, String> settingsFromJson(Object? raw) => raw is Map
      ? raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
      : const {};
}
