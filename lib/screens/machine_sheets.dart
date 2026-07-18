import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/machine_service.dart';
import '../theme/app_theme.dart';

/// Machines are only a meaningful idea for equipment you sit down at and set up.
/// A barbell has no seat height and no stack.
bool exerciseHasMachines(String? equipment) {
  final e = equipment?.toLowerCase().trim();
  return e == 'machine' || e == 'cable';
}

/// The machine strip under the exercise title.
///
/// Renders as little as it can get away with, because the whole feature is
/// optional and must never look like a form to fill in:
///
///   none registered → just "+ set up machine"
///   exactly one     → the station and its setup; tap edits it, no choice to make
///   two or more     → one chip each, nothing preselected; tap picks, hold edits
///
/// The last case is the only one that asks anything of you, and it only happens
/// because you registered a second station yourself. The "+" is present at every
/// count, including one — without it there is no route from one machine to two.
class MachineStrip extends StatelessWidget {
  final List<UserMachine> candidates;
  final String? selectedId;
  final MachineExerciseSettings? settings;
  final bool readOnly;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<UserMachine> onEdit;

  const MachineStrip({
    super.key,
    required this.candidates,
    required this.selectedId,
    required this.settings,
    required this.readOnly,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty && readOnly) return const SizedBox.shrink();

    // With one station there is nothing to choose between, so tapping its chip
    // edits it. With two or more, tapping picks — and editing moves to a long
    // press, since picking is the thing you do every session and editing is the
    // thing you do once.
    final picking = candidates.length > 1;

    // One line that scrolls sideways, never a block that grows downwards.
    //
    // A Wrap reflowed onto a second and third row as machines were added or a
    // label got longer, shoving the chart down the screen by a row at a time.
    // Same shape as the discipline chips on the home screen.
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final m in candidates) ...[
            _chip(
              context,
              label: _labelFor(m),
              selected: selectedId == m.machineId,
              onTap: readOnly
                  ? null
                  : picking
                      ? () {
                          // Tapping the selected chip clears it — the way back
                          // out of a mis-tap without inventing a "no machine"
                          // option.
                          onSelect(
                              selectedId == m.machineId ? null : m.machineId);
                        }
                      : () => onEdit(m),
              onLongPress: readOnly || !picking ? null : () => onEdit(m),
            ),
            const SizedBox(width: LiftrSpacing.x6),
          ],

