import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class AddExerciseScreen extends StatefulWidget {
  final DateTime sessionDate;
  const AddExerciseScreen({super.key, required this.sessionDate});

  @override
  State<AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<AddExerciseScreen> {
  final _sessionNameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selectedExercise;
  String? _selectedExerciseEmoji;
  String? _selectedCatalogId;
  bool _nameError = false;
  bool _isSaving = false;

  List<CatalogExercises> _catalog = [];

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final catalog = await WorkoutService.getExerciseCatalog();
    if (mounted) setState(() => _catalog = catalog);
  }

  @override
  void dispose() {
    _sessionNameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _pickExercise() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExercisePickerSheet(
        exercises: _catalog,
        selectedName: _selectedExercise,
        onSelect: (emoji, name, catalogId) {
          setState(() {
            _selectedExercise = name;
            _selectedExerciseEmoji = emoji;
            _selectedCatalogId = catalogId;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _save() async {
    final name = _sessionNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final sessionId = await WorkoutService.createWorkoutSession(
        WorkoutSessionsPayload(
          sessionDate: widget.sessionDate,
          name: name,
          notes: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        ),
      );

      await WorkoutService.createWorkoutExercise(
        WorkoutExercisePayload(
          sessionId: sessionId,
          catalogId: _selectedCatalogId,
          orderIndex: 1,
          notes: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        ),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: const Color(0xFFE24B4A),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Nav header ──────────────────────────────────
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
                        border: Border.all(color: lt.border, width: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.chevron_left, size: 20, color: lt.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add Exercise',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                ],
              ),
            ),

            // ── Form ────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Session name
                    const SectionLabel('Session Name'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: lt.card,
                        border: Border.all(
                          color: _nameError ? const Color(0xFFE24B4A) : lt.border,
                          width: _nameError ? 1.0 : 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _sessionNameCtrl,
                        onChanged: (_) {
                          if (_nameError) setState(() => _nameError = false);
                        },
                        style: TextStyle(fontSize: 14, color: lt.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'e.g. Push Day A',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                    if (_nameError) ...[
                      const SizedBox(height: 5),
                      const Text(
                        'Session name is required',
                        style: TextStyle(fontSize: 11, color: Color(0xFFE24B4A)),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Exercise picker
                    const SectionLabel('Exercise'),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickExercise,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: lt.card,
                          border: Border.all(
                            color: _selectedExercise != null ? lt.accentBorder : lt.border,
                            width: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            if (_selectedExercise != null) ...[
                              Text(_selectedExerciseEmoji!, style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedExercise!,
                                  style: TextStyle(fontSize: 14, color: lt.textPrimary),
                                ),
                              ),
                            ] else
                              Expanded(
                                child: Text(
                                  'Choose an exercise…',
                                  style: TextStyle(fontSize: 14, color: lt.textDim),
                                ),
                              ),
                            Icon(Icons.chevron_right, size: 16, color: lt.textDim),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Notes
                    const SectionLabel('Notes'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: lt.card,
                        border: Border.all(color: lt.border, width: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _noteCtrl,
                        maxLines: 4,
                        style: TextStyle(fontSize: 14, color: lt.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Optional notes for this exercise…',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Cancel / Save ────────────────────────────────
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
                          border: Border.all(color: lt.border, width: 0.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: lt.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_selectedExercise == null || _isSaving) ? null : _save,
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
}

// ── Exercise Picker Bottom Sheet ──────────────────────────────
class _ExercisePickerSheet extends StatefulWidget {
  final List<CatalogExercises> exercises;
  final String? selectedName;
  final void Function(String emoji, String name, String? catalogId) onSelect;
  const _ExercisePickerSheet({
    required this.exercises,
    required this.selectedName,
    required this.onSelect,
  });

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  static String _muscleEmoji(String? group) {
    switch (group?.toLowerCase()) {
      case 'chest': return '🏋️';
      case 'back': return '🔛';
      case 'legs': return '🦵';
      case 'shoulders': return '💪';
      case 'triceps': return '📌';
      case 'biceps': return '💪';
      default: return '🏃';
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final filtered = widget.exercises
        .where((e) => (e.name ?? '').toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: lt.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: lt.borderSubtle, width: 0.5)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: lt.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose Exercise',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: lt.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, size: 20, color: lt.textMuted),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: lt.card,
                border: Border.all(color: lt.border, width: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(fontSize: 14, color: lt.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search exercises…',
                  prefixIcon: Icon(Icons.search, size: 18, color: lt.textDim),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  fillColor: Colors.transparent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Exercise list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? 'No exercises found.' : 'No results for "$_query".',
                      style: TextStyle(fontSize: 13, color: lt.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final ex = filtered[i];
                      final emoji = _muscleEmoji(ex.muscleGroup);
                      final name = ex.name ?? '';
                      final muscle = ex.muscleGroup ?? ex.category ?? '';
                      final isSelected = name == widget.selectedName;
                      return InkWell(
                        onTap: () => widget.onSelect(emoji, name, ex.catalogId),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: lt.card,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(emoji, style: const TextStyle(fontSize: 16)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: lt.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      muscle,
                                      style: TextStyle(fontSize: 11, color: lt.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle, size: 18, color: LiftrColors.accent),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
