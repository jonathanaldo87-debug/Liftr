/// A kind of training the app can log: gym, running, and whatever comes next.
///
/// This mirrors the `disciplines` table (migration 009) rather than being an
/// enum on purpose. Adding swimming later should be an INSERT, not a code
/// change — so nothing in the app may switch on a hardcoded list of keys.
///
/// The one exception is [gymKey]: the gym flow is the only discipline with a
/// bespoke logging UI today, so a couple of places legitimately ask "is this the
/// gym one?".
class Discipline {
  /// Stable slug and primary key — 'gym', 'running'. Also what
  /// `workout_sessions.discipline` stores.
  final String key;
  final String label;
  final String emoji;

  /// One-line blurb for the onboarding card, e.g. "Weights & machines".
  final String description;

  final int sortOrder;

  /// Which logging UI this discipline opens: 'sets', 'distance', or 'none'.
  ///
  /// This is how a new discipline stays an INSERT rather than a release. Adding
  /// cycling means seeding a row with `logging_type = 'distance'`, and it gets
  /// the run logger without a line of Dart changing. Switching on [key] instead
  /// would quietly take that promise back, one `if` at a time.
  final String loggingType;

  const Discipline({
    required this.key,
    required this.label,
    required this.emoji,
    this.description = '',
    this.sortOrder = 0,
    this.loggingType = loggingNone,
  });

  /// The only key the app is allowed to special-case: gym has a workout/exercise
  /// UI that nothing else shares, and onboarding only offers templates for it.
  static const String gymKey = 'gym';

  static const String loggingNone = 'none';
  static const String loggingSets = 'sets';
  static const String loggingDistance = 'distance';

  bool get isGym => key == gymKey;

  /// Logs sets and reps — the gym flow.
  bool get logsSets => loggingType == loggingSets;

  /// Logs distance over time — the run flow.
  bool get logsDistance => loggingType == loggingDistance;

  /// Seeded, but with no way to log into it yet.
  bool get hasNoLogging => !logsSets && !logsDistance;

  factory Discipline.fromJson(Map<String, dynamic> j) => Discipline(
        key: j['discipline_key'] as String,
        label: j['label'] as String,
        emoji: j['emoji'] as String? ?? '•',
        description: j['description'] as String? ?? '',
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        // Defaults to 'none' rather than guessing: a row written before
        // migration 013 has no opinion, and inventing one would open a logging
        // UI that can't save anywhere.
        loggingType: j['logging_type'] as String? ?? loggingNone,
      );

  @override
  bool operator ==(Object other) => other is Discipline && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
