import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/machine_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../utils/format.dart';
import 'machine_sheets.dart';

class ExerciseDetailScreen extends StatefulWidget {
  final WorkoutExercises exercise;
  final DateTime selectedDate;

  /// Opened from a session that isn't active and hasn't been unlocked.
  ///
  /// You can still read everything — the chart and the sets are the point of
  /// looking at history — but nothing here may change it. Without this the lock
  /// on the home card would be cosmetic: you'd just tap through and edit anyway.
  final bool readOnly;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
    required this.selectedDate,
    this.readOnly = false,
  });

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();
  late final TextEditingController _noteCtrl;

  List<ExerciseSets> _sets = [];
  List<WeightPoint> _history = [];
  bool _isLoading = true;
  bool _isSaving = false;

  /// The last set logged for this lift in an earlier session. Only used to seed
  /// the fields before you've logged anything today.
  ExerciseSets? _lastTime;

  /// The set being edited, or null when logging a new one.
  ExerciseSets? _editing;

  /// Set to true by any change that the previous screen needs to see.
  bool _dirty = false;

  /// Machines you could be on for this lift. Empty unless you've registered
  /// any, which most people never will — the strip renders nothing then.
  List<UserMachine> _machines = [];

  /// The station this exercise is recorded against. Null means unspecified,
  /// which is the honest default rather than a missing value to be filled.
  String? _machineId;

  /// How the selected machine is set up for this exercise — seat 4, back pad 2.
  MachineExerciseSettings? _machineSettings;

  String get _exerciseId => widget.exercise.exerciseId ?? '';

  String? get _catalogId => widget.exercise.catalogId;

  bool get _hasMachines =>
      exerciseHasMachines(widget.exercise.catalogDetail?.equipment);

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController(text: widget.exercise.notes ?? '');
    _load();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final sets = await WorkoutService.getExerciseSets(_exerciseId);
      final catalogId = widget.exercise.catalogId;

      final history = catalogId == null
          ? <WeightPoint>[]
          : await WorkoutService.getExerciseHistory(catalogId);

      // Only worth asking when today is still empty — otherwise today's own
      // last set is the better default anyway.
      final lastTime = (sets.isEmpty && catalogId != null)
          ? await WorkoutService.getLastSetForExercise(catalogId)
          : null;

      if (mounted) {
        setState(() {
          _sets = sets;
          _history = history;
          _lastTime = lastTime;
        });
        _prefill();
      }

      await _loadMachines();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Loads the stations you could be on, and the setup for the one you're on.
  ///
  /// Skipped entirely for barbells and bodyweight: a bench press has no seat
  /// height and no stack, so there is nothing here worth a round trip.
  Future<void> _loadMachines() async {
    final catalogId = _catalogId;
    if (!_hasMachines || catalogId == null) return;

    final machines = await MachineService.getCandidates(catalogId);
    var machineId = widget.exercise.machineId;

    // Exactly one registered station means there is no ambiguity to resolve —
    // you registered it because it's the one you use. Recording it silently is
    // what keeps the common case free of taps. With two or more, nothing is
    // chosen for you: which one you're on is decided by whichever was free, so
    // a guess would be wrong about half the time and would quietly corrupt the
    // history the whole feature depends on.
    if (machineId == null &&
        machines.length == 1 &&
        !widget.readOnly &&
        machines.first.machineId != null) {
      machineId = machines.first.machineId;
      await MachineService.assignMachine(_exerciseId, machineId);
      _dirty = true;
    }

    final settings = machineId == null
        ? null
        : await MachineService.getSettings(machineId, catalogId);

    if (!mounted) return;
    setState(() {
      _machines = machines;
      _machineId = machineId;
      _machineSettings = settings;
    });
  }

  Future<void> _selectMachine(String? machineId) async {
    final catalogId = _catalogId;
    if (catalogId == null) return;

    setState(() {
      _machineId = machineId;
      _machineSettings = null; // cleared until the new one's setup loads
    });

    try {
      await MachineService.assignMachine(_exerciseId, machineId);
      _dirty = true;

      final settings = machineId == null
          ? null
          : await MachineService.getSettings(machineId, catalogId);
      if (mounted) setState(() => _machineSettings = settings);
    } catch (e) {
      _toast('Could not record the machine: $e', error: true);
    }
  }

  /// Opens the editor for [machine], or for a new one when null.
  ///
  /// The inferred step is worked out first so the sheet can offer it as a fact
  /// to accept rather than a field to fill. For a machine that already exists
  /// the evidence is its own logged weights; for a new one it's this exercise's
  /// history, which is weaker — that history may be a blend of two stations.
  Future<void> _editMachine(UserMachine? machine) async {
    final catalogId = _catalogId;
    if (catalogId == null) return;

    final machineId = machine?.machineId;
    final inferred = machineId == null
        ? await MachineService.inferIncrementForExercise(catalogId)
        : await MachineService.inferIncrementFor(machineId);

    if (!mounted) return;
    final saved = await showMachineEditor(
      context,
      catalogId: catalogId,
      machine: machine,
      inferredIncrement: inferred,
    );

    if (!saved || !mounted) return;

    // A machine that was just deleted must not stay selected.
    if (machineId != null && _machineId == machineId) {
      final still = await MachineService.getMachines();
      if (!still.any((m) => m.machineId == machineId)) {
        await _selectMachine(null);
      }
    }

    _dirty = true;
    await _loadMachines();
  }

  /// Carries the last set forward into the input fields, so a working set of
  /// 5×5 is four taps of Save rather than four rounds of retyping.
  ///
  /// Today's most recent set wins; failing that, the last time you did this
  /// lift at all. Never overwrites what you've already typed, and never fights
  /// an edit in progress.
  void _prefill() {
    // Nothing to prefill when there's no input to prefill into.
    if (widget.readOnly) return;
    if (_editing != null) return;
    if (_weightCtrl.text.isNotEmpty || _repsCtrl.text.isNotEmpty) return;

    final source = _sets.isNotEmpty ? _sets.last : _lastTime;
    if (source == null) return;

    setState(() {
      _weightCtrl.text = _trim(source.weightKg ?? 0);
      _repsCtrl.text = '${source.reps ?? 0}';
    });
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? LiftrColors.danger : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Sets ────────────────────────────────────────────────────

  Future<void> _saveSet() async {
    final weight = double.tryParse(_weightCtrl.text.trim());
    final reps = int.tryParse(_repsCtrl.text.trim());

    if (weight == null || reps == null || reps <= 0) {
      _toast('Enter a weight and a rep count', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final editing = _editing;
      if (editing?.setId != null) {
        await WorkoutService.updateExerciseSet(editing!.setId!, weight, reps);
      } else {
        await WorkoutService.addSet(_exerciseId, weight, reps);
      }

      _weightCtrl.clear();
      _repsCtrl.clear();
      _dirty = true;
      setState(() => _editing = null);
      await _load();
    } catch (e) {
      _toast('Could not save the set: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _editSet(ExerciseSets s) {
    setState(() {
      _editing = s;
      _weightCtrl.text = s.weightKg?.toString() ?? '';
      _repsCtrl.text = s.reps?.toString() ?? '';
    });
  }

  Future<void> _deleteSet(ExerciseSets s) async {
    if (s.setId == null) return;
    try {
      await WorkoutService.deleteExerciseSet(s.setId!, _exerciseId);
      _dirty = true;
      if (_editing?.setId == s.setId) {
        _weightCtrl.clear();
        _repsCtrl.clear();
        setState(() => _editing = null);
      }
      await _load();
    } catch (e) {
      _toast('Could not delete the set: $e', error: true);
    }
  }

  // ── Exercise ────────────────────────────────────────────────

  Future<void> _saveNotes() async {
    final text = _noteCtrl.text.trim();
    try {
      await WorkoutService.updateExerciseNotes(
          _exerciseId, text.isEmpty ? null : text);
      _dirty = true;
      _toast('Note saved');
    } catch (e) {
      _toast('Could not save the note: $e', error: true);
    }
  }

  Future<void> _deleteExercise() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'Delete exercise?',
        message:
            '${widget.exercise.name} and its ${_sets.length} logged set${_sets.length == 1 ? '' : 's'} '
            'will be removed from this workout.',
      ),
    );
    if (confirmed != true) return;

    try {
      await WorkoutService.deleteWorkoutExercise(_exerciseId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('Could not delete: $e', error: true);
    }
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    // The back arrow and the system back gesture must both report whether
    // anything changed, or the home screen shows stale sets.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _dirty);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _header(lt),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: LiftrColors.accent,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    children: [
                      // Above the chart because it says which station the
                      // numbers below it belong to. Renders nothing at all for
                      // barbell and bodyweight work, or before you've
                      // registered a machine.
                      if (_hasMachines) ...[
                        MachineStrip(
                          candidates: _machines,
                          selectedId: _machineId,
                          settings: _machineSettings,
                          readOnly: widget.readOnly,
                          onSelect: _selectMachine,
                          onAdd: () => _editMachine(null),
                          onEdit: _editMachine,
                        ),
                        const SizedBox(height: LiftrSpacing.x10),
                      ],
                      _chartCard(lt),
                      const SizedBox(height: LiftrSpacing.x14),
                      _notesCard(lt),
                      const SizedBox(height: LiftrSpacing.x16),
                      _setsHeader(lt),
                      const SizedBox(height: LiftrSpacing.x10),
                      if (_isLoading)
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: LiftrSpacing.x24),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: LiftrColors.accent,
                              ),
                            ),
                          ),
                        )
                      else if (_sets.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: LiftrSpacing.x14),
                          child: Text(
                            widget.readOnly
                                ? 'No sets were logged for this exercise.'
                                : 'No sets yet. Log your first one below.',
                            style: TextStyle(
                                fontSize: LiftrType.x13, color: lt.textDim),
                          ),
                        )
                      else
                        ..._sets.map((s) => _setRow(lt, s)),

                      // The whole logging surface, gone when read-only — there's
                      // nothing to type into a session you're only looking at.
                      if (!widget.readOnly) ...[
                        const SizedBox(height: LiftrSpacing.x4),
                        _weightInput(lt),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(LiftrTheme lt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context, _dirty),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: lt.card,
                border:
                    Border.all(color: lt.border, width: LiftrBorders.hairline),
                borderRadius: BorderRadius.circular(LiftrRadii.control),
              ),
              child:
                  Icon(Icons.chevron_left, size: 20, color: lt.textSecondary),
            ),
          ),
          const SizedBox(width: LiftrSpacing.x10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.exercise.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                if (_subtitle.isNotEmpty)
                  Text(
                    _subtitle,
                    style:
                        TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
                  ),
              ],
            ),
          ),
          if (widget.readOnly)
            // Says why the controls are missing, rather than leaving them
            // mysteriously absent. Same metrics as the chips on the home card.
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: LiftrSpacing.x10, vertical: LiftrSpacing.x4),
              decoration: BoxDecoration(
                color: lt.card,
                border:
                    Border.all(color: lt.border, width: LiftrBorders.hairline),
                borderRadius: BorderRadius.circular(LiftrRadii.panel),
              ),
              child: Text(
                'READ ONLY',
                style: TextStyle(
                  fontSize: LiftrType.x10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.06,
                  color: lt.textSecondary,
                ),
              ),
            )
          else
            ThreeDotMenu(
              onEdit: _saveNotes,
              onDelete: _deleteExercise,
            ),
        ],
      ),
    );
  }

  String get _subtitle {
    final d = widget.exercise.catalogDetail;
    return detailLine([d?.equipment, d?.muscleGroup]);
  }

  Widget _chartCard(LiftrTheme lt) {
    final best = _history.isEmpty
        ? null
        : _history.map((p) => p.topWeight).reduce((a, b) => a > b ? a : b);

    // Up only when the last session actually beat the one before it.
    final improving = _history.length >= 2 &&
        _history.last.topWeight > _history[_history.length - 2].topWeight;

    return Container(
      decoration: BoxDecoration(
        color: lt.surface,
        border:
            Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.cardLarge),
      ),
      padding: const EdgeInsets.all(LiftrSpacing.x14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Weight progress',
                style: TextStyle(
                  fontSize: LiftrType.x12,
                  fontWeight: FontWeight.w500,
                  color: lt.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                best == null
                    ? '—'
                    : '${_trim(best)} kg${improving ? ' ↑' : ''}',
                style: const TextStyle(
                  fontSize: LiftrType.x16,
                  fontWeight: FontWeight.w600,
                  color: LiftrColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: LiftrSpacing.x12),
          SizedBox(
            height: 100,
            child: _history.length < 2
                ? Center(
                    child: Text(
                      _history.isEmpty
                          ? 'Log a set to start tracking this lift.'
                          : 'One session logged. The trend appears after the next one.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: LiftrType.x12, color: lt.textDim),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 100),
                    painter: _ChartPainter(
                      data: _history.map((p) => p.topWeight).toList(),
                      labels: _history.map((p) => _shortDate(p.date)).toList(),
                      accentColor: LiftrColors.accent,
                      gridColor: lt.borderSubtle,
                      labelColor: lt.textDim,
                      isDark: context.isDark,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _notesCard(LiftrTheme lt) {
    return Container(
      decoration: BoxDecoration(
        color: lt.card,
        border: Border.all(color: lt.border, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.field),
      ),
      child: TextField(
        controller: _noteCtrl,
        maxLines: 2,
        readOnly: widget.readOnly,
        // Persist on blur: typing a note and walking away used to silently
        // discard it, because the field had no controller at all.
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          if (widget.readOnly) return;
          if (_noteCtrl.text.trim() != (widget.exercise.notes ?? '').trim()) {
            _saveNotes();
          }
        },
        onSubmitted: widget.readOnly ? null : (_) => _saveNotes(),
        style: TextStyle(
          fontSize: LiftrType.x13,
          color: widget.readOnly ? lt.textSecondary : lt.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: widget.readOnly
              ? 'No note for this exercise'
              : 'Add a note for this exercise…',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x12),
          fillColor: Colors.transparent,
        ),
      ),
    );
  }

  Widget _setsHeader(LiftrTheme lt) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final d = widget.selectedDate;
    final volume = _sets.fold<double>(0, (sum, s) => sum + s.volume);

    return Row(
      children: [
        Text(
          'SETS · ${months[d.month - 1]} ${d.day}',
          style: TextStyle(
            fontSize: LiftrType.x11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.08,
            color: lt.textMuted,
          ),
        ),
        const Spacer(),
        if (volume > 0)
          Text(
            '${_trim(volume)} kg volume',
            style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
          ),
      ],
    );
  }

  Widget _setRow(LiftrTheme lt, ExerciseSets s) {
    final isEditing = _editing?.setId != null && _editing!.setId == s.setId;

    // Read-only: no swipe-to-delete and no tap-to-edit. Wrapping in Dismissible
    // at all would leave the swipe live even with the handler stubbed out.
    if (widget.readOnly) {
      return Padding(
        padding: const EdgeInsets.only(bottom: LiftrSpacing.x8),
        child: _setRowBody(lt, s, isEditing: false),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(s.setId),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => _deleteSet(s),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: LiftrColors.danger.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(LiftrRadii.field),
          ),
          child: const Icon(Icons.delete_outline,
              size: 18, color: LiftrColors.danger),
        ),
        child: GestureDetector(
          onTap: () => _editSet(s),
          child: _setRowBody(lt, s, isEditing: isEditing),
        ),
      ),
    );
  }

  Widget _setRowBody(LiftrTheme lt, ExerciseSets s, {required bool isEditing}) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x10),
      decoration: BoxDecoration(
        color: isEditing ? lt.accentBg : lt.surface,
        border: Border.all(
          color: isEditing ? LiftrColors.accent : lt.borderSubtle,
          width: isEditing ? LiftrBorders.thin : LiftrBorders.hairline,
        ),
        borderRadius: BorderRadius.circular(LiftrRadii.field),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              'S${s.setNumber ?? 0}',
              style: TextStyle(
                fontSize: LiftrType.x11,
                fontWeight: FontWeight.w600,
                color: isEditing ? lt.accentMid : lt.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${s.reps ?? 0} reps · ${_trim(s.weightKg ?? 0)} kg',
              style: TextStyle(fontSize: LiftrType.x13, color: lt.textPrimary),
            ),
          ),
          Text(
            isEditing ? 'Editing' : '${_trim(s.volume)} kg',
            style: TextStyle(
              fontSize: LiftrType.x11,
              fontWeight: FontWeight.w500,
              color: isEditing ? lt.accentMid : lt.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightInput(LiftrTheme lt) {
    final editing = _editing != null;

    return Container(
      padding: const EdgeInsets.all(LiftrSpacing.x14),
      decoration: BoxDecoration(
        color: lt.accentBg,
        border: Border.all(color: LiftrColors.accent, width: LiftrBorders.thin),
        borderRadius: BorderRadius.circular(LiftrRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                editing
                    ? 'EDITING SET ${_editing!.setNumber ?? 0}'
                    : 'SET ${_sets.length + 1} · LOG WEIGHT',
                style: TextStyle(
                  fontSize: LiftrType.x11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.08,
                  color: lt.textMuted,
                ),
              ),
              const Spacer(),
              if (editing)
                GestureDetector(
                  onTap: () {
                    _weightCtrl.clear();
                    _repsCtrl.clear();
                    setState(() => _editing = null);
                    _prefill(); // back to logging a new set, seeded again
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                        fontSize: LiftrType.x11, color: lt.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: LiftrSpacing.x8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: lt.card,
                    border: Border.all(
                        color: lt.border, width: LiftrBorders.hairline),
                    borderRadius: BorderRadius.circular(LiftrRadii.control),
                  ),
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: LiftrType.x20,
                      fontWeight: FontWeight.w600,
                      color: LiftrColors.accent,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle:
                          TextStyle(fontSize: LiftrType.x20, color: lt.textDim),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: LiftrSpacing.x10),
                      fillColor: Colors.transparent,
                    ),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: LiftrSpacing.x6),
                child: Text(
                  'kg',
                  style: TextStyle(
                    fontSize: LiftrType.x13,
                    color: lt.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Column(
                children: [
                  Text('Reps',
                      style: TextStyle(
                          fontSize: LiftrType.x11, color: lt.textMuted)),
                  const SizedBox(height: LiftrSpacing.x4),
                  Container(
                    width: 56,
                    decoration: BoxDecoration(
                      color: lt.card,
                      border: Border.all(
                          color: lt.border, width: LiftrBorders.hairline),
                      borderRadius: BorderRadius.circular(LiftrRadii.control),
                    ),
                    child: TextField(
                      controller: _repsCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _saveSet(),
                      style: TextStyle(
                        fontSize: LiftrType.x16,
                        fontWeight: FontWeight.w600,
                        color: lt.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(
                            fontSize: LiftrType.x16, color: lt.textDim),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: LiftrSpacing.x10),
                        fillColor: Colors.transparent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: LiftrSpacing.x8),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveSet,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(64, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: LiftrSpacing.x16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(LiftrRadii.control)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: LiftrColors.accentText,
                        ),
                      )
                    : Text(editing ? 'Update' : 'Save',
                        style: const TextStyle(fontSize: LiftrType.x13)),
              ),
            ],
          ),
          const SizedBox(height: LiftrSpacing.x6),
          Text(
            _hint,
            style: TextStyle(fontSize: LiftrType.x10, color: lt.textDim),
          ),
        ],
      ),
    );
  }

  /// Says where a prefilled number came from, so a value you didn't type never
  /// looks like one you did.
  String get _hint {
    if (_editing != null) return 'Editing an existing set';

    if (_sets.isNotEmpty) {
      return 'Prefilled from set ${_sets.last.setNumber ?? _sets.length} · '
          'tap a set to edit, swipe left to delete';
    }

    final last = _lastTime;
    if (last != null) {
      final when =
          last.loggedAt == null ? '' : ' (${_shortDate(last.loggedAt!)})';
      return 'Last time$when: ${_trim(last.weightKg ?? 0)} kg × ${last.reps ?? 0}';
    }

    return 'Tap a set to edit · swipe left to delete';
  }

  /// 72.5 stays 72.5; 70.0 shows as 70.
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static String _shortDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

// ── Confirm dialog ────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  const _ConfirmDialog({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return AlertDialog(
      backgroundColor: lt.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LiftrRadii.card)),
      title: Text(title,
          style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary)),
      content: Text(message,
          style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: lt.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child:
              const Text('Delete', style: TextStyle(color: LiftrColors.danger)),
        ),
      ],
    );
  }
}

