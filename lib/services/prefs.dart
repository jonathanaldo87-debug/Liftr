import 'package:shared_preferences/shared_preferences.dart';

/// On-device settings. Nothing here is worth a database round trip, and it has
/// to be readable synchronously at startup to decide the first screen — so it
/// lives in SharedPreferences, loaded once in `main()`.
class Prefs {
  static late final SharedPreferences _p;

  static const _seenOnboarding = 'seen_onboarding';
  static const _activity = 'onboarding_activity';
  static const _level = 'onboarding_level';

  /// Must be awaited before `runApp`, so [hasOnboarded] can be read without a
  /// loading flicker on the very first frame.
  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  /// True once the user has been through onboarding. Gates it to first launch:
  /// showing it every time would be worse than never showing it at all.
  static bool get hasOnboarded => _p.getBool(_seenOnboarding) ?? false;

  /// e.g. "Gym".
  static String? get activity => _p.getString(_activity);

  /// e.g. "Intermediate".
  static String? get level => _p.getString(_level);

  /// Also called when re-running the flow from Profile, which just overwrites
  /// the previous answers.
  static Future<void> completeOnboarding({
    required String activity,
    required String level,
  }) async {
    await _p.setString(_activity, activity);
    await _p.setString(_level, level);
    await _p.setBool(_seenOnboarding, true);
  }
}
