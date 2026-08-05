import 'package:shared_preferences/shared_preferences.dart';

import '../models/discipline.dart';

class Prefs {
  static late final SharedPreferences _p;

  static const _seenOnboarding = 'seen_onboarding';
  static const _disciplines = 'enabled_disciplines';
  static const _darkMode = 'dark_mode';
  static const _restSeconds = 'rest_seconds';
  static const _restAutoStart = 'rest_auto_start';

  static const restPresets = [30, 45, 60, 90, 120, 150, 180, 240, 300];

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static bool get hasOnboarded => _p.getBool(_seenOnboarding) ?? false;

  static List<String> get enabledDisciplines {
    final saved = _p.getStringList(_disciplines);
    if (saved == null || saved.isEmpty) return const [Discipline.gymKey];
    return saved;
  }

  static bool get isDarkMode => _p.getBool(_darkMode) ?? true;

  static Future<void> setDarkMode(bool value) => _p.setBool(_darkMode, value);

  static int get restSeconds => _p.getInt(_restSeconds) ?? 90;

  static Future<void> setRestSeconds(int value) =>
      _p.setInt(_restSeconds, value);

  static bool get restAutoStart => _p.getBool(_restAutoStart) ?? true;

  static Future<void> setRestAutoStart(bool value) =>
      _p.setBool(_restAutoStart, value);

  static bool isEnabled(String disciplineKey) =>
      enabledDisciplines.contains(disciplineKey);

  static bool get doesGym => isEnabled(Discipline.gymKey);

  static Future<void> completeOnboarding({
    required List<String> disciplines,
  }) async {
    await _p.setStringList(_disciplines, disciplines);
    await _p.setBool(_seenOnboarding, true);
  }
}
