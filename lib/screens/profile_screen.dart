import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/prefs.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'onboarding_screen.dart';

/// Account and app settings.
///
/// Also the only place the theme toggle is reachable from, and — for guests —
/// the only route to a permanent account.
class ProfileTab extends StatefulWidget {
  final VoidCallback onSignOut;
  const ProfileTab({super.key, required this.onSignOut});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

/// Signs out, but never lets a guest do it by accident.
///
/// A guest account has no email, so signing out is irreversible: the session
/// token is the only key to it, and there's no way to ask for another. Every
/// route to sign-out goes through here — Profile *and* the avatar menu on Home —
/// because a warning that only guards one of them is no warning at all.
///
/// A real account skips the dialog: signing out is harmless there.
Future<void> confirmAndSignOut(
    BuildContext context, VoidCallback doSignOut) async {
  if (!AuthService.isGuest) {
    doSignOut();
    return;
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final lt = ctx.lt;
      return AlertDialog(
        backgroundColor: lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text('Sign out of a guest account?',
            style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary)),
        content: Text(
          'A guest account only exists on this device. It has no email, so '
          'there is no way to sign back into it.\n\n'
          'Signing out permanently loses access to every workout you have '
          'logged. Add an email and password first to keep them.',
          style: TextStyle(
              fontSize: LiftrType.x13, color: lt.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text('Cancel', style: TextStyle(color: lt.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save account',
                style: TextStyle(color: LiftrColors.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'signout'),
            child: const Text('Sign out anyway',
                style: TextStyle(color: LiftrColors.danger)),
          ),
        ],
      );
    },
  );

  if (!context.mounted) return;
  if (choice == 'signout') doSignOut();
  if (choice == 'save') await openUpgradeSheet(context);
}

/// The guest → permanent account form. Returns true if the upgrade happened.
Future<bool> openUpgradeSheet(BuildContext context) async {
  final upgraded = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _UpgradeSheet(),
  );

  if (upgraded == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Account saved. Your workouts are backed up.'),
    ));
  }
  return upgraded == true;
}

class _ProfileTabState extends State<ProfileTab> {
  /// The catalog, only so saved discipline *keys* can be shown as labels.
  List<Discipline> _disciplines = [];

  @override
  void initState() {
    super.initState();
    _loadDisciplines();
  }

  Future<void> _loadDisciplines() async {
    final list = await WorkoutService.getDisciplines();
    if (mounted) setState(() => _disciplines = list);
  }

  /// e.g. "Gym · Running". Falls back to the raw key if the catalog hasn't
  /// loaded yet, so the row never sits empty.
  String get _disciplineLabel {
    final enabled = Prefs.enabledDisciplines;
    if (enabled.isEmpty) return 'Set up your training';

    return enabled.map((disciplineKey) {
      final match = _disciplines.where((d) => d.key == disciplineKey);
      return match.isEmpty ? disciplineKey : match.first.label;
    }).join(' · ');
  }

  Future<void> _confirmSignOut() =>
      confirmAndSignOut(context, widget.onSignOut);

  Future<void> _openUpgradeSheet() async {
    final upgraded = await openUpgradeSheet(context);
    // No longer a guest — the badge and warning card have to go.
    if (upgraded && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;
    final isDark = context.isDark;
    final isGuest = AuthService.isGuest;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text('Account',
              style: TextStyle(fontSize: LiftrType.x12, color: lt.textMuted)),
          const SizedBox(height: LiftrSpacing.x2),
          Text('Profile', style: tt.displaySmall),
          const SizedBox(height: LiftrSpacing.x20),

          // Identity
          Container(
            padding: const EdgeInsets.all(LiftrSpacing.x16),
            decoration: BoxDecoration(
              color: lt.surface,
              border: Border.all(
                  color: lt.borderSubtle, width: LiftrBorders.hairline),
              borderRadius: BorderRadius.circular(LiftrRadii.cardLarge),
            ),
            child: Row(
              children: [
                AvatarCircle(AuthService.initials, size: 46),
                const SizedBox(width: LiftrSpacing.x14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              AuthService.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: LiftrType.x15,
                                fontWeight: FontWeight.w500,
                                color: lt.textPrimary,
                              ),
                            ),
                          ),
                          if (isGuest) ...[
                            const SizedBox(width: LiftrSpacing.x8),
                            const AccentChip('guest'),
                          ],
                        ],
                      ),
                      const SizedBox(height: LiftrSpacing.x2),
                      Text(
                        AuthService.accountLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: LiftrType.x12, color: lt.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // The one thing a guest most needs to know, stated where they'll see it.
          if (isGuest) ...[
            const SizedBox(height: LiftrSpacing.x10),
            _GuestWarningCard(onSave: _openUpgradeSheet),
          ],

          const SizedBox(height: LiftrSpacing.x20),

          const SectionLabel('Training'),
          const SizedBox(height: LiftrSpacing.x8),
          Container(
            decoration: BoxDecoration(
              color: lt.surface,
              border: Border.all(
                  color: lt.borderSubtle, width: LiftrBorders.hairline),
              borderRadius: BorderRadius.circular(LiftrRadii.card),
            ),
            child: ListTile(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
                if (mounted) setState(() {});
              },
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x2),
              leading: Icon(Icons.tune, size: 20, color: lt.textSecondary),
              title: Text(
                // The disciplines you picked in onboarding. These are now
                // load-bearing: they decide which chips the home screen offers.
                _disciplineLabel,
                style:
                    TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
              ),
              subtitle: Text(
                'Tap to run through setup again',
                style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
              ),
            ),
          ),
          const SizedBox(height: LiftrSpacing.x20),

