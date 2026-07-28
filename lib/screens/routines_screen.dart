import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/routine_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../utils/dates.dart';
import 'routine_edit_screen.dart';

/// Your routines, and which weekday each one runs on.
///
/// Two lists that read top-down as the thing you actually want to know: what's
/// on this week, then what the routines themselves contain. The week comes first
/// because that's the answer you're usually after — the routine list below it is
/// where you go to change one.
class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  List<Routine> _routines = [];
  WeeklySchedule _schedule = {};

  /// Only the disciplines that can actually hold a routine. One seeded without a
  /// logging screen has nothing to plan, so offering it would produce a routine
  /// you could never put anything in.
  List<Discipline> _disciplines = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Discipline _disciplineFor(String key) => _disciplines.firstWhere(
        (d) => d.key == key,
        orElse: () => Discipline(key: key, label: key, emoji: '•'),
      );

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final routines = await RoutineService.getRoutines();
      final schedule = await RoutineService.getSchedule();
      final disciplines = await WorkoutService.getDisciplines();
      if (mounted) {
        setState(() {
          _routines = routines;
          _schedule = schedule;
          _disciplines = [
            for (final d in disciplines)
              if (d.logsSets || d.logsDistance) d,
          ];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not load your routines: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    }
  }

  Future<void> _edit([Routine? routine]) async {
    if (_disciplines.isEmpty) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RoutineEditScreen(
          routine: routine,
          disciplines: _disciplines,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  /// Assigns a weekday, or clears it back to a rest day.
  Future<void> _assign(int weekday) async {
    final lt = context.lt;
    final current = _schedule[weekday]?.routineId;

    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: lt.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LiftrRadii.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: LiftrSpacing.x18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
              child: Text(kWeekdaysFull[weekday - 1],
                  style: Theme.of(ctx).textTheme.displaySmall),
            ),
            const SizedBox(height: LiftrSpacing.x12),
            for (final r in _routines)
              ListTile(
                leading: Text(_disciplineFor(r.discipline).emoji,
                    style: const TextStyle(fontSize: LiftrType.x20)),
                trailing: r.routineId == current
                    ? Icon(Icons.check_circle,
                        size: 20, color: lt.accentStrong)
                    : null,
                title: Text(r.name,
                    style: TextStyle(
                        fontSize: LiftrType.x15, color: lt.textPrimary)),
                subtitle: Text(r.summary,
                    style: TextStyle(
                        fontSize: LiftrType.x12, color: lt.textMuted)),
                // Returns the id, or the empty string for "leave it as it was" —
                // null is already spoken for by dismissing the sheet.
                onTap: () => Navigator.pop(ctx, r.routineId),
              ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.bedtime_outlined,
                  size: 20, color: lt.textSecondary),
              title: Text('Rest day',
                  style: TextStyle(
                      fontSize: LiftrType.x15, color: lt.textPrimary)),
              subtitle: Text('Nothing scheduled',
                  style:
                      TextStyle(fontSize: LiftrType.x12, color: lt.textMuted)),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            const SizedBox(height: LiftrSpacing.x12),
          ],
        ),
      ),
    );

    // Dismissed without choosing.
    if (picked == null || !mounted) return;

    try {
      await RoutineService.assignDay(weekday, picked.isEmpty ? null : picked);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not update the week: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    }
  }

  Future<void> _delete(Routine r) async {
    final id = r.routineId;
    if (id == null) return;

    final lt = context.lt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text('Delete ${r.name}?',
            style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary)),
        content: Text(
          'Any weekday running it becomes a rest day.\n\n'
          'Workouts you already filled from it are not affected — they hold '
          'their own exercises and never pointed back here.',
          style: TextStyle(
              fontSize: LiftrType.x13, color: lt.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: lt.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: lt.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await RoutineService.deleteRoutine(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete it: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: lt.card,
                        border: Border.all(
                            color: lt.border, width: LiftrBorders.hairline),
                        borderRadius: BorderRadius.circular(LiftrRadii.control),
                      ),
                      child: Icon(Icons.chevron_left,
                          size: 20, color: lt.textSecondary),
                    ),
                  ),
                  const SizedBox(width: LiftrSpacing.x10),
                  Expanded(
                    child: Text('Routines',
                        style: Theme.of(context).textTheme.displaySmall),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: LiftrColors.accent),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        const SectionLabel('Your week'),
                        const SizedBox(height: LiftrSpacing.x8),
                        if (_routines.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(LiftrSpacing.x16),
                            decoration: BoxDecoration(
                              color: lt.card,
                              border: Border.all(
                                  color: lt.border,
                                  width: LiftrBorders.hairline),
                              borderRadius:
                                  BorderRadius.circular(LiftrRadii.field),
                            ),
                            child: Text(
                              'Make a routine first, then you can put it on a '
                              'day.',
                              style: TextStyle(
                                  fontSize: LiftrType.x12,
                                  color: lt.textDim,
                                  height: 1.5),
                            ),
                          )
                        else
                          for (var d = 1; d <= 7; d++)
                            _DayRow(
                              weekday: d,
                              routine: _schedule[d],
                              isToday: DateTime.now().weekday == d,
                              onTap: () => _assign(d),
                            ),
                        const SizedBox(height: LiftrSpacing.x20),

                        const SectionLabel('Routines'),
                        const SizedBox(height: LiftrSpacing.x8),
                        for (final r in _routines)
                          _RoutineRow(
                            routine: r,
                            emoji: _disciplineFor(r.discipline).emoji,
                            subtitle: r.summary,
                            onTap: () => _edit(r),
                            onDelete: () => _delete(r),
                          ),
                        const SizedBox(height: LiftrSpacing.x10),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _edit(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: LiftrSpacing.x14,
                                vertical: LiftrSpacing.x12),
                            decoration: BoxDecoration(
                              color: lt.accentBg,
                              border: Border.all(
                                  color: lt.accentBorder,
                                  width: LiftrBorders.hairline),
                              borderRadius:
                                  BorderRadius.circular(LiftrRadii.field),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add,
                                    size: 16, color: lt.accentMid),
                                const SizedBox(width: LiftrSpacing.x8),
                                Text(
                                  'New routine',
                                  style: TextStyle(
                                    fontSize: LiftrType.x13,
                                    fontWeight: FontWeight.w500,
                                    color: lt.accentMid,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One weekday and what runs on it.
class _DayRow extends StatelessWidget {
  final int weekday;
  final Routine? routine;
  final bool isToday;
  final VoidCallback onTap;

  const _DayRow({
    required this.weekday,
    required this.routine,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final r = routine;

    return Padding(
      padding: const EdgeInsets.only(bottom: LiftrSpacing.x6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LiftrRadii.field),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x12),
          decoration: BoxDecoration(
            color: lt.card,
            border: Border.all(
              // Today gets the accent edge, so the week reads as a week you're
              // standing in rather than an abstract table.
              color: isToday ? lt.accentBorder : lt.border,
              width: LiftrBorders.hairline,
            ),
            borderRadius: BorderRadius.circular(LiftrRadii.field),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  kWeekdaysUpper[weekday - 1],
                  style: TextStyle(
                    fontSize: LiftrType.x11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                    color: isToday ? lt.accentMid : lt.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: LiftrSpacing.x8),
              Expanded(
                child: Text(
                  r?.name ?? 'Rest',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: LiftrType.x14,
                    fontWeight: r == null ? FontWeight.w400 : FontWeight.w500,
                    color: r == null ? lt.textDim : lt.textPrimary,
                  ),
                ),
              ),
              if (r != null) ...[
                Text(
                  r.summary,
                  style: TextStyle(
                      fontSize: LiftrType.x11, color: lt.textMuted),
                ),
                const SizedBox(width: LiftrSpacing.x8),
              ],
              Icon(Icons.chevron_right, size: 18, color: lt.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutineRow extends StatelessWidget {
  final Routine routine;
  final String emoji;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RoutineRow({
    required this.routine,
    required this.emoji,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Padding(
      padding: const EdgeInsets.only(bottom: LiftrSpacing.x6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LiftrRadii.field),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x12),
          decoration: BoxDecoration(
            color: lt.card,
            border:
                Border.all(color: lt.border, width: LiftrBorders.hairline),
            borderRadius: BorderRadius.circular(LiftrRadii.field),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: LiftrType.x18)),
              const SizedBox(width: LiftrSpacing.x10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: LiftrType.x14,
                        fontWeight: FontWeight.w500,
                        color: lt.textPrimary,
                      ),
                    ),
                    const SizedBox(height: LiftrSpacing.x2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: LiftrType.x11, color: lt.textMuted)),
                  ],
                ),
              ),
              ThreeDotMenu(onEdit: onTap, onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}
