import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/exercise_setup_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Whether this exercise can carry a setup at all.
///
/// Everything except bodyweight. This used to be machine and cable only, back
/// when a setup meant a seat height — a barbell has nothing to adjust, so
/// offering it one was noise.
///
/// What changed is what a setup is *for*. Its weight step is the number that
/// lets the app suggest "try 62.5 kg" rather than "go up", and a barbell has a
/// step as surely as a stack does: the smallest pair of plates you own. Gating
/// on machinery would leave the suggestion number-less on exactly the lifts
/// where progression is most deliberate.
///
/// Bodyweight is the one real exclusion — no weight, so nothing to step.
/// Unknown equipment is included: it may well be loaded, and the cost of
/// offering a setup nobody wants is a chip they never tap.
bool exerciseHasSetup(String? equipment) {
  return equipment?.toLowerCase().trim() != 'bodyweight';
}

/// The setup line under the exercise title.
///
/// Renders as little as it can get away with, because the whole feature is
/// optional and must never look like a form to fill in:
///
///   none entered → just "+ Set up"
///   one or more  → one chip per setup, then "+ Add"
///
/// One chip per *setup*, not per value. An exercise can hold more than one — the
/// 5 kg cable stack and the 2.5 kg one, both used for the same movement
/// depending on which is free — and each carries its own step and its own seat
/// height. Collapsing them into one chip per value would merge two stations back
/// into one reading, which is the thing the whole model exists to keep apart.
///
/// The "+" is present at every count, including one. A chip that merely *opened*
/// the editor read as a label, so after saving a weight step there was nothing
/// on screen suggesting a second stack could be recorded at all — and a route
/// you have to guess at is not a route.
///
/// Tapping a chip records that this is the stack you're on today; tapping it
/// again clears that. Editing is a long press, because you pick a stack every
/// session and rename one about once.
///
/// Nothing is ever selected for you, at any count — not even when there's only
/// one it could be. That inference is precisely what migration 017's column
/// exists to avoid repeating.
class ExerciseSetupLine extends StatelessWidget {
  final List<ExerciseSetup> setups;

  /// The setup this workout is recorded against, or null for "not said".
  final String? selectedId;

  final bool readOnly;

  /// Records (or clears) which setup today's sets were done on.
  final ValueChanged<String?> onSelect;

  /// Opens an existing setup for editing.
  final ValueChanged<ExerciseSetup> onEdit;

  /// Opens an empty sheet — a new setup, never a correction to an existing one.
  final VoidCallback onAdd;

