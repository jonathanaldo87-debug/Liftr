import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Asks whether to end the session that's already running and start a new one.
///
/// Exactly one session is active at a time, across every discipline — migration
/// 010 enforces it with a partial unique index on `user_id WHERE is_active`,
/// not on (user, discipline). You can't be at the gym and out on a run at the
/// same time, and the database is what guarantees it rather than app logic that
/// a double-tap could race past.
///
/// That leaves the app owing you a way out. Reporting "a gym session is already
/// active" and stopping is a dead end: it's true, it's not what you asked for,
/// and it leaves you to go and find the other session yourself. This is the
/// prompt [WorkoutService.endAndStartSession] was written for.
///
/// Returns true if the user chose to switch.
Future<bool> confirmSessionSwitch(
  BuildContext context, {
  required WorkoutSessions active,
  required String activeLabel,
  required String startingLabel,
}) async {
  final lt = context.lt;

  final switched = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: lt.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LiftrRadii.card),
      ),
      title: Text(
        'End your $activeLabel session?',
        style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary),
      ),
      content: Text(
        'You can only have one session going at a time. Your $activeLabel '
        'session stays saved exactly as it is — ending it just means you\'re '
        'no longer in it.',
        style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Keep $activeLabel',
            style: TextStyle(color: lt.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Start $startingLabel',
            style: const TextStyle(color: LiftrColors.accentDark),
          ),
        ),
      ],
    ),
  );

  return switched ?? false;
}
