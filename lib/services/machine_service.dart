import 'package:liftr/models/models.dart';
import 'package:liftr/utils/increment_inference.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Machines: the physical stations you train on, and how you set them up.
///
/// Everything here is optional by design. An account with no machines behaves
/// exactly as the app did before they existed — the machine is only ever
/// recorded because you chose to distinguish one station from another, and the
/// picker doesn't render until you have two to choose between.
///
/// The arithmetic lives in `utils/increment_inference.dart`, which is pure and
/// tested. This class is the IO around it.
class MachineService {
  static final _db = Supabase.instance.client;

  static String get _userId {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  static const _machineCols =
      'machine_id, label, weight_increment_kg, min_weight_kg, notes, created_at';

  // ── Machines ────────────────────────────────────────────────

  /// Every machine you've registered, oldest first.
  ///
  /// Returns an empty list rather than throwing: machines are an enhancement,
  /// and failing to load them must never block logging a set.
  static Future<List<UserMachine>> getMachines() async {
    try {
      final data = await _db
          .from('user_machines')
          .select(_machineCols)
          .eq('user_id', _userId)
          .order('created_at', ascending: true);

      return data.map((j) => UserMachine.fromJson(j)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The machines worth offering for [catalogId], best candidates first.
  ///
  /// Ones you've already used for this exercise come first — a cable stack you
  /// do pushdowns on is a likelier answer for pushdowns than the leg press —
  /// followed by the rest, because the first time you use an existing station
  /// for a new movement it has no history yet and still needs to be reachable.
  static Future<List<UserMachine>> getCandidates(String catalogId) async {
    final all = await getMachines();
    if (all.length < 2) return all;

    final used = await _machineIdsUsedFor(catalogId);
    if (used.isEmpty) return all;

    final familiar = all.where((m) => used.contains(m.machineId)).toList();
    final rest = all.where((m) => !used.contains(m.machineId)).toList();
    return [...familiar, ...rest];
  }

  static Future<Set<String>> _machineIdsUsedFor(String catalogId) async {
    try {
      final data = await _db
          .from('workout_exercises')
          .select('machine_id, workout_sessions!inner(user_id)')
          .eq('catalog_id', catalogId)
          .eq('workout_sessions.user_id', _userId)
          .not('machine_id', 'is', null);

      return data
          .map((r) => r['machine_id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Registers a machine and returns its id.
  static Future<String> createMachine({
    required String label,
    double? weightIncrementKg,
    double? minWeightKg,
    String? notes,
  }) async {
    final result = await _db
        .from('user_machines')
        .insert({
          'user_id': _userId,
          'label': label.trim(),
          'weight_increment_kg': weightIncrementKg,
          'min_weight_kg': minWeightKg,
          'notes': notes,
        })
        .select('machine_id')
        .single();

    return result['machine_id'] as String;
  }

  static Future<void> updateMachine(
    String machineId, {
    required String label,
    double? weightIncrementKg,
    double? minWeightKg,
    String? notes,
  }) async {
    await _db.from('user_machines').update({
      'label': label.trim(),
      'weight_increment_kg': weightIncrementKg,
      'min_weight_kg': minWeightKg,
      'notes': notes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('machine_id', machineId);
  }

  /// Forgets a machine. The workouts done on it survive — migration 012 sets
  /// their `machine_id` to NULL rather than cascading, so deleting a machine you
  /// no longer train on can never delete training history.
  static Future<void> deleteMachine(String machineId) async {
    await _db.from('user_machines').delete().eq('machine_id', machineId);
  }

  // ── Per-exercise setup ──────────────────────────────────────

  /// How [machineId] is set up for [catalogId] — seat 4, back pad 2.
  static Future<MachineExerciseSettings?> getSettings(
    String machineId,
    String catalogId,
  ) async {
    try {
      final data = await _db
          .from('machine_exercise_settings')
          .select('machine_id, catalog_id, settings, notes')
          .eq('machine_id', machineId)
          .eq('catalog_id', catalogId)
          .limit(1);

      if (data.isEmpty) return null;
      return MachineExerciseSettings.fromJson(data.first);
    } catch (_) {
      return null;
    }
  }

  /// Writes the setup for one (machine, exercise) pair.
  ///
  /// Upsert rather than insert-or-update: the row is created the first time you
  /// type a seat height and edited every time after, and the caller has no
  /// reason to care which of those it is.
  static Future<void> saveSettings(
    String machineId,
    String catalogId, {
    required Map<String, String> settings,
    String? notes,
  }) async {
    await _db.from('machine_exercise_settings').upsert({
      'machine_id': machineId,
      'catalog_id': catalogId,
      'settings': settings,
      'notes': notes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'machine_id,catalog_id');
  }

  // ── Assignment ──────────────────────────────────────────────

  /// Records which station an exercise was done on. Passing null clears it,
  /// which is how you undo a mis-tap without inventing a "no machine" row.
  static Future<void> assignMachine(String exerciseId, String? machineId) async {
    await _db
        .from('workout_exercises')
        .update({'machine_id': machineId}).eq('exercise_id', exerciseId);
  }

  // ── Inference ───────────────────────────────────────────────

  /// The step [machineId] appears to move in, worked out from what you've
  /// logged on it. Null when the evidence is too thin to say.
  ///
  /// Scoped to the machine, not the exercise: a cable stack has one step across
  /// every movement you do on it, so pushdowns and curls are evidence about the
  /// same stack. Deliberately never written back automatically — the app offers
  /// this as a guess for you to accept or correct, so an inference can't harden
  /// into a stored fact behind your back.
  static Future<double?> inferIncrementFor(String machineId) async {
    final weights = await _weightsLoggedOn(machineId);
    return inferIncrement(weights);
  }

  /// The step suggested for an exercise with no machine recorded.
  ///
  /// Falls back to the whole of that exercise's history. Worth less than the
  /// per-machine answer — if you've been alternating two stacks, this history is
  /// a blend of both — which is exactly what [looksLikeTwoMachines] is for.
  static Future<double?> inferIncrementForExercise(String catalogId) async {
    final weights = await _weightsLoggedForExercise(catalogId);
    return inferIncrement(weights);
  }

  /// Whether an exercise's history looks like it came from two different
  /// stations. Drives the offer to split it, and a warning that a suggestion
  /// built on the blend may not be loadable.
  static Future<bool> historyLooksMixed(String catalogId) async {
    final weights = await _weightsLoggedForExercise(catalogId);
    return looksLikeTwoMachines(weights);
  }

  static Future<List<double?>> _weightsLoggedOn(String machineId) async {
    try {
      final data = await _db
          .from('exercise_sets')
          .select('weight_kg, workout_exercises!inner(machine_id, '
              'workout_sessions!inner(user_id))')
          .eq('workout_exercises.machine_id', machineId)
          .eq('workout_exercises.workout_sessions.user_id', _userId);

      return data.map((r) => (r['weight_kg'] as num?)?.toDouble()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<double?>> _weightsLoggedForExercise(
      String catalogId) async {
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
