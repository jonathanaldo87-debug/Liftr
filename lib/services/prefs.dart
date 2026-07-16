import 'package:shared_preferences/shared_preferences.dart';

import '../models/discipline.dart';

/// On-device settings. Nothing here is worth a database round trip, and it has
/// to be readable synchronously at startup to decide the first screen — so it
/// lives in SharedPreferences, loaded once in `main()`.
class Prefs {
  static late final SharedPreferences _p;

  static const _seenOnboarding = 'seen_onboarding';
  static const _disciplines = 'enabled_disciplines';

  /// Must be awaited before `runApp`, so [hasOnboarded] can be read without a
  /// loading flicker on the very first frame.
  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  /// True once the user has been through onboarding. Gates it to first launch:
  /// showing it every time would be worse than never showing it at all.
  static bool get hasOnboarded => _p.getBool(_seenOnboarding) ?? false;

  /// The discipline keys this user actually trains — what the home chips offer.
  ///
  /// Falls back to gym rather than an empty list: a user with no disciplines has
  /// no way to log anything, and that's a worse failure than a wrong default.
  static List<String> get enabledDisciplines {
    final saved = _p.getStringList(_disciplines);
    if (saved == null || saved.isEmpty) return const [Discipline.gymKey];
    return saved;
  }

  static bool isEnabled(String disciplineKey) =>
      enabledDisciplines.contains(disciplineKey);

  static bool get doesGym => isEnabled(Discipline.gymKey);

  /// Also called when re-running the flow from Profile, which just overwrites
  /// the previous answers.
  static Future<void> completeOnboarding({
    required List<String> disciplines,
  }) async {
    await _p.setStringList(_disciplines, disciplines);
    await _p.setBool(_seenOnboarding, true);
  }
}
