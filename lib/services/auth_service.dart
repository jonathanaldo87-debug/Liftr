import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/username.dart';

/// Everything the app needs to know about who's signed in.
///
/// A guest is a real Supabase user — an *anonymous* one. It has an id and a JWT,
/// so every existing row-level-security policy (`user_id = auth.uid()`) applies
/// to it unchanged, and guest workouts are stored and isolated exactly like any
/// other user's. That's the whole reason to use anonymous auth rather than a
/// local-only mode: no second storage path, no schema changes.
///
/// The catch, and it's a real one: an anonymous account can only ever be reached
/// through the session token cached on this device. There is no email to log back
/// in with. Sign out, clear the app's data, or reinstall, and those workouts are
/// gone for good — hence [upgradeToAccount], and the warnings around signing out
/// as a guest.
class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;
  static GoTrueClient get _auth => _client.auth;

  static User? get currentUser => _auth.currentUser;

  static bool get isSignedIn => _auth.currentSession != null;

  /// True for accounts created with "Continue as guest".
  static bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  /// Creates an anonymous account with a generated name.
  ///
  /// The name goes in user metadata rather than a `profiles` table: it's the
  /// only thing we'd store there, and metadata travels with the account through
  /// the upgrade to a real login for free.
  static Future<void> signInAsGuest() async {
    final username = generateUsername();
    await _auth.signInAnonymously(data: {'username': username});
  }

  /// Attaches an email and password to the current guest account.
  ///
  /// The user id does not change, so **every workout already logged is kept** —
  /// this is an upgrade, not a migration. After it succeeds the account is no
  /// longer anonymous and can be signed into from any device.
  ///
  /// If the project requires email confirmation, the address only becomes active
  /// once the user clicks the link; the password is set immediately either way.
  static Future<void> upgradeToAccount({
    required String email,
    required String password,
  }) async {
    await _auth.updateUser(
      UserAttributes(email: email, password: password),
    );
  }

  static Future<void> signOut() => _auth.signOut();

  /// What to call this person in the UI.
  ///
  /// Guests have no email, so the generated username is all there is. Real
  /// accounts fall back to the first chunk of their email address.
  static String get displayName {
    final user = _auth.currentUser;
    if (user == null) return 'Lifter';

    final username = user.userMetadata?['username'] as String?;
    if (username != null && username.trim().isNotEmpty) return username.trim();

    final email = user.email;
    if (email == null || email.isEmpty) return 'Lifter';
    return _nameFromEmail(email);
  }

  /// Just the first name, for the home header ("Hey, Swift 👋").
  static String get shortName => displayName.split(' ').first;

  /// Two letters for the avatar circle.
  static String get initials {
    final user = _auth.currentUser;
    if (user == null) return '?';

    final username = user.userMetadata?['username'] as String?;
    if (username != null && username.trim().isNotEmpty) {
      return initialsFromUsername(username.trim());
    }

    final email = user.email;
    if (email == null || email.isEmpty) return '?';
    return initialsFromEmail(email);
  }

  /// The email, or a label for guests who don't have one.
  static String get accountLabel {
    if (isGuest) return 'Guest account · not backed up';
    return _auth.currentUser?.email ?? 'Signed in';
  }

  /// "jonathan.aldo@x.com" -> "Jonathan".
  static String _nameFromEmail(String email) {
    final local = email.split('@').first;
    final first = local.split(RegExp(r'[._\-+0-9]')).firstWhere(
          (p) => p.isNotEmpty,
          orElse: () => local,
        );
    if (first.isEmpty) return 'Lifter';
    return first[0].toUpperCase() + first.substring(1);
  }

  /// "jonathanaldo87@gmail.com" -> "JO".
  static String initialsFromEmail(String email) {
    final local = email.split('@').first;
    final parts =
        local.split(RegExp(r'[._\-+]')).where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
