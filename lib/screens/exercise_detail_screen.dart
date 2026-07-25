import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/exercise_setup_service.dart';
import '../services/progression_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../utils/progression.dart';
import 'exercise_setup_sheet.dart';

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

  /// How this exercise's station is set up — seat 4, back pad 2, moves in 5s.
  ///
  /// A list because a movement can have more than one: the 5 kg cable stack and
  /// the 2.5 kg one. Empty unless you've entered something, which most exercises
  /// never will.
  List<ExerciseSetup> _setups = [];

  /// Which setup today's sets are recorded against. Null means you haven't
  /// said, which is the honest default and never filled in for you.
  String? _selectedSetupId;

  /// The rule-based hint for what to aim for, built from earlier sessions.
  /// Null until loaded, when there's no history to build one from, or in
  /// read-only mode where planning the next set makes no sense.
  ProgressionHint? _progression;

  String get _exerciseId => widget.exercise.exerciseId ?? '';

  String? get _catalogId => widget.exercise.catalogId;

  /// Barbell, dumbbell, cable, machine — what decides which stations this lift
  /// can be done on, and whether it can have a setup at all.
  String? get _equipment => widget.exercise.catalogDetail?.equipment;

  bool get _hasSetup => exerciseHasSetup(_equipment);

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController(text: widget.exercise.notes ?? '');
    // What the session already says, including on a workout from weeks ago.
    _selectedSetupId = widget.exercise.setupId;
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

      await _loadSetup();
      await _loadHint();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Loads the progression hint. Read-only skips it — a session you're only
  /// inspecting isn't one you're about to add a set to — and it fails soft, so
  /// a missing hint never disturbs the rest of the screen.
  Future<void> _loadHint() async {
    final detail = widget.exercise.catalogDetail;
    if (widget.readOnly || detail == null) return;

    final hint = await ProgressionService.hintFor(detail);
    if (!mounted) return;
    setState(() => _progression = hint);
  }

  /// Loads how this exercise's station is set up.
  ///
  /// Skipped entirely for barbells and bodyweight: a bench press has no seat
  /// height and no stack, so there is nothing here worth a round trip.
  Future<void> _loadSetup() async {
    final catalogId = _catalogId;
    if (!_hasSetup || catalogId == null) return;

    final setups = await ExerciseSetupService.getSetups(
      catalogId: catalogId,
      equipment: _equipment,
    );
    if (!mounted) return;
    setState(() {
      _setups = setups;
      // A setup that was removed must not stay selected on screen. The database
      // has already cleared the column for us — 017's foreign key is ON DELETE
      // SET NULL — so this is only keeping the UI honest about it.
      if (!setups.any((s) => s.setupId == _selectedSetupId)) {
        _selectedSetupId = null;
      }
    });
  }

  /// Records which stack today's sets were done on, or clears it.
  ///
  /// Written on the tap, not on save: the point is that the sets you're about
  /// to log belong to this setup, so it has to be true before they exist.
  Future<void> _selectSetup(String? setupId) async {
    final previous = _selectedSetupId;
    setState(() => _selectedSetupId = setupId);

    try {
      await ExerciseSetupService.assignSetup(_exerciseId, setupId);
      _dirty = true;
    } catch (e) {
      // Put the chip back rather than leaving the screen claiming something the
      // database doesn't say.
      if (mounted) setState(() => _selectedSetupId = previous);
      _toast('Could not record the setup: $e', error: true);
    }
  }

  /// Opens the setup sheet — on [setup] to edit it, or with null for a new one.
  ///
  /// The inferred step is offered as a fact to accept rather than a field to
  /// fill, but only while this is the exercise's first setup. Once a second
  /// exists, the logged weights are known to be a blend of two stacks, so the
  /// inference over them can be finer than either machine can actually load —
  /// and a suggestion you can't pin is worse than no suggestion. That's the same
  /// hazard `looksLikeTwoMachines` was written to detect, except here you've
  /// told the app outright instead of it having to guess.
  Future<void> _editSetup(ExerciseSetup? setup) async {
    final catalogId = _catalogId;
    if (catalogId == null) return;

    final firstSetup = _setups.isEmpty;
    final inferred = firstSetup
        ? await ExerciseSetupService.inferIncrementFor(catalogId)
        : null;

    if (!mounted) return;
    final saved = await showExerciseSetupEditor(
      context,
      catalogId: catalogId,
      equipment: _equipment,
      setup: setup,
      inferredIncrement: inferred,
    );

    if (!saved || !mounted) return;
    await _loadSetup();
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
                      // Above the chart because it says how the station the
                      // numbers came from was arranged. Renders nothing at all
                      // for barbell and bodyweight work.
                      if (_hasSetup) ...[
                        ExerciseSetupLine(
                          setups: _setups,
                          selectedId: _selectedSetupId,
                          readOnly: widget.readOnly,
                          onSelect: _selectSetup,
                          onEdit: _editSetup,
                          onAdd: () => _editSetup(null),
                        ),
                        const SizedBox(height: LiftrSpacing.x10),
                      ],
                      _chartCard(lt),
                      // The suggestion sits under the chart: the graph is what
                      // happened, this is what to do next. Only when there's a
                      // suggestion to make.
                      const SizedBox(height: LiftrSpacing.x14),
                      _notesCard(lt),
                      if (_progression?.suggestion != null) ...[
                        const SizedBox(height: LiftrSpacing.x14),
                        _suggestionCard(lt, _progression!),
                      ],
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
                style: TextStyle(
                  fontSize: LiftrType.x16,
                  fontWeight: FontWeight.w600,
                  color: lt.accentStrong,
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
                      labels: _history.map((p) => shortDate(p.date)).toList(),
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

  /// The hint card: what to aim for next, why, and what last time looked like.
  Widget _suggestionCard(LiftrTheme lt, ProgressionHint hint) {
    final s = hint.suggestion!;
    final note = _incrementNote(hint.increment);

    return Container(
      decoration: BoxDecoration(
        color: lt.accentBg,
        border: Border.all(color: LiftrColors.accent, width: LiftrBorders.thin),
        borderRadius: BorderRadius.circular(LiftrRadii.cardLarge),
      ),
      padding: const EdgeInsets.all(LiftrSpacing.x14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Suggestion',
                style: TextStyle(
                  fontSize: LiftrType.x12,
                  fontWeight: FontWeight.w500,
                  color: lt.accentMid,
                ),
              ),
              const Spacer(),
              Text(
                _target(s),
                style: TextStyle(
                  fontSize: LiftrType.x16,
                  fontWeight: FontWeight.w600,
                  color: lt.accentStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: LiftrSpacing.x8),
          Text(
            _reasonText(s.reason),
            style: TextStyle(fontSize: LiftrType.x12, color: lt.textPrimary),
          ),
          const SizedBox(height: LiftrSpacing.x8),
          Text(
            'Last time: ${_lastSummary(hint.lastSession)}',
            style: TextStyle(fontSize: LiftrType.x11, color: lt.textDim),
          ),
          if (note != null) ...[
            const SizedBox(height: LiftrSpacing.x8),
            _footnote(lt, Icons.tune, note),
          ],
          if (hint.plateau) ...[
            const SizedBox(height: LiftrSpacing.x6),
            _footnote(
              lt,
              Icons.trending_flat,
              'Estimated strength has been flat — consider a deload week or a '
              'new rep range.',
            ),
          ],
        ],
      ),
    );
  }

  /// A small icon + muted line for the setup and plateau asides.
  Widget _footnote(LiftrTheme lt, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: lt.textMuted),
        const SizedBox(width: LiftrSpacing.x6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: LiftrType.x10, color: lt.textMuted),
          ),
        ),
      ],
    );
  }

  /// The right-hand target: a weight and rep window, or reps alone for
  /// bodyweight where there's no load to name.
  String _target(ProgressionSuggestion s) {
    final w = s.suggestedWeightKg;
    final r = s.targetReps;
    final reps = r.min == r.max ? '${r.min}' : '${r.min}–${r.max}';
    if (w == null) return '$reps reps';
    return '${_trim(w)} kg × $reps';
  }

  String _reasonText(ProgressionReason reason) {
    switch (reason) {
      case ProgressionReason.hitTopOfRange:
        return 'Hit the top of the range last time — time to add weight.';
      case ProgressionReason.withinRange:
        return 'In range last time — same weight, aim for one more rep.';
      case ProgressionReason.belowRange:
        return 'Fell short of the range last time — ease the weight down.';
      case ProgressionReason.bodyweightAddReps:
        return 'Bodyweight — aim for one or two more reps.';
      case ProgressionReason.confidentProgression:
        return 'Two strong sessions in a row — time to add weight.';
      case ProgressionReason.gatheringData:
        return 'Mixed last two sessions — hold the weight and settle it next '
            'time.';
      case ProgressionReason.confidentRegression:
        return 'Two sessions short of the range — drop the weight.';
      case ProgressionReason.returningDeload:
        return 'Coming back from a break — start a little lighter and build up.';
      case ProgressionReason.startingOver:
        return 'A long time off — treat this as starting the lift over.';
      case ProgressionReason.bigJumpHoldReps:
        return 'One step is a big jump at this weight — earn more reps here '
            'first.';
      case ProgressionReason.fatigueCollapse:
        return 'Reps fell off sharply last time — the first set was likely too '
            'heavy, so hold.';
    }
  }

  /// "40×12, 40×10, 40×7" — or reps alone for bodyweight sets.
  String _lastSummary(ExerciseSessionHistory h) {
    return h.sets
        .map((s) => s.weightKg == null
            ? '${s.reps ?? 0}'
            : '${_trim(s.weightKg!)}×${s.reps ?? 0}')
        .join(', ');
  }

  /// The "you can make this sharper" nudge, when the step was defaulted or
  /// ambiguous. Nothing for a confirmed setup or a bodyweight lift.
  String? _incrementNote(ResolvedIncrement increment) {
    if (increment.isAmbiguous) {
      return 'Sized with a default 2.5 kg step — pick which stack you used for '
          'a sharper number.';
    }
    if (increment.isDefaulted) {
      return 'Sized with a default 2.5 kg step — set this exercise up for a '
          'sharper number.';
    }
    return null;
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
    final d = widget.selectedDate;
    final volume = _sets.fold<double>(0, (sum, s) => sum + s.volume);

    return Row(
      children: [
        Text(
          'SETS · ${shortDateUpper(d)}',
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

  /// The step the weight field's − / + buttons move by: this exercise's
  /// resolved increment, or null for bodyweight (nothing to step) — which
  /// leaves the weight field a plain typed box.
  ///
  /// Comes from the same pure resolver the hint uses, over the setups already
  /// loaded, so it works before any history exists (defaulting to 2.5 kg).
  double? get _stepIncrement {
    final isBodyweight = (_equipment ?? '').toLowerCase().trim() == 'bodyweight';
    if (isBodyweight) return null;
    return resolveIncrement(
      setups: _setups,
      assignedSetupId: _selectedSetupId,
      isBodyweight: false,
    ).incrementKg;
  }

  /// Nudges [c]'s value by [delta], snapping to the [snap] grid first so a
  /// tap always lands on a loadable weight even if the typed number was off it.
  /// Floored at zero.
  void _step(TextEditingController c, double delta, double snap) {
    final current = double.tryParse(c.text.trim()) ?? 0;
    var next = roundToIncrement(current, snap) + delta;
    if (next < 0) next = 0;
    final text = _trim(next);
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Widget _stepButton(LiftrTheme lt, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isSaving ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x12, vertical: LiftrSpacing.x10),
        child: Icon(icon, size: 18, color: lt.textSecondary),
      ),
    );
  }

  /// A labelled number field — the same box for weight and reps, so the two
  /// read as one control rather than two mismatched inputs. Pass [step] to flank
  /// it with − / + buttons that move by that amount.
  Widget _numberField(
    LiftrTheme lt, {
    required String label,
    required TextEditingController controller,
    required bool decimal,
    double? step,
    ValueChanged<String>? onSubmitted,
  }) {
    final field = TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      textAlign: TextAlign.center,
      onSubmitted: onSubmitted,
      style: TextStyle(
        fontSize: LiftrType.x20,
        fontWeight: FontWeight.w600,
        color: lt.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: '0',
        // Dim, so an empty field never looks like a logged 0.
        hintStyle: TextStyle(fontSize: LiftrType.x20, color: lt.textDim),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: LiftrSpacing.x10),
        fillColor: Colors.transparent,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: LiftrType.x10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.06,
            color: lt.textMuted,
          ),
        ),
        const SizedBox(height: LiftrSpacing.x4),
        Container(
          decoration: BoxDecoration(
            color: lt.card,
            border: Border.all(color: lt.border, width: LiftrBorders.hairline),
            borderRadius: BorderRadius.circular(LiftrRadii.control),
          ),
          child: step == null
              ? field
              : Row(
                  children: [
                    _stepButton(lt, Icons.remove,
                        () => _step(controller, -step, step)),
                    Expanded(child: field),
                    _stepButton(
                        lt, Icons.add, () => _step(controller, step, step)),
                  ],
                ),
        ),
      ],
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
          const SizedBox(height: LiftrSpacing.x10),
          Row(
            // Bottom-aligned so the Save button lines up with the field boxes,
            // not with the labels sitting above them.
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Weight gets the wider share — it carries decimals like 142.5.
              Expanded(
                flex: 3,
                child: _numberField(
                  lt,
                  label: 'WEIGHT (KG)',
                  controller: _weightCtrl,
                  decimal: true,
                  step: _stepIncrement,
                ),
              ),
              const SizedBox(width: LiftrSpacing.x8),
              Expanded(
                flex: 2,
                child: _numberField(
                  lt,
                  label: 'REPS',
                  controller: _repsCtrl,
                  decimal: false,
                  onSubmitted: (_) => _saveSet(),
                ),
              ),
              const SizedBox(width: LiftrSpacing.x8),
              SizedBox(
                height: 46, // matches a field box, so the row bottoms align
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveSet,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(68, 46),
                    padding: const EdgeInsets.symmetric(
                        horizontal: LiftrSpacing.x16),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(LiftrRadii.control)),
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
              ),
            ],
          ),
          const SizedBox(height: LiftrSpacing.x8),
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
          last.loggedAt == null ? '' : ' (${shortDate(last.loggedAt!)})';
      return 'Last time$when: ${_trim(last.weightKg ?? 0)} kg × ${last.reps ?? 0}';
    }

    return 'Tap a set to edit · swipe left to delete';
  }

  /// 72.5 stays 72.5; 70.0 shows as 70.
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

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
