import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A snapshot of the leg you're running right now, for surviving a crash.
///
/// Completed intervals are already in Supabase — inserted the moment each one
/// finished — so the only thing a crash can lose is the leg in progress, the one
/// that hasn't been saved anywhere yet. This is that leg: enough to reopen the
/// run where it stopped rather than from zero.
///
/// The GPS baseline is deliberately *not* stored. A fix from before the crash
/// and the first fix after it are minutes and possibly streets apart, and
/// counting the gap between them as distance run would be a lie; restore resumes
/// the total and takes a fresh baseline instead.
@immutable
class RunBackup {
  final String sessionId;

  /// The day the session belongs to — needed to reopen it, since a run is filed
  /// by date.
  final DateTime date;

  /// Which distance discipline this was, so recovery reopens with the right
  /// label and emoji rather than assuming 'running' — a cycling discipline
  /// seeded as `logging_type = 'distance'` recovers as cycling.
  final String disciplineKey;

  /// What this leg was aiming for, or null for a free run. Restored so the
  /// remaining-distance display and the target vibration still mean something.
  final double? targetMeters;

  /// Distance accumulated before the crash. Restored straight into the
  /// accumulator's total.
  final double distanceMeters;

  /// Seconds elapsed before the crash. The run's clock picks up from here rather
  /// than restarting, so a recovered 20-minute run doesn't read as 20 seconds.
  final int elapsedSeconds;

  /// The last target the user set this session, so "Add another interval" after
  /// a recovery still pre-fills what it would have.
  final double? lastTargetMeters;

  const RunBackup({
    required this.sessionId,
    required this.date,
    required this.disciplineKey,
    required this.targetMeters,
    required this.distanceMeters,
    required this.elapsedSeconds,
    required this.lastTargetMeters,
  });

  Map<String, dynamic> _toJson() => {
        'session_id': sessionId,
        'date': date.toIso8601String(),
        'discipline_key': disciplineKey,
        'target_meters': targetMeters,
        'distance_meters': distanceMeters,
        'elapsed_seconds': elapsedSeconds,
        'last_target_meters': lastTargetMeters,
      };

  static RunBackup? _fromJson(Map<String, dynamic> j) {
    final sessionId = j['session_id'] as String?;
    final dateStr = j['date'] as String?;
    if (sessionId == null || dateStr == null) return null;

    final date = DateTime.tryParse(dateStr);
    if (date == null) return null;

    return RunBackup(
      sessionId: sessionId,
      date: date,
      // Older backups predate this field; default to running rather than reject
      // a recoverable leg over a label.
      disciplineKey: j['discipline_key'] as String? ?? 'running',
      targetMeters: (j['target_meters'] as num?)?.toDouble(),
      distanceMeters: (j['distance_meters'] as num?)?.toDouble() ?? 0,
      elapsedSeconds: (j['elapsed_seconds'] as num?)?.toInt() ?? 0,
      lastTargetMeters: (j['last_target_meters'] as num?)?.toDouble(),
    );
  }
}

/// Reads and writes the single [RunBackup] on the device.
///
/// Lives in SharedPreferences rather than the database on purpose: it's written
/// every few seconds during a run and thrown away on the next successful save,
/// so a network round trip per tick would be both wasteful and exactly the wrong
/// thing to depend on when the phone might be out of signal. At most one backup
/// exists — a person runs one leg at a time.
class RunBackupStore {
  static const _key = 'run_backup_in_progress';

  /// Called lazily rather than in `main()`: recovery only matters once, on the
  /// first thing that asks, and the run feature shouldn't tax cold start for it.
  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  /// Writes the current leg, replacing any previous snapshot. Errors are
  /// swallowed — a backup that fails to write must never interrupt the run it's
  /// backing up.
  static Future<void> save(RunBackup backup) async {
    try {
      final p = await _prefs;
      await p.setString(_key, jsonEncode(backup._toJson()));
    } catch (e) {
      debugPrint('RunBackupStore.save failed: $e');
    }
  }

  /// The stored leg, or null if there's nothing to recover. A corrupt or
  /// half-written entry reads as null and is dropped rather than crashing the
  /// launch that tried to restore it.
  static Future<RunBackup?> read() async {
    try {
      final p = await _prefs;
      final raw = p.getString(_key);
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return RunBackup._fromJson(decoded);
    } catch (e) {
      debugPrint('RunBackupStore.read failed: $e');
      return null;
    }
  }

  /// Whether a backup is waiting — the cheap check the home screen runs on load
  /// before deciding whether to offer a restore.
  static Future<bool> exists() async => (await read()) != null;

  /// Drops the backup. Called on a successful save or a deliberate discard —
  /// once the leg has a home, or has been thrown away, there's nothing left to
  /// recover.
  static Future<void> clear() async {
    try {
      final p = await _prefs;
      await p.remove(_key);
    } catch (e) {
      debugPrint('RunBackupStore.clear failed: $e');
    }
  }
}
