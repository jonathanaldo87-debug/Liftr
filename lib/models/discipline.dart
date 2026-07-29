class Discipline {
  final String key;
  final String label;
  final String emoji;

  final String description;

  final int sortOrder;

  final String loggingType;

  const Discipline({
    required this.key,
    required this.label,
    required this.emoji,
    this.description = '',
    this.sortOrder = 0,
    this.loggingType = loggingNone,
  });

  static const String gymKey = 'gym';

  static const String loggingNone = 'none';
  static const String loggingSets = 'sets';
  static const String loggingDistance = 'distance';

  bool get isGym => key == gymKey;

  bool get logsSets => loggingType == loggingSets;

  bool get logsDistance => loggingType == loggingDistance;

  bool get hasNoLogging => !logsSets && !logsDistance;

  factory Discipline.fromJson(Map<String, dynamic> j) => Discipline(
        key: j['discipline_key'] as String,
        label: j['label'] as String,
        emoji: j['emoji'] as String? ?? '•',
        description: j['description'] as String? ?? '',
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        loggingType: j['logging_type'] as String? ?? loggingNone,
      );

  @override
  bool operator ==(Object other) => other is Discipline && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