          const SectionLabel('Appearance'),
          const SizedBox(height: LiftrSpacing.x8),
          Container(
            decoration: BoxDecoration(
              color: lt.surface,
              border: Border.all(
                  color: lt.borderSubtle, width: LiftrBorders.hairline),
              borderRadius: BorderRadius.circular(LiftrRadii.card),
            ),
            child: SwitchListTile(
              value: isDark,
              onChanged: (_) => LiftrApp.of(context).toggleTheme(),
              activeThumbColor: LiftrColors.accentText,
              activeTrackColor: LiftrColors.accent,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x2),
              title: Text(
                'Dark mode',
                style:
                    TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
              ),
              subtitle: Text(
                isDark ? 'Dark theme is on' : 'Light theme is on',
                style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
              ),
              secondary: Icon(
                isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 20,
                color: lt.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: LiftrSpacing.x20),

          const SectionLabel('Session'),
          const SizedBox(height: LiftrSpacing.x8),
          Container(
            decoration: BoxDecoration(
              color: lt.surface,
              border: Border.all(
                  color: lt.borderSubtle, width: LiftrBorders.hairline),
              borderRadius: BorderRadius.circular(LiftrRadii.card),
            ),
            child: ListTile(
              onTap: _confirmSignOut,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x2),
              leading:
                  const Icon(Icons.logout, size: 20, color: LiftrColors.danger),
              title: const Text(
                'Sign out',
                style: TextStyle(
                    fontSize: LiftrType.x14, color: LiftrColors.danger),
              ),
              subtitle: isGuest
                  ? Text(
                      'Ends this guest account for good',
                      style: TextStyle(
                          fontSize: LiftrType.x11, color: lt.textMuted),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: LiftrSpacing.x24),

          Center(
            child: Text('Liftr',
                style: TextStyle(fontSize: LiftrType.x12, color: lt.textDim)),
          ),
        ],
      ),
    );
  }
}

// ── Guest warning ─────────────────────────────────────────────
class _GuestWarningCard extends StatelessWidget {
  final VoidCallback onSave;
  const _GuestWarningCard({required this.onSave});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Container(
      padding: const EdgeInsets.all(LiftrSpacing.x14),
      decoration: BoxDecoration(
        color: lt.accentBg,
        border:
            Border.all(color: lt.accentBorder, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: lt.accentMid),
              const SizedBox(width: LiftrSpacing.x8),
              Text(
                'This account lives on this phone only',
                style: TextStyle(
                  fontSize: LiftrType.x13,
                  fontWeight: FontWeight.w500,
                  color: lt.accentTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: LiftrSpacing.x6),
          Text(
            'Add an email and password to back your workouts up and reach them '
            'from another device. Nothing you have already logged is lost — the '
            'account is upgraded in place.',
            style: TextStyle(
                fontSize: LiftrType.x12, color: lt.textSecondary, height: 1.45),
          ),
          const SizedBox(height: LiftrSpacing.x10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSave,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
              ),
              child: const Text('Save my account'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Guest → real account ──────────────────────────────────────
class _UpgradeSheet extends StatefulWidget {
  const _UpgradeSheet();

  @override
  State<_UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends State<_UpgradeSheet> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    if (!email.contains('@') || email.length < 3) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      // Keeps the same user id, so every workout already logged comes along.
      await AuthService.upgradeToAccount(email: email, password: pass);
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save the account. Try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: lt.surface,
          border: Border.all(color: lt.border, width: LiftrBorders.hairline),
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(LiftrRadii.sheet)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: lt.border,
                  borderRadius: BorderRadius.circular(LiftrRadii.pip),
                ),
              ),
            ),
            const SizedBox(height: LiftrSpacing.x16),
            Text('Save your account', style: tt.displaySmall),
            const SizedBox(height: LiftrSpacing.x4),
            Text(
              'Your ${AuthService.displayName} history stays exactly as it is — '
              'this just adds a way to sign back in.',
              style: TextStyle(
                  fontSize: LiftrType.x12, color: lt.textMuted, height: 1.4),
            ),
            const SizedBox(height: LiftrSpacing.x18),
            const SectionLabel('Email'),
            const SizedBox(height: LiftrSpacing.x6),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
              decoration: const InputDecoration(hintText: 'you@email.com'),
            ),
            const SizedBox(height: LiftrSpacing.x12),
            const SectionLabel('Password'),
            const SizedBox(height: LiftrSpacing.x6),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
              decoration: InputDecoration(
                hintText: 'At least 6 characters',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: lt.textMuted,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: LiftrSpacing.x10),
              Text(
                _error!,
                style: const TextStyle(
                    fontSize: LiftrType.x12, color: LiftrColors.danger),
              ),
            ],
            const SizedBox(height: LiftrSpacing.x18),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LiftrColors.accentText,
                      ),
                    )
                  : const Text('Save account'),
            ),
          ],
        ),
      ),
    );
  }
}
