import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/username.dart';

class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;
  static GoTrueClient get _auth => _client.auth;

  static User? get currentUser => _auth.currentUser;

  static bool get isSignedIn => _auth.currentSession != null;

  static bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  static Future<void> signInAsGuest() async {
    final username = generateUsername();
    await _auth.signInAnonymously(data: {'username': username});
  }

  static Future<void> upgradeToAccount({
    required String email,
    required String password,
  }) async {
    await _auth.updateUser(
      UserAttributes(email: email, password: password),
    );
  }

  static Future<void> signOut() => _auth.signOut();

  static String get displayName {
    final user = _auth.currentUser;
    if (user == null) return 'Lifter';

    final username = user.userMetadata?['username'] as String?;
    if (username != null && username.trim().isNotEmpty) return username.trim();

    final email = user.email;
    if (email == null || email.isEmpty) return 'Lifter';
    return _nameFromEmail(email);
  }

  static String get shortName => displayName.split(' ').first;

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

  static String get accountLabel {
    if (isGuest) return 'Guest account · not backed up';
    return _auth.currentUser?.email ?? 'Signed in';
  }

  static String _nameFromEmail(String email) {
    final local = email.split('@').first;
    final first = local.split(RegExp(r'[._\-+0-9]')).firstWhere(
          (p) => p.isNotEmpty,
          orElse: () => local,
        );
    if (first.isEmpty) return 'Lifter';
    return first[0].toUpperCase() + first.substring(1);
  }

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
