import 'package:liftr/models/models.dart';
import 'package:liftr/utils/increment_inference.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The stations you train on, and how each is set for a given exercise.
///
/// Everything here is optional by design. An account that never opens the setup
/// sheet behaves exactly as the app did before it existed.
///
/// Two tables behind this (migration 018): `user_setup` holds the station and
/// its step, shared across every exercise using that equipment; and
/// `user_setup_exercise` holds the seat height, which is only true of one
/// station and one exercise together.
///
/// The arithmetic lives in `utils/increment_inference.dart`, which is pure and
/// tested. This class is the IO around it.
class ExerciseSetupService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  static const _cols =
      'setup_id, label, equipment, catalog_id, weight_increment_kg, '
      'min_weight_kg';

  /// The stations worth offering for one exercise, each carrying that
  /// exercise's own settings.
  ///
  /// Offered when the equipment matches and the station isn't pinned to a
  /// different exercise. So both cable stacks appear on every cable movement —
  /// entered once, not once per lift — while the preacher curl machine appears
  /// only on preacher curls.
  ///
  /// Returns an empty list rather than throwing: setup is an enhancement, and
  /// failing to load it must never block logging a set.
  static Future<List<ExerciseSetup>> getSetups({
    required String catalogId,
    required String? equipment,
  }) async {
    if (equipment == null || equipment.trim().isEmpty) return const [];

    try {
      final data = await _db
          .from('user_setup')
          .select(_cols)
          .eq('user_id', _userId)
          .eq('equipment', equipment.toLowerCase().trim())
          // Unpinned stations, plus any pinned to this exercise.
          .or('catalog_id.is.null,catalog_id.eq.$catalogId')
          .order('created_at', ascending: true);

      final setups = data.map((j) => ExerciseSetup.fromJson(j)).toList();
      if (setups.isEmpty) return setups;

      final settings = await _settingsFor(
        setups.map((s) => s.setupId).whereType<String>().toList(),
        catalogId,
      );

      return setups
          .map((s) => s.withSettings(settings[s.setupId] ?? const {}))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Seat heights for these stations on one exercise, keyed by station.
  static Future<Map<String, Map<String, String>>> _settingsFor(
    List<String> setupIds,
    String catalogId,
  ) async {
    if (setupIds.isEmpty) return const {};

    try {
      final data = await _db
          .from('user_setup_exercise')
          .select('setup_id, settings')
          .inFilter('setup_id', setupIds)
          .eq('catalog_id', catalogId);

      return {
        for (final row in data)
          if (row['setup_id'] case final String id)
            id: ExerciseSetup.settingsFromJson(row['settings']),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Creates a station, or updates [setupId] when one is given, and writes its
  /// settings for [catalogId].
  ///
  /// Insert-or-update rather than upsert, because which one it is genuinely
  /// matters: a save with no id is a second stack, not a correction to the
  /// first.
  ///
  /// [pinToExercise] is what keeps a dozen machines off every machine
  /// exercise — see migration 018. It's decided by the caller from the
  /// equipment, not chosen by the user, because "is this station one of many
  /// like it" is a fact about the gym rather than a preference.
  static Future<void> saveSetup({
    required String catalogId,
    required String? equipment,
    String? setupId,
    String? label,
    required Map<String, String> settings,
    double? weightIncrementKg,
    double? minWeightKg,
    bool pinToExercise = false,
  }) async {
    var id = setupId;

    final station = {
      'label': label,
      'weight_increment_kg': weightIncrementKg,
      'min_weight_kg': minWeightKg,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (id == null) {
      final created = await _db
          .from('user_setup')
          .insert({
            ...station,
            'user_id': _userId,
            'equipment': equipment?.toLowerCase().trim(),
            'catalog_id': pinToExercise ? catalogId : null,
          })
          .select('setup_id')
          .single();
      id = created['setup_id'] as String;
    } else {
      await _db
          .from('user_setup')
          .update(station)
          .eq('setup_id', id)
          .eq('user_id', _userId);
    }

    // Settings belong to the pair, so they're written even when the station
    // itself was only edited — and cleared to {} rather than deleted, so the
    // row's absence keeps meaning "never set up here".
    await _db.from('user_setup_exercise').upsert({
      'setup_id': id,
      'catalog_id': catalogId,
      'settings': settings,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'setup_id,catalog_id');
  }

  /// Records which station a logged exercise was done on. Passing null clears
  /// it, which is how you undo a mis-tap without inventing a "no setup" row.
  ///
  /// Only ever called from a tap. Nothing in the app infers this: the last
  /// version of this idea guessed, and guessed wrong — see migration 017.
  static Future<void> assignSetup(String exerciseId, String? setupId) async {
    await _db
        .from('workout_exercises')
        .update({'setup_id': setupId}).eq('exercise_id', exerciseId);
  }

  /// Forgets a station everywhere, including its seat heights on every exercise.
  ///
  /// The workouts survive — 017's foreign key sets their setup_id to NULL
  /// rather than cascading, so removing a station you no longer use can never
  /// delete training history.
  static Future<void> deleteSetup(String setupId) async {
    await _db
        .from('user_setup')
        .delete()
        .eq('setup_id', setupId)
        .eq('user_id', _userId);
  }

  /// The step this exercise appears to move in, worked out from what you've
  /// logged on it. Null when the evidence is too thin to say.
  ///
  /// Deliberately never written back automatically — the app offers this as a
  /// guess for you to accept or correct, so an inference can't harden into a
  /// stored fact behind your back.
  static Future<double?> inferIncrementFor(String catalogId) async {
    return inferIncrement(await _weightsLoggedFor(catalogId));
  }

  static Future<List<double?>> _weightsLoggedFor(String catalogId) async {
    try {
      final data = await _db
          .from('exercise_sets')
          .select('weight_kg, workout_exercises!inner(catalog_id, '
              'workout_sessions!inner(user_id))')
          .eq('workout_exercises.catalog_id', catalogId)
          .eq('workout_exercises.workout_sessions.user_id', _userId);

      return data.map((r) => (r['weight_kg'] as num?)?.toDouble()).toList();
    } catch (_) {
      return const [];
    }
  }
}
