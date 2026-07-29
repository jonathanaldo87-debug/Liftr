import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/routine_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../utils/exercise_search.dart';
import '../utils/format.dart';
import '../utils/run_math.dart';
import 'target_sheet.dart';

class RoutineEditScreen extends StatefulWidget {
  final Routine? routine;

  final List<Discipline> disciplines;

  const RoutineEditScreen({
    super.key,
    this.routine,
    required this.disciplines,
  });

  @override
  State<RoutineEditScreen> createState() => _RoutineEditScreenState();
}

class _RoutineEditScreenState extends State<RoutineEditScreen> {
  final _nameCtrl = TextEditingController();

  final List<CatalogExercises> _picked = [];

  final List<double> _targets = [];

  List<CatalogExercises> _catalog = [];
  ExerciseSearch? _search;

  late Discipline _discipline;

  bool _nameError = false;
  bool _isSaving = false;
  bool _isLoading = true;

  bool get _isNew => widget.routine?.routineId == null;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.routine?.name ?? '';

    final key = widget.routine?.discipline;
    _discipline = widget.disciplines.firstWhere(
      (d) => d.key == key,
      orElse: () => widget.disciplines.first,
    );

    _load();
  }

  Future<void> _load() async {
    final catalog = await WorkoutService.getExerciseCatalog();
    if (!mounted) return;

    final byId = {for (final e in catalog) e.catalogId: e};
    final existing = <CatalogExercises>[];
    for (final line in widget.routine?.exercises ?? const <RoutineExercise>[]) {
      final match = byId[line.catalogId];
      if (match != null) existing.add(match);
    }

    setState(() {
      _catalog = catalog;
      _search = ExerciseSearch(catalog);
      _picked
        ..clear()
        ..addAll(existing);
      _targets
        ..clear()
        ..addAll([
          for (final i in widget.routine?.intervals ?? const <RoutineInterval>[])
            i.targetDistanceMeters,
        ]);
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final id = _isNew
          ? await RoutineService.createRoutine(name,
              discipline: _discipline.key)
          : widget.routine!.routineId!;

      if (!_isNew) await RoutineService.renameRoutine(id, name);

      if (_discipline.logsDistance) {
        await RoutineService.setIntervals(id, _targets);
      } else {
        await RoutineService.setExercises(
          id,
          [for (final e in _picked) e.catalogId].whereType<String>().toList(),
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save the routine: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    }
  }

  Future<void> _addExercises() async {
    final search = _search;
    if (search == null) return;

    final added = await showModalBottomSheet<List<CatalogExercises>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExercisePickerSheet(search: search, catalog: _catalog),
    );

    if (added != null && added.isNotEmpty && mounted) {
      setState(() => _picked.addAll(added));
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
                    onTap: _isSaving ? null : () => Navigator.pop(context),
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
                    child: Text(
                      _isNew ? 'New routine' : 'Edit routine',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
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
                  : _form(lt),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _isSaving ? null : () => Navigator.pop(context),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: lt.card,
                          border: Border.all(
                              color: lt.border, width: LiftrBorders.hairline),
                          borderRadius:
                              BorderRadius.circular(LiftrRadii.button),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: LiftrType.x15,
                              fontWeight: FontWeight.w500,
                              color: lt.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: LiftrSpacing.x10),
                  Expanded(
                    child: ElevatedButton(
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
                          : const Text('Save'),
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

  Widget _form(LiftrTheme lt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Name'),
          const SizedBox(height: LiftrSpacing.x8),
          Container(
            decoration: BoxDecoration(
              color: lt.card,
              border: Border.all(
                color: _nameError ? LiftrColors.danger : lt.border,
                width:
                    _nameError ? LiftrBorders.thin : LiftrBorders.hairline,
              ),
              borderRadius: BorderRadius.circular(LiftrRadii.field),
            ),
            child: TextField(
              controller: _nameCtrl,
              onChanged: (_) {
                if (_nameError) setState(() => _nameError = false);
              },
              style:
                  TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
              decoration: const InputDecoration(
                hintText: 'e.g. Push',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: LiftrSpacing.x14,
                    vertical: LiftrSpacing.x14),
                fillColor: Colors.transparent,
              ),
            ),
          ),
          if (_nameError) ...[
            const SizedBox(height: LiftrSpacing.x5),
            const Text(
              'Give the routine a name',
              style: TextStyle(
                  fontSize: LiftrType.x11, color: LiftrColors.danger),
            ),
          ],
          const SizedBox(height: LiftrSpacing.x20),

          if (_isNew && widget.disciplines.length > 1) ...[
            const SectionLabel('For'),
            const SizedBox(height: LiftrSpacing.x8),
            Row(
              children: [
                for (final d in widget.disciplines) ...[
                  _DisciplineChoice(
                    discipline: d,
                    isSelected: d.key == _discipline.key,
                    onTap: () => setState(() => _discipline = d),
                  ),
                  const SizedBox(width: LiftrSpacing.x6),
                ],
              ],
            ),
            const SizedBox(height: LiftrSpacing.x20),
          ],

          if (_discipline.logsDistance)
            ..._targetsSection(lt)
          else
            ..._exercisesSection(lt),

          const SizedBox(height: LiftrSpacing.x32),
        ],
      ),
    );
  }

  List<Widget> _exercisesSection(LiftrTheme lt) => [
        Row(
          children: [
            const SectionLabel('Exercises'),
            const Spacer(),
            if (_picked.isNotEmpty)
              Text('${_picked.length}',
                  style: TextStyle(
                      fontSize: LiftrType.x11, color: lt.textMuted)),
          ],
        ),
        const SizedBox(height: LiftrSpacing.x8),
        if (_picked.isEmpty)
          _EmptyBox(lt,
              'Nothing in this routine yet.\n'
              'Add the exercises you do on this day, in the order you do them.')
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _picked.length,
            onReorder: (from, to) => setState(() {
              if (to > from) to -= 1;
              _picked.insert(to, _picked.removeAt(from));
            }),
            itemBuilder: (_, i) => _PickedRow(
              key: ValueKey('${_picked[i].catalogId}#$i'),
              exercise: _picked[i],
              index: i,
              onRemove: () => setState(() => _picked.removeAt(i)),
            ),
          ),
        const SizedBox(height: LiftrSpacing.x10),
        _AddRow(label: 'Add exercises', onTap: _addExercises),
      ];

  List<Widget> _targetsSection(LiftrTheme lt) => [
        Row(
          children: [
            const SectionLabel('Targets'),
            const Spacer(),
            if (_targets.isNotEmpty)
              Text(formatDistance(_targets.fold<double>(0, (a, b) => a + b)),
                  style: TextStyle(
                      fontSize: LiftrType.x11, color: lt.textMuted)),
          ],
        ),
        const SizedBox(height: LiftrSpacing.x8),
        if (_targets.isEmpty)
          _EmptyBox(lt,
              'No targets — this day is just a run.\n'
              'Add one for a set distance, or several for intervals.')
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _targets.length,
            onReorder: (from, to) => setState(() {
              if (to > from) to -= 1;
              _targets.insert(to, _targets.removeAt(from));
            }),
            itemBuilder: (_, i) => _TargetRow(
              key: ValueKey('${_targets[i]}#$i'),
              meters: _targets[i],
              index: i,
              label: _targets.length == 1 ? null : 'Leg ${i + 1}',
              onRemove: () => setState(() => _targets.removeAt(i)),
            ),
          ),
        const SizedBox(height: LiftrSpacing.x10),
        _AddRow(label: 'Add a target', onTap: _addTarget),
      ];

  Future<void> _addTarget() async {
    final meters = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TargetSheet(),
    );
    if (meters != null && mounted) setState(() => _targets.add(meters));
  }
}

