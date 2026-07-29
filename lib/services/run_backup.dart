import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class RunBackup {
  final String sessionId;

  final DateTime date;

  final String disciplineKey;

  final double? targetMeters;

  final double distanceMeters;

  final int elapsedSeconds;

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
      disciplineKey: j['discipline_key'] as String? ?? 'running',
      targetMeters: (j['target_meters'] as num?)?.toDouble(),
      distanceMeters: (j['distance_meters'] as num?)?.toDouble() ?? 0,
      elapsedSeconds: (j['elapsed_seconds'] as num?)?.toInt() ?? 0,
      lastTargetMeters: (j['last_target_meters'] as num?)?.toDouble(),
    );
  }
}

class RunBackupStore {
  static const _key = 'run_backup_in_progress';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<void> save(RunBackup backup) async {
    try {
      final p = await _prefs;
      await p.setString(_key, jsonEncode(backup._toJson()));
    } catch (e) {
      debugPrint('RunBackupStore.save failed: $e');
    }
  }

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

  static Future<bool> exists() async => (await read()) != null;

  static Future<void> clear() async {
    try {
      final p = await _prefs;
      await p.remove(_key);
    } catch (e) {
      debugPrint('RunBackupStore.clear failed: $e');
    }
  }
}