          // Always reachable, at every count. This used to only render once you
          // already had two machines, which made the second one impossible to
          // add: registering your first replaced the "+ set up" text with a lone
          // chip and left no way back. The two-machine case is the entire point
          // of the feature, so the way into it can't be behind itself.
          if (!readOnly)
            _chip(
              context,
              label: candidates.isEmpty ? '+ Set up machine' : '+ Machine',
              selected: false,
              onTap: onAdd,
              muted: true,
            ),
        ],
      ),
    );
  }

  /// "5 kg cable · seat 4" — the setup is only appended for the station you're
  /// actually on, since that's the only one whose seat height is any use.
  String _labelFor(UserMachine m) {
    final base = m.displayLabel;
    final s = settings;
    if (selectedId != m.machineId || s == null || s.settings.isEmpty) {
      return base;
    }
    return '$base · ${s.summary}';
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool muted = false,
  }) {
    final lt = context.lt;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 32 high rather than the ~19 the text alone gives: this is a control
        // you tap mid-set with clumsy hands, not a label.
        //
        // Capped in width because a chip carrying its setup — "5 kg cable ·
        // seat 4 · back pad 2" — is wide enough on its own to push "+ machine"
        // off the end of the strip, where nothing suggests scrolling to find it.
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x10, vertical: LiftrSpacing.x6),
        decoration: BoxDecoration(
          color: selected ? lt.accentBg : lt.card,
          border: Border.all(
            color: selected ? LiftrColors.accent : lt.border,
            width: selected ? LiftrBorders.thin : LiftrBorders.hairline,
          ),
          borderRadius: BorderRadius.circular(LiftrRadii.panel),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: LiftrType.x11,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            // textMuted, never textDim, even for the quiet "add" affordance:
            // textDim on the dark card is about 1.6:1 contrast, which is not
            // subtle, it's invisible. Quiet has to stay legible.
            color: selected
                ? lt.accentTextColor
                : muted
                    ? lt.textMuted
                    : lt.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Creates or edits a machine and its setup for one exercise.
///
/// Returns true if anything was saved or deleted, so the caller knows to reload.
Future<bool> showMachineEditor(
  BuildContext context, {
  required String catalogId,
  UserMachine? machine,
  double? inferredIncrement,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MachineEditorSheet(
      catalogId: catalogId,
      machine: machine,
      inferredIncrement: inferredIncrement,
    ),
  );
  return saved ?? false;
}

class _MachineEditorSheet extends StatefulWidget {
  final String catalogId;
  final UserMachine? machine;
  final double? inferredIncrement;

  const _MachineEditorSheet({
    required this.catalogId,
    this.machine,
    this.inferredIncrement,
  });

  @override
  State<_MachineEditorSheet> createState() => _MachineEditorSheetState();
}

class _MachineEditorSheetState extends State<_MachineEditorSheet> {
  final _labelCtrl = TextEditingController();
  final _incrementCtrl = TextEditingController();

  /// Setup rows as parallel controllers rather than a Map, because a Map keyed
  /// on the field you're editing loses the row the moment the key is blank.
  final _keyCtrls = <TextEditingController>[];
  final _valueCtrls = <TextEditingController>[];

  bool _isSaving = false;
  bool _isLoading = true;

  bool get _isNew => widget.machine?.machineId == null;

  @override
  void initState() {
    super.initState();
    _labelCtrl.text = widget.machine?.label ?? '';
    final inc = widget.machine?.weightIncrementKg;
    if (inc != null) _incrementCtrl.text = _trim(inc);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final id = widget.machine?.machineId;
    MachineExerciseSettings? existing;
    if (id != null) {
      existing = await MachineService.getSettings(id, widget.catalogId);
    }

    if (!mounted) return;
    setState(() {
      final entries = existing?.settings.entries.toList() ?? [];
      for (final e in entries) {
        _keyCtrls.add(TextEditingController(text: e.key));
        _valueCtrls.add(TextEditingController(text: e.value));
      }
      if (_keyCtrls.isEmpty) _addRow();
      _isLoading = false;
    });
  }

  void _addRow() {
    _keyCtrls.add(TextEditingController());
    _valueCtrls.add(TextEditingController());
  }

  @override
  void dispose() {
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
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Give the machine a name you\'ll recognise'),
          backgroundColor: LiftrColors.danger,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final increment = double.tryParse(_incrementCtrl.text.trim());

      final machineId = _isNew
          ? await MachineService.createMachine(
              label: label,
              weightIncrementKg: increment,
            )
          : widget.machine!.machineId!;

      if (!_isNew) {
        await MachineService.updateMachine(
          machineId,
          label: label,
          weightIncrementKg: increment,
          minWeightKg: widget.machine?.minWeightKg,
          notes: widget.machine?.notes,
        );
      }

      // Blank keys are empty rows the user left behind, not data.
      final settings = <String, String>{};
      for (var i = 0; i < _keyCtrls.length; i++) {
        final k = _keyCtrls[i].text.trim();
        final v = _valueCtrls[i].text.trim();
        if (k.isNotEmpty && v.isNotEmpty) settings[k] = v;
      }

      await MachineService.saveSettings(
        machineId,
        widget.catalogId,
        settings: settings,
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

  Future<void> _delete() async {
    final id = widget.machine?.machineId;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text('Forget this machine?',
            style: TextStyle(
                fontSize: LiftrType.x16, color: context.lt.textPrimary)),
        content: Text(
          'Your logged workouts stay exactly as they are — they just stop '
          'saying which machine they were on.',
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
            child: const Text('Forget',
                style: TextStyle(color: LiftrColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await MachineService.deleteMachine(id);
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
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: LiftrSpacing.x36),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: LiftrColors.accent),
                  ),
                ),
              )
            // Scrollable, not just min-height: the setup list grows a row at a
            // time and the keyboard takes half the screen with it. Without
            // this, a third setting overflows the sheet and pushes Save out of
            // reach — the content has to move, not the sheet.
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _isNew ? 'New machine' : 'Machine',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const Spacer(),
                        if (!_isNew)
                          GestureDetector(
                            onTap: _delete,
                            child: Text('Forget',
                                style: TextStyle(
                                    fontSize: LiftrType.x12,
                                    color: lt.textSecondary)),
                          ),
                      ],
                    ),
                    const SizedBox(height: LiftrSpacing.x4),
                    Text(
                      'Whatever tells it apart from the other one.',
                      style: TextStyle(
                          fontSize: LiftrType.x11, color: lt.textMuted),
                    ),
                    const SizedBox(height: LiftrSpacing.x12),
                    _field(lt, _labelCtrl, hint: 'e.g. 5 kg cable'),
                    const SizedBox(height: LiftrSpacing.x16),
                    Text('WEIGHT STEP',
                        style: TextStyle(
                          fontSize: LiftrType.x11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.08,
                          color: lt.textMuted,
                        )),
                    const SizedBox(height: LiftrSpacing.x6),
                    Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: _field(lt, _incrementCtrl,
                              hint: '—', numeric: true),
                        ),
                        const SizedBox(width: LiftrSpacing.x8),
                        Text('kg',
                            style: TextStyle(
                                fontSize: LiftrType.x13, color: lt.textMuted)),
                        const Spacer(),
                        // The inferred value is offered as a fact you can accept,
                        // not as a question you must answer. Leaving it untouched
                        // is a valid outcome.
                        if (inferred != null &&
                            _incrementCtrl.text.trim().isEmpty)
                          GestureDetector(
                            onTap: () => setState(
                                () => _incrementCtrl.text = _trim(inferred)),
                            child: Text(
                              'Looks like ${_trim(inferred)} — use it',
                              style: const TextStyle(
                                fontSize: LiftrType.x11,
                                color: LiftrColors.accentDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: LiftrSpacing.x16),
                    Text('SETUP',
                        style: TextStyle(
                          fontSize: LiftrType.x11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.08,
                          color: lt.textMuted,
                        )),
                    const SizedBox(height: LiftrSpacing.x4),
                    Text(
                      'Only for this exercise — a cable row and a curl need '
                      'different seats on the same stack.',
                      style: TextStyle(
                          fontSize: LiftrType.x11, color: lt.textMuted),
                    ),
                    const SizedBox(height: LiftrSpacing.x8),
                    // Two settings per line rather than one.
                    //
                    // A setting is a short word and a number — "seat 4" — so a
                    // full-width row per pair wasted most of the line and grew
                    // the sheet by a whole row for every one you added. Four
                    // settings used to be four rows; now they're two.
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

                            // Sits inline with the fields rather than on its own
                            // line below them, so adding a setting doesn't push
                            // the button away each time.
                            GestureDetector(
                              onTap: () => setState(_addRow),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                constraints:
                                    const BoxConstraints(minHeight: 32),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: LiftrSpacing.x4),
                                alignment: Alignment.center,
                                child: Text('+ add',
                                    style: TextStyle(
                                        fontSize: LiftrType.x11,
                                        color: lt.textMuted)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: LiftrSpacing.x20),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: LiftrColors.accentText),
                            )
                          : const Text('Save'),
                    ),
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

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