class _EmptyBox extends StatelessWidget {
  final LiftrTheme lt;
  final String message;
  const _EmptyBox(this.lt, this.message);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            vertical: LiftrSpacing.x20, horizontal: LiftrSpacing.x16),
        decoration: BoxDecoration(
          color: lt.card,
          border: Border.all(color: lt.border, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.field),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: LiftrType.x12, color: lt.textDim, height: 1.5),
        ),
      );
}

class _AddRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x12),
        decoration: BoxDecoration(
          color: lt.accentBg,
          border:
              Border.all(color: lt.accentBorder, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.field),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 16, color: lt.accentMid),
            const SizedBox(width: LiftrSpacing.x8),
            Text(
              label,
              style: TextStyle(
                fontSize: LiftrType.x13,
                fontWeight: FontWeight.w500,
                color: lt.accentMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisciplineChoice extends StatelessWidget {
  final Discipline discipline;
  final bool isSelected;
  final VoidCallback onTap;

  const _DisciplineChoice({
    required this.discipline,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x12, vertical: LiftrSpacing.x8),
        decoration: BoxDecoration(
          color: isSelected ? LiftrColors.accent : lt.card,
          border: Border.all(
            color: isSelected ? LiftrColors.accent : lt.border,
            width: LiftrBorders.hairline,
          ),
          borderRadius: BorderRadius.circular(LiftrRadii.panel),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(discipline.emoji,
                style: const TextStyle(fontSize: LiftrType.x13)),
            const SizedBox(width: LiftrSpacing.x6),
            Text(
              discipline.label,
              style: TextStyle(
                fontSize: LiftrType.x13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? LiftrColors.accentText : lt.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final double meters;
  final int index;
  final String? label;
  final VoidCallback onRemove;

  const _TargetRow({
    super.key,
    required this.meters,
    required this.index,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Padding(
      padding: const EdgeInsets.only(bottom: LiftrSpacing.x6),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x12, vertical: LiftrSpacing.x10),
        decoration: BoxDecoration(
          color: lt.card,
          border: Border.all(color: lt.border, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.field),
        ),
        child: Row(
          children: [
            if (label != null) ...[
              SizedBox(
                width: 46,
                child: Text(
                  label!,
                  style: TextStyle(
                      fontSize: LiftrType.x11, color: lt.textMuted),
                ),
              ),
              const SizedBox(width: LiftrSpacing.x4),
            ],
            Expanded(
              child: Text(
                formatDistance(meters),
                style: TextStyle(
                  fontSize: LiftrType.x14,
                  fontWeight: FontWeight.w500,
                  color: lt.textPrimary,
                ),
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: LiftrSpacing.x6, vertical: LiftrSpacing.x4),
                child: Icon(Icons.close, size: 16, color: lt.textDim),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(left: LiftrSpacing.x4),
                child: Icon(Icons.drag_handle, size: 18, color: lt.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedRow extends StatelessWidget {
  final CatalogExercises exercise;
  final int index;
  final VoidCallback onRemove;

  const _PickedRow({
    super.key,
    required this.exercise,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final subtitle = detailLine([exercise.equipment, exercise.muscleGroup]);

    return Padding(
      padding: const EdgeInsets.only(bottom: LiftrSpacing.x6),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x12, vertical: LiftrSpacing.x8),
        decoration: BoxDecoration(
          color: lt.card,
          border: Border.all(color: lt.border, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.field),
        ),
        child: Row(
          children: [
            Text(
              exerciseEmoji(exercise.category, exercise.muscleGroup),
              style: const TextStyle(fontSize: LiftrType.x16),
            ),
            const SizedBox(width: LiftrSpacing.x10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: LiftrType.x13,
                      fontWeight: FontWeight.w500,
                      color: lt.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: LiftrSpacing.x2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: LiftrType.x11, color: lt.textMuted)),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: LiftrSpacing.x6, vertical: LiftrSpacing.x4),
                child: Icon(Icons.close, size: 16, color: lt.textDim),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding:
                    const EdgeInsets.only(left: LiftrSpacing.x4),
                child: Icon(Icons.drag_handle, size: 18, color: lt.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExercisePickerSheet extends StatefulWidget {
  final ExerciseSearch search;
  final List<CatalogExercises> catalog;

  const _ExercisePickerSheet({required this.search, required this.catalog});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _ctrl = TextEditingController();

  final List<CatalogExercises> _chosen = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<CatalogExercises> get _results {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return widget.catalog.take(30).toList();
    return widget.search.search(q).toList();
  }

  void _toggle(CatalogExercises e) => setState(() {
        final i = _chosen.indexWhere((x) => x.catalogId == e.catalogId);
        if (i >= 0) {
          _chosen.removeAt(i);
        } else {
          _chosen.add(e);
        }
      });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final results = _results;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: lt.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(LiftrRadii.sheet)),
        ),
        child: Column(
          children: [
            const SizedBox(height: LiftrSpacing.x12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: lt.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: LiftrSpacing.x14),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: LiftrSpacing.x16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: LiftrSpacing.x14),
                decoration: BoxDecoration(
                  color: lt.card,
                  border: Border.all(
                      color: lt.border, width: LiftrBorders.hairline),
                  borderRadius: BorderRadius.circular(LiftrRadii.field),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: lt.textDim),
                    const SizedBox(width: LiftrSpacing.x8),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                            fontSize: LiftrType.x14, color: lt.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search exercises…',
                          hintStyle: TextStyle(
                              fontSize: LiftrType.x14, color: lt.textDim),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: LiftrSpacing.x14),
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                    if (_ctrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _ctrl.clear();
                          setState(() {});
                        },
                        child:
                            Icon(Icons.close, size: 16, color: lt.textDim),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: LiftrSpacing.x10),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing matches that.',
                        style: TextStyle(
                            fontSize: LiftrType.x13, color: lt.textDim),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final e = results[i];
                        final picked = _chosen
                            .any((x) => x.catalogId == e.catalogId);
                        return _PickerRow(
                          exercise: e,
                          isPicked: picked,
                          onTap: () => _toggle(e),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _chosen.isEmpty
                      ? null
                      : () => Navigator.pop(context, _chosen),
                  child: Text(_chosen.isEmpty
                      ? 'Pick some exercises'
                      : 'Add ${_chosen.length}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final CatalogExercises exercise;
  final bool isPicked;
  final VoidCallback onTap;

  const _PickerRow({
    required this.exercise,
    required this.isPicked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final subtitle = detailLine([exercise.equipment, exercise.muscleGroup]);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x16, vertical: LiftrSpacing.x10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: lt.card,
                borderRadius: BorderRadius.circular(LiftrRadii.control),
              ),
              child: Center(
                child: Text(
                  exerciseEmoji(exercise.category, exercise.muscleGroup),
                  style: const TextStyle(fontSize: LiftrType.x16),
                ),
              ),
            ),
            const SizedBox(width: LiftrSpacing.x10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: LiftrType.x13,
                      fontWeight: FontWeight.w500,
                      color: lt.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: LiftrSpacing.x2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: LiftrType.x11, color: lt.textMuted)),
                  ],
                ],
              ),
            ),
            Icon(
              isPicked ? Icons.check_circle : Icons.add_circle_outline,
              size: 20,
              color: isPicked ? lt.accentStrong : lt.textDim,
            ),
          ],
        ),
      ),
    );
  }
}
