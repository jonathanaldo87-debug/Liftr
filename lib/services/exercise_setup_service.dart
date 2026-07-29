import 'package:liftr/models/models.dart';
import 'package:liftr/utils/increment_inference.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    await _db.from('user_setup_exercise').upsert({
      'setup_id': id,
      'catalog_id': catalogId,
      'settings': settings,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'setup_id,catalog_id');
  }

  static Future<void> assignSetup(String exerciseId, String? setupId) async {
    await _db
        .from('workout_exercises')
        .update({'setup_id': setupId}).eq('exercise_id', exerciseId);
  }

  static Future<void> deleteSetup(String setupId) async {
    await _db
        .from('user_setup')
        .delete()
        .eq('setup_id', setupId)
        .eq('user_id', _userId);
  }

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
