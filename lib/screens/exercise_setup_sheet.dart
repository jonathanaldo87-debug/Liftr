import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/exercise_setup_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

bool exerciseHasSetup(String? equipment) {
  return equipment?.toLowerCase().trim() != 'bodyweight';
}

class ExerciseSetupLine extends StatelessWidget {
  final List<ExerciseSetup> setups;

  final String? selectedId;

  final bool readOnly;

  final ValueChanged<String?> onSelect;

  final ValueChanged<ExerciseSetup> onEdit;

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
    if (setups.isEmpty && readOnly) return const SizedBox.shrink();

    return SizedBox(
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
            color: filled ? lt.accentTextColor : lt.textMuted,
          ),
        ),
      ),
    );
  }
}

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

  final _keyCtrls = <TextEditingController>[];
  final _valueCtrls = <TextEditingController>[];

  bool _isSaving = false;

  bool get _hasExisting => widget.setup?.setupId != null;

  bool get _pinToExercise =>
      widget.equipment?.toLowerCase().trim() == 'machine';

  String get _equipmentWord {
    final e = widget.equipment?.toLowerCase().trim();
    return (e == null || e.isEmpty) ? 'other' : e;
  }

  double? get _step {
    final v = double.tryParse(_incrementCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  @override
  void initState() {
    super.initState();

    _incrementCtrl.addListener(_onStepChanged);

    final existing = widget.setup;
    _labelCtrl.text = existing?.label ?? '';

    final inc = existing?.weightIncrementKg;
    if (inc != null) _incrementCtrl.text = trimWeight(inc);

    for (final e in existing?.settings.entries ?? <MapEntry<String, String>>[]) {
      _keyCtrls.add(TextEditingController(text: e.key));
      _valueCtrls.add(TextEditingController(text: e.value));
    }

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
    final step = _step;
    if (step == null) return;

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
              Text(
                'This exercise only — a row and a curl need different seats on '
                'the same stack.',
                style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
              ),
              const SizedBox(height: LiftrSpacing.x8),
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
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => setState(_addRow),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
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
