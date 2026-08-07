import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/routine_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'routine_edit_screen.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

Future<Routine?> pickRoutine(
  BuildContext context, {
  required List<Routine> routines,
  required Discipline Function(String) disciplineFor,
  String? currentId,
  String title = 'Pick a routine',
}) {
  final lt = context.lt;

  return showModalBottomSheet<Routine>(
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
            child:
                Text(title, style: Theme.of(ctx).textTheme.displaySmall),
          ),
          const SizedBox(height: LiftrSpacing.x12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in routines)
                  ListTile(
                    leading: Text(disciplineFor(r.discipline).emoji,
                        style: const TextStyle(fontSize: LiftrType.x20)),
                    trailing: r.routineId == currentId
                        ? Icon(Icons.check_circle,
                            size: 20, color: lt.accentStrong)
                        : null,
                    title: Text(r.name,
                        style: TextStyle(
                            fontSize: LiftrType.x15, color: lt.textPrimary)),
                    subtitle: Text(
                      r.inCycle ? r.summary : '${r.summary} · off the cycle',
                      style: TextStyle(
                          fontSize: LiftrType.x12, color: lt.textMuted),
                    ),
                    onTap: () => Navigator.pop(ctx, r),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LiftrSpacing.x12),
        ],
      ),
    ),
  );
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  List<Routine> _routines = [];

  List<Discipline> _disciplines = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final routines = await RoutineService.getRoutines();
      final disciplines = await WorkoutService.getDisciplines();
      if (mounted) {
        setState(() {
          _routines = routines;
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

  List<Routine> _cycleFor(String disciplineKey) => [
        for (final r in _routines)
          if (r.discipline == disciplineKey) r,
      ];

  Future<void> _reorder(String disciplineKey, int from, int to) async {
    final cycle = _cycleFor(disciplineKey);
    if (to > from) to -= 1;

    final moved = cycle.removeAt(from);
    cycle.insert(to, moved);

    setState(() {
      _routines = [
        for (final r in _routines)
          if (r.discipline != disciplineKey) r,
        ...cycle,
      ];
    });

    try {
      await RoutineService.setCycleOrder(
        [for (final r in cycle) r.routineId!],
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save the new order: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
      await _load();
    }
  }

  List<Widget> _cycleSection(Discipline d) {
    final cycle = _cycleFor(d.key);
    if (cycle.isEmpty) return const [];

    final lt = context.lt;

    return [
      SectionLabel('${d.label} cycle'),
      const SizedBox(height: LiftrSpacing.x6),
      Text(
        'Drag to reorder. Doing one moves you to the next.',
        style: TextStyle(fontSize: LiftrType.x11, color: lt.textDim),
      ),
      const SizedBox(height: LiftrSpacing.x8),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (from, to) => _reorder(d.key, from, to),
        children: [
          for (var i = 0; i < cycle.length; i++)
            _CycleRow(
              key: ValueKey(cycle[i].routineId),
              index: i,
              routine: cycle[i],
              emoji: d.emoji,
              onTap: () => _edit(cycle[i]),
              onToggleCycle: () => _toggleInCycle(cycle[i]),
              onDelete: () => _delete(cycle[i]),
            ),
        ],
      ),
      const SizedBox(height: LiftrSpacing.x20),
    ];
  }

  Future<void> _toggleInCycle(Routine r) async {
    final id = r.routineId;
    if (id == null) return;

    try {
      await RoutineService.setInCycle(id, !r.inCycle);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not update the cycle: $e'),
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
          'The cycle closes up around it and the rest keep their order.\n\n'
          'Workouts you already filled from it keep every exercise and set. '
          'They just stop counting towards where you are in the cycle.',
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
                              'Make a routine, then another. They run in a '
                              'cycle — finish one and the next comes up, '
                              'whenever you next train.',
                              style: TextStyle(
                                  fontSize: LiftrType.x12,
                                  color: lt.textDim,
                                  height: 1.5),
                            ),
                          ),
                        for (final d in _disciplines) ..._cycleSection(d),
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
                                Icon(Icons.add, size: 16, color: lt.accentMid),
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

class _CycleRow extends StatelessWidget {
  final int index;
  final Routine routine;
  final String emoji;
  final VoidCallback onTap;
  final VoidCallback onToggleCycle;
  final VoidCallback onDelete;

  const _CycleRow({
    super.key,
    required this.index,
    required this.routine,
    required this.emoji,
    required this.onTap,
    required this.onToggleCycle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final active = routine.inCycle;

    return Padding(
      padding: const EdgeInsets.only(bottom: LiftrSpacing.x6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LiftrRadii.field),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: LiftrSpacing.x12, vertical: LiftrSpacing.x12),
          decoration: BoxDecoration(
            color: lt.card,
            border: Border.all(color: lt.border, width: LiftrBorders.hairline),
            borderRadius: BorderRadius.circular(LiftrRadii.field),
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: LiftrSpacing.x8),
                  child:
                      Icon(Icons.drag_indicator, size: 18, color: lt.textDim),
                ),
              ),
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
                        color: active ? lt.textPrimary : lt.textMuted,
                      ),
                    ),
                    const SizedBox(height: LiftrSpacing.x2),
                    Text(
                      active
                          ? routine.summary
                          : '${routine.summary} · off the cycle',
                      style: TextStyle(
                          fontSize: LiftrType.x11, color: lt.textMuted),
                    ),
                  ],
                ),
              ),
              ThreeDotMenu(actions: [
                MenuAction('Edit', onTap),
                MenuAction(
                    active ? 'Take off the cycle' : 'Put back on the cycle',
                    onToggleCycle),
                MenuAction('Delete', onDelete, isDanger: true),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
