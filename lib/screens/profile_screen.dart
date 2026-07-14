import 'package:flutter/material.dart';
import '../main.dart';
import '../services/prefs.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'onboarding_screen.dart';

/// Account and app settings. Also the only place the theme toggle is reachable
/// from — `LiftrApp.toggleTheme` existed but nothing ever called it.
class ProfileTab extends StatelessWidget {
  final VoidCallback onSignOut;
  const ProfileTab({super.key, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;
    final email = WorkoutService.currentUser?.email ?? 'Signed in';
    final isDark = context.isDark;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text('Account', style: TextStyle(fontSize: 12, color: lt.textMuted)),
          const SizedBox(height: 2),
          Text('Profile', style: tt.displaySmall),
          const SizedBox(height: 20),

          // Identity
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: lt.surface,
              border: Border.all(color: lt.borderSubtle, width: 0.5),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                AvatarCircle(initialsFor(email), size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayNameFor(email),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: lt.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: lt.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const SectionLabel('Training'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: lt.surface,
              border: Border.all(color: lt.borderSubtle, width: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              leading: Icon(Icons.tune, size: 20, color: lt.textSecondary),
              title: Text(
                // Answers from onboarding. They're recorded but don't change how
                // the app behaves yet — it logs gym lifts either way.
                [Prefs.activity, Prefs.level]
                        .whereType<String>()
                        .join(' · ')
                        .trim()
                        .isEmpty
                    ? 'Set up your training'
                    : '${Prefs.activity} · ${Prefs.level}',
                style: TextStyle(fontSize: 14, color: lt.textPrimary),
              ),
              subtitle: Text(
                'Tap to run through setup again',
                style: TextStyle(fontSize: 11, color: lt.textMuted),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const SectionLabel('Appearance'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: lt.surface,
              border: Border.all(color: lt.borderSubtle, width: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile(
              value: isDark,
              onChanged: (_) => LiftrApp.of(context).toggleTheme(),
              activeThumbColor: LiftrColors.accentText,
              activeTrackColor: LiftrColors.accent,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              title: Text(
                'Dark mode',
                style: TextStyle(fontSize: 14, color: lt.textPrimary),
              ),
              subtitle: Text(
                isDark ? 'Dark theme is on' : 'Light theme is on',
                style: TextStyle(fontSize: 11, color: lt.textMuted),
              ),
              secondary: Icon(
                isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 20,
                color: lt.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),

          const SectionLabel('Session'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: lt.surface,
              border: Border.all(color: lt.borderSubtle, width: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              onTap: onSignOut,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              leading: const Icon(Icons.logout,
                  size: 20, color: Color(0xFFE24B4A)),
              title: const Text(
                'Sign out',
                style: TextStyle(fontSize: 14, color: Color(0xFFE24B4A)),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Center(
            child: Text(
              'Liftr',
              style: TextStyle(fontSize: 12, color: lt.textDim),
            ),
          ),
        ],
      ),
    );
  }

  /// "jonathanaldo87@gmail.com" → "JO". Shared with the home header so the
  /// avatar reads the same in both places.
  static String initialsFor(String email) {
    final local = email.split('@').first;
    final parts = local
        .split(RegExp(r'[._\-+]'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  /// "jonathan.aldo@x.com" → "Jonathan".
  static String displayNameFor(String email) {
    final local = email.split('@').first;
    final first = local.split(RegExp(r'[._\-+0-9]')).firstWhere(
          (p) => p.isNotEmpty,
          orElse: () => local,
        );
    if (first.isEmpty) return 'Lifter';
    return first[0].toUpperCase() + first.substring(1);
  }
}
