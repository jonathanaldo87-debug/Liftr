class ExerciseSetup {
  final String? setupId;

  final String? label;

  final String? equipment;

  final String? catalogId;

  final double? weightIncrementKg;

  final double? minWeightKg;

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

  bool get isUsable => (weightIncrementKg ?? 0) > 0;

  bool get isShared => catalogId == null;

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
        weightIncrementKg: (j['weight_increment_kg'] as num?)?.toDouble(),
        minWeightKg: (j['min_weight_kg'] as num?)?.toDouble(),
      );

  static Map<String, String> settingsFromJson(Object? raw) => raw is Map
      ? raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
      : const {};
}