  const ExerciseSetupLine({
    super.key,
    required this.setups,
    required this.selectedId,
    required this.readOnly,
    required this.onSelect,
    required this.onEdit,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to show and no way to add it: render nothing rather than a chip
    // that says "not set up" on a workout you're only looking at.
    if (setups.isEmpty && readOnly) return const SizedBox.shrink();

    return SizedBox(
      // One line that scrolls sideways, never a block that grows downwards —
      // same shape and height as the machine strip this replaced, so a second
      // stack can't shove the chart down the screen.
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final s in setups) ...[
            _chip(
              context,
              label: _label(s),
              filled: selectedId != null && s.setupId == selectedId,
              // Tapping the selected chip clears it — the way back out of a
              // mis-tap without inventing a "no setup" option.
              onTap: readOnly
                  ? null
                  : () => onSelect(s.setupId == selectedId ? null : s.setupId),
              onLongPress: readOnly ? null : () => onEdit(s),
            ),
            const SizedBox(width: LiftrSpacing.x6),
          ],
          if (!readOnly)
            _chip(
              context,
              label: setups.isEmpty ? '+ Set up' : '+ Add',
              filled: false,
              onTap: onAdd,
            ),
        ],
      ),
    );
  }

  /// What one setup's chip says.
  ///
  /// The name if you gave it one — that's the whole point of naming it, and it's
  /// what tells two stacks apart at a glance. Otherwise the values themselves,
  /// which is the common case: with a single setup there is nothing to
  /// distinguish, so being made to name it would be a field to fill for no
  /// answer.
  String _label(ExerciseSetup s) {
    final name = s.label?.trim();
    if (name != null && name.isNotEmpty) return name;

    final parts = <String>[
      if (s.weightIncrementKg != null)
        '${trimWeight(s.weightIncrementKg!)} kg steps',
      if (s.settings.isNotEmpty) s.settingsSummary,
    ];
    return parts.isEmpty ? 'Setup' : parts.join(' · ');
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool filled,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final lt = context.lt;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // Padding, not `alignment`, is what makes this ~30 high rather than the
        // ~19 the text alone gives — it's a control you tap mid-set with clumsy
        // hands, not a label. An alignment would also stretch it to fill the
        // line the moment this widget sits anywhere width-bounded.
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x10, vertical: LiftrSpacing.x8),
        decoration: BoxDecoration(
          color: filled ? lt.accentBg : lt.card,
          border: Border.all(
            color: filled ? LiftrColors.accent : lt.border,
            width: filled ? LiftrBorders.thin : LiftrBorders.hairline,
          ),
          borderRadius: BorderRadius.circular(LiftrRadii.panel),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: LiftrType.x11,
            fontWeight: filled ? FontWeight.w500 : FontWeight.w400,
            // textMuted, never textDim, even for the quiet "add" affordance:
            // textDim on the dark card is about 1.6:1 contrast, which is not
            // subtle, it's invisible. Quiet has to stay legible.
            color: filled ? lt.accentTextColor : lt.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Creates a setup, or edits [setup] when one is passed.
///
/// A null [setup] means a new one — a second stack, not a correction to the
/// first. That distinction is the entire difference between "+ Add" and tapping
/// a chip, so it's carried explicitly rather than inferred from whether any
/// fields happen to be filled.
///
/// Returns true if anything was saved or removed, so the caller knows to reload.
Future<bool> showExerciseSetupEditor(
  BuildContext context, {
  required String catalogId,
  required String? equipment,
  ExerciseSetup? setup,
  double? inferredIncrement,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SetupEditorSheet(
      catalogId: catalogId,
      equipment: equipment,
      setup: setup,
      inferredIncrement: inferredIncrement,
    ),
  );
  return saved ?? false;
}

class _SetupEditorSheet extends StatefulWidget {
  final String catalogId;
  final String? equipment;
  final ExerciseSetup? setup;
  final double? inferredIncrement;

  const _SetupEditorSheet({
    required this.catalogId,
    required this.equipment,
    this.setup,
    this.inferredIncrement,
  });

  @override
  State<_SetupEditorSheet> createState() => _SetupEditorSheetState();
}

class _SetupEditorSheetState extends State<_SetupEditorSheet> {
  final _incrementCtrl = TextEditingController();

  final _labelCtrl = TextEditingController();

  /// Setup rows as parallel controllers rather than a Map, because a Map keyed
  /// on the field you're editing loses the row the moment the key is blank.
  final _keyCtrls = <TextEditingController>[];
  final _valueCtrls = <TextEditingController>[];

  bool _isSaving = false;

  bool get _hasExisting => widget.setup?.setupId != null;

  /// Whether this station is one of many like it, and so belongs to the one
  /// exercise rather than to all of them.
  ///
  /// A gym has one dumbbell rack and one plate set, so their step is entered
  /// once and serves every lift that uses them. It has two cable stacks, still
  /// shared across every cable movement. But it has a dozen machines, and an
  /// unpinned machine would put a dozen chips on every machine exercise.
  ///
  /// Decided from the equipment rather than asked: "is this station one of many
  /// like it" is a fact about the gym, not a preference.
  bool get _pinToExercise =>
      widget.equipment?.toLowerCase().trim() == 'machine';

  /// "cable", "dumbbell" — for the line saying what this step is shared with.
  /// Falls back to a word that's true of anything rather than an empty gap.
  String get _equipmentWord {
    final e = widget.equipment?.toLowerCase().trim();
    return (e == null || e.isEmpty) ? 'other' : e;
  }

  /// The step is the one thing a setup must carry.
  ///
  /// Everything else here is a convenience — a seat height saves you working it
  /// out again, and a name only matters once there are two. The step is what the
  /// app *reads*: it's the difference between "go up" and "try 62.5 kg". A setup
  /// without one is a row that can never do the job the row exists for, so Save
  /// stays off rather than accepting it and disappointing you later.
  double? get _step {
    final v = double.tryParse(_incrementCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  @override
  void initState() {
    super.initState();

    // Save's enabled state is a function of this field, so it has to rebuild as
    // you type — otherwise the button stays dead until something else redraws.
    _incrementCtrl.addListener(_onStepChanged);

    // No load: the caller already has the setup, so the sheet opens filled
    // rather than opening empty and filling itself a frame later. A new setup
    // opens genuinely empty — none of the existing one's values follow it in.
    final existing = widget.setup;
    _labelCtrl.text = existing?.label ?? '';

    final inc = existing?.weightIncrementKg;
    if (inc != null) _incrementCtrl.text = trimWeight(inc);

    for (final e in existing?.settings.entries ?? <MapEntry<String, String>>[]) {
      _keyCtrls.add(TextEditingController(text: e.key));
      _valueCtrls.add(TextEditingController(text: e.value));
    }

    // Always somewhere to type on arrival.
    if (_keyCtrls.isEmpty) _addRow();
  }

  void _onStepChanged() => setState(() {});

  void _addRow() {
    _keyCtrls.add(TextEditingController());
    _valueCtrls.add(TextEditingController());
  }

  @override
  void dispose() {
    _incrementCtrl.removeListener(_onStepChanged);
    _labelCtrl.dispose();
    _incrementCtrl.dispose();
    for (final c in _keyCtrls) {
      c.dispose();
    }
    for (final c in _valueCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    // Unreachable while Save is disabled without one, but the guard stays: this
    // is the invariant the whole row exists for, not a UI detail.
    final step = _step;
    if (step == null) return;

    // Blank keys are empty rows the user left behind, not data.
    final settings = <String, String>{};
    for (var i = 0; i < _keyCtrls.length; i++) {
      final k = _keyCtrls[i].text.trim();
      final v = _valueCtrls[i].text.trim();
      if (k.isNotEmpty && v.isNotEmpty) settings[k] = v;
    }

    final label = _labelCtrl.text.trim();

    setState(() => _isSaving = true);
    try {
      await ExerciseSetupService.saveSetup(
        catalogId: widget.catalogId,
        equipment: widget.equipment,
        setupId: widget.setup?.setupId,
        label: label.isEmpty ? null : label,
        settings: settings,
        weightIncrementKg: step,
        // Carried through rather than edited: there's no field for it yet, and
        // dropping it on every save would silently forget a value the weight
        // suggestions depend on.
        minWeightKg: widget.setup?.minWeightKg,
        pinToExercise: _pinToExercise,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save: $e'),
            backgroundColor: LiftrColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _remove() async {
    final setupId = widget.setup?.setupId;
    if (setupId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text('Remove this setup?',
            style: TextStyle(
                fontSize: LiftrType.x16, color: context.lt.textPrimary)),
        content: Text(
          'Your logged workouts stay exactly as they are — they just stop '
          'saying how the machine was set.',
          style: TextStyle(
              fontSize: LiftrType.x13, color: context.lt.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: context.lt.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: LiftrColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ExerciseSetupService.deleteSetup(setupId);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final inferred = widget.inferredIncrement;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: lt.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(LiftrRadii.sheet)),
          border: Border.all(color: lt.border, width: LiftrBorders.hairline),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        // Scrollable, not just min-height: the setup list grows a row at a time
        // and the keyboard takes half the screen with it. Without this, a third
        // setting overflows the sheet and pushes Save out of reach — the content
        // has to move, not the sheet.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_hasExisting ? 'Setup' : 'New setup',
                      style: Theme.of(context).textTheme.displaySmall),
                  const Spacer(),
                  if (_hasExisting)
                    GestureDetector(
                      onTap: _remove,
                      child: Text('Remove',
                          style: TextStyle(
                              fontSize: LiftrType.x12,
                              color: lt.textSecondary)),
                    ),
                ],
              ),
              const SizedBox(height: LiftrSpacing.x4),
              Text(
                'Whatever you\'d otherwise have to work out again next week.',
                style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
              ),
              const SizedBox(height: LiftrSpacing.x16),
              Text('NAME',
                  style: TextStyle(
                    fontSize: LiftrType.x11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.08,
                    color: lt.textMuted,
                  )),
              const SizedBox(height: LiftrSpacing.x4),
              Text(
                'Only worth it once there are two to tell apart.',
                style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
              ),
              const SizedBox(height: LiftrSpacing.x6),
              _field(lt, _labelCtrl, hint: 'e.g. 5 kg stack'),
              const SizedBox(height: LiftrSpacing.x16),
              Text('WEIGHT STEP',
                  style: TextStyle(
                    fontSize: LiftrType.x11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.08,
                    color: lt.textMuted,
                  )),
              const SizedBox(height: LiftrSpacing.x4),
              // Which half of this sheet is shared is not guessable from
              // looking at it, and getting it wrong means silently changing
              // every other lift on this stack. So it says so.
              Text(
                _pinToExercise
                    ? 'This machine only.'
                    : 'Shared with every $_equipmentWord exercise — enter it '
                        'once.',
                style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
              ),
              const SizedBox(height: LiftrSpacing.x6),
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: _field(lt, _incrementCtrl, hint: '—', numeric: true),
                  ),
                  const SizedBox(width: LiftrSpacing.x8),
                  Text('kg',
                      style: TextStyle(
                          fontSize: LiftrType.x13, color: lt.textMuted)),
                  const Spacer(),
                  // The inferred value is offered as a fact you can accept, not
                  // as a question you must answer. Leaving it untouched is a
                  // valid outcome.
                  if (inferred != null && _incrementCtrl.text.trim().isEmpty)
                    GestureDetector(
                      onTap: () => setState(
                          () => _incrementCtrl.text = trimWeight(inferred)),
                      child: Text(
                        'Looks like ${trimWeight(inferred)} — use it',
                        style: const TextStyle(
                          fontSize: LiftrType.x11,
                          color: LiftrColors.accentDark,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: LiftrSpacing.x16),
              Text('SETTINGS',
                  style: TextStyle(
                    fontSize: LiftrType.x11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.08,
                    color: lt.textMuted,
                  )),
              const SizedBox(height: LiftrSpacing.x4),
              // The other half of the split, said out loud for the same reason:
              // a row and a curl are different heights on the same stack, so
              // these can't be shared the way the step above is.
              Text(
                'This exercise only — a row and a curl need different seats on '
                'the same stack.',
                style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
              ),
              const SizedBox(height: LiftrSpacing.x8),
              // Two settings per line rather than one.
              //
              // A setting is a short word and a number — "seat 4" — so a
              // full-width row per pair wasted most of the line and grew the
              // sheet by a whole row for every one you added.
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = LiftrSpacing.x8;
                  final cell = (constraints.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: LiftrSpacing.x6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < _keyCtrls.length; i++)
                        SizedBox(
                          width: cell,
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _field(lt, _keyCtrls[i],
                                    hint: 'seat', compact: true),
                              ),
                              const SizedBox(width: LiftrSpacing.x4),
                              Expanded(
                                flex: 2,
                                child: _field(lt, _valueCtrls[i],
                                    hint: '4', compact: true),
                              ),
                            ],
                          ),
                        ),

                    ],
                  );
                },
              ),
              const SizedBox(height: LiftrSpacing.x8),
              // Below the fields on a line of its own, always.
              //
              // It used to be the last child of the Wrap, on the theory that
              // sitting inline saved a row. Two cells are exactly a line wide —
              // `cell` is (maxWidth - gap) / 2 — so the moment you had two
              // settings there was no room left and the button wrapped to its
              // own line anyway. It only *looked* inline while you had one, and
              // then it moved.
              //
              // Given it lands on its own line regardless, it may as well do so
              // predictably, and look like something you can press: bordered and
              // filled like every other tap target here, rather than faint text
              // adrift under two boxed fields.
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => setState(_addRow),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    // No `alignment`, and the height comes from padding rather
                    // than a minHeight constraint. Both are load-bearing: a
                    // Container with an alignment expands to fill whatever
                    // bounded width it's given, so setting one here made the
                    // chip span the whole sheet regardless of its label. The
                    // horizontal strips elsewhere get away with the same pattern
                    // only because a scrolling ListView hands its children
                    // unbounded width, which nothing can expand into.
                    padding: const EdgeInsets.symmetric(
                        horizontal: LiftrSpacing.x12,
                        vertical: LiftrSpacing.x10),
                    decoration: BoxDecoration(
                      color: lt.card,
                      border: Border.all(
                          color: lt.border, width: LiftrBorders.hairline),
                      borderRadius: BorderRadius.circular(LiftrRadii.panel),
                    ),
                    child: Text(
                      '+ Add setting',
                      style: TextStyle(
                        fontSize: LiftrType.x11,
                        fontWeight: FontWeight.w500,
                        color: lt.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x20),
              ElevatedButton(
                onPressed: (_isSaving || _step == null) ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: LiftrColors.accentText),
                      )
                    : const Text('Save'),
              ),
              // Says why the button is off. A disabled control with no
              // explanation reads as a broken one, and the reason here is worth
              // knowing anyway — it's what the setup is for.
              if (_step == null) ...[
                const SizedBox(height: LiftrSpacing.x6),
                Text(
                  'A weight step is needed before this can be saved — it\'s what '
                  'lets the app suggest a weight you can actually load.',
                  style:
                      TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    LiftrTheme lt,
    TextEditingController ctrl, {
    required String hint,
    bool numeric = false,
    // Half-width setting cells can't spare 12px of padding on each side — that
    // left barely enough room for "back pad" to render before eliding.
    bool compact = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: lt.card,
        border: Border.all(color: lt.border, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.control),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: TextStyle(
            fontSize: compact ? LiftrType.x12 : LiftrType.x13,
            color: lt.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontSize: compact ? LiftrType.x12 : LiftrType.x13,
              color: lt.textDim),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
              horizontal: compact ? LiftrSpacing.x8 : LiftrSpacing.x12,
              vertical: LiftrSpacing.x10),
          fillColor: Colors.transparent,
        ),
      ),
    );
  }
}