// ── Line Chart Painter ────────────────────────────────────────
class _ChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color accentColor;
  final Color gridColor;
  final Color labelColor;
  final bool isDark;

  const _ChartPainter({
    required this.data,
    required this.labels,
    required this.accentColor,
    required this.gridColor,
    required this.labelColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Guarded because x() divides by data.length - 1.
    if (data.length < 2) return;

    final minVal = data.reduce((a, b) => a < b ? a : b);
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);

    final chartH = size.height - 18; // leave room for labels
    const padX = 8.0;
    final usableW = size.width - padX * 2;

    double x(int i) => padX + (i / (data.length - 1)) * usableW;
    double y(double v) => chartH - ((v - minVal) / range) * (chartH - 12) - 4;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 0; i < 3; i++) {
      final yy = 8.0 + (chartH - 12) * i / 2;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), gridPaint);
    }

    final path = Path()..moveTo(x(0), y(data[0]));
    for (var i = 1; i < data.length; i++) {
      final cp1x = x(i - 1) + (x(i) - x(i - 1)) * 0.5;
      path.cubicTo(cp1x, y(data[i - 1]), cp1x, y(data[i]), x(i), y(data[i]));
    }
    path.lineTo(x(data.length - 1), chartH);
    path.lineTo(x(0), chartH);
    path.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withValues(alpha: 0.3),
          accentColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartH));
    canvas.drawPath(path, fillPaint);

    final linePath = Path()..moveTo(x(0), y(data[0]));
    for (var i = 1; i < data.length; i++) {
      final cp1x = x(i - 1) + (x(i) - x(i - 1)) * 0.5;
      linePath.cubicTo(
          cp1x, y(data[i - 1]), cp1x, y(data[i]), x(i), y(data[i]));
    }
    final linePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = accentColor;
    final holePaint = Paint()
      ..color = isDark ? LiftrColors.darkSurface : Colors.white;
    for (var i = 0; i < data.length; i++) {
      canvas.drawCircle(
          Offset(x(i), y(data[i])), i == data.length - 1 ? 4.5 : 3, dotPaint);
      if (i == data.length - 1) {
        canvas.drawCircle(Offset(x(i), y(data[i])), 2.5, holePaint);
      }
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, Offset pos, TextAlign align) {
      tp.text = TextSpan(
        text: text,
        style: TextStyle(
            fontSize: LiftrType.x9, color: labelColor, fontFamily: 'DMSans'),
      );
      tp.textAlign = align;
      tp.layout();
      final dx = align == TextAlign.right ? pos.dx - tp.width : pos.dx;
      tp.paint(canvas, Offset(dx, pos.dy));
    }

    drawLabel(labels.first, Offset(x(0) - 2, chartH + 4), TextAlign.left);
    drawLabel(labels.last, Offset(x(data.length - 1) + 2, chartH + 4),
        TextAlign.right);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.data != data || old.isDark != isDark;
}
