import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../utils/exercise_search.dart';
import '../utils/format.dart';

class AddExerciseScreen extends StatefulWidget {
  final DateTime sessionDate;
  const AddExerciseScreen({super.key, required this.sessionDate});

  @override
  State<AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<AddExerciseScreen> {
  final _sessionNameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _exerciseCtrl = TextEditingController();
  final _exerciseFocus = FocusNode();

  /// The exercise picked from the dropdown. Null means the field holds free text
  /// that matches nothing, which is what keeps Save disabled.
  CatalogExercises? _selected;

  bool _nameError = false;
  bool _isSaving = false;

  List<CatalogExercises> _catalog = [];
  List<CatalogExercises> _recent = [];

  /// Built once when the catalog lands — it precomputes a search index, so
  /// rebuilding it per keystroke would defeat the point.
  ExerciseSearch? _search;

  /// The workout already logged on this date, if any. When it exists we append
  /// to it instead of starting a second session for the same day.
  WorkoutSessions? _existingSession;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final catalog = await WorkoutService.getExerciseCatalog();
    final recent = await WorkoutService.getRecentExercises();
    final session = await WorkoutService.getWorkoutSession(widget.sessionDate);

    if (mounted) {
      setState(() {
        _catalog = catalog;
        _search = ExerciseSearch(catalog);
        _recent = recent;
        _existingSession = session;
        // Adding to a day that already has a workout: show its name rather than
        // asking for one again. Editing it renames the session.
        if (session?.name != null) _sessionNameCtrl.text = session!.name!;
      });
    }
  }

  @override
  void dispose() {
    _sessionNameCtrl.dispose();
    _noteCtrl.dispose();
    _exerciseCtrl.dispose();
    _exerciseFocus.dispose();
    super.dispose();
  }

  /// Matches on any word, in any order, across name *and* equipment/muscle —
  /// see [ExerciseSearch]. An empty field offers your recent lifts instead.
  Iterable<CatalogExercises> _rank(String raw) {
    if (raw.trim().isEmpty) {
      return _recent.isNotEmpty ? _recent : _catalog.take(8);
    }
    return _search?.search(raw) ?? const [];
  }

  /// e.g. "Barbell · Biceps" — the only way to tell the curl variants apart.
  static String _subtitle(CatalogExercises e) =>
      detailLine([e.equipment, e.muscleGroup]);

  void _select(CatalogExercises e) {
    setState(() => _selected = e);
    _exerciseFocus.unfocus();
  }

  Future<void> _save() async {
    final name = _sessionNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final notes = _noteCtrl.text.trim();

      // Reuse the day's session if it has one. Unconditionally creating here is
      // what produced two sessions for a single day the moment you added a
      // second exercise.
      final sessionId = await WorkoutService.getOrCreateSession(
        widget.sessionDate,
        name,
      );

      final existingId = _existingSession?.sessionId;
      if (existingId != null && _existingSession!.name != name) {
        await WorkoutService.updateWorkoutSession(
          existingId,
          WorkoutSessionsPayload(
            sessionDate: widget.sessionDate,
            name: name,
            notes: _existingSession!.notes,
          ),
        );
      }

      // orderIndex omitted on purpose: the service appends. Hardcoding 1 here
      // left every exercise in the session sitting at the same position.
      await WorkoutService.createWorkoutExercise(
        WorkoutExercisePayload(
          sessionId: sessionId,
          catalogId: _selected?.catalogId,
          notes: notes.isEmpty ? null : notes,
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

                    // ── Exercise autocomplete ───────────────
                    const SectionLabel('Exercise'),
                    const SizedBox(height: 8),
                    _buildExerciseField(lt),
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
                      onPressed:
                          (_selected == null || _isSaving) ? null : _save,
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

  Widget _buildExerciseField(LiftrTheme lt) {
    // LayoutBuilder gives the dropdown the field's exact width — optionsViewBuilder
    // renders into an unconstrained Align, so without this it collapses.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return RawAutocomplete<CatalogExercises>(
          textEditingController: _exerciseCtrl,
          focusNode: _exerciseFocus,
          displayStringForOption: (e) => e.name ?? '',
          optionsBuilder: (value) => _rank(value.text),
          onSelected: _select,
          fieldViewBuilder: (context, controller, focusNode, _) {
            final selected = _selected;
            final hasSelection = selected != null;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: lt.card,
                border: Border.all(
                  color: hasSelection ? lt.accentBorder : lt.border,
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (hasSelection) ...[
                    Text(
                      exerciseEmoji(selected.category, selected.muscleGroup),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                  ] else
                    Icon(Icons.search, size: 18, color: lt.textDim),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: TextStyle(fontSize: 14, color: lt.textPrimary),
                      onChanged: (v) {
                        // Typing past a selection invalidates it, which disables Save.
                        if (selected != null && v.trim() != selected.name) {
                          setState(() => _selected = null);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Search exercises…',
                        hintStyle: TextStyle(fontSize: 14, color: lt.textDim),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        fillColor: Colors.transparent,
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        controller.clear();
                        setState(() => _selected = null);
                      },
                      child: Icon(Icons.close, size: 16, color: lt.textDim),
                    ),
                ],
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList();
            final showingRecents = _exerciseCtrl.text.trim().isEmpty &&
                _recent.isNotEmpty;

            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: width,
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: lt.surface,
                      border: Border.all(color: lt.border, width: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showingRecents)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'RECENT',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w600,
                                  color: lt.textMuted,
                                ),
                              ),
                            ),
                          ),
                        Flexible(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final e = list[i];
                              final sub = _subtitle(e);
                              return InkWell(
                                onTap: () => onSelected(e),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 9),
                                  child: Row(
                                    children: [
                                      Text(
                                        exerciseEmoji(e.category, e.muscleGroup),
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.name ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: lt.textPrimary,
                                              ),
                                            ),
                                            if (sub.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                sub,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: lt.textMuted,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
