import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/run_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../utils/run_math.dart';

/// Wrapping up a tracked session: the totals across every interval, an optional
/// title and notes, and the two ways out — save it, or throw it away.
///
/// Reached from the interval summary's "End session". It's a real route rather
/// than another phase of the tracking screen because by now the run is over —
/// nothing is live, there's no GPS or wakelock to keep hold of, so it has no
/// reason to share that screen's machinery.
///
/// Pops a string the caller acts on: `'saved'` once the session is named and
/// ended, `'discarded'` once it's deleted, and null if the user backed out to
/// go add another interval after all.
class RunSaveScreen extends StatefulWidget {
  final String sessionId;
  final DateTime date;
  final Discipline discipline;

  const RunSaveScreen({
    super.key,
    required this.sessionId,
    required this.date,
    required this.discipline,
  });

  @override
  State<RunSaveScreen> createState() => _RunSaveScreenState();
}

class _RunSaveScreenState extends State<RunSaveScreen> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  /// The intervals themselves rather than just [RunTotals]: the count and the
  /// per-interval numbers both come off them, and refetching for each would be
  /// two round trips for one question.
  List<DistanceInterval>? _intervals;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final legs = await RunService.getIntervals(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _intervals = legs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Could not load the session: $e', error: true);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final name = _nameCtrl.text.trim();
      await WorkoutService.updateWorkoutSession(
        widget.sessionId,
        WorkoutSessionsPayload(
          sessionDate: widget.date,
          // Never blank — an empty name would leave the day's card titleless.
          name: name.isEmpty ? 'Run' : name,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          discipline: widget.discipline.key,
        ),
      );
      // Ending is a flag flip: the session and its intervals stay exactly as
      // they are, you're just no longer in it.
      await WorkoutService.endSession(widget.sessionId);
      if (mounted) Navigator.pop(context, 'saved');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('Could not save the session: $e', error: true);
      }
    }
  }

  Future<void> _discard() async {
    final lt = context.lt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text('Discard this session?',
            style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary)),
        content: Text(
          'Every interval you ran in this session will be deleted. This can\'t '
          'be undone.',
          style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep it', style: TextStyle(color: lt.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Discard', style: TextStyle(color: lt.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await RunService.discardSession(widget.sessionId);
      if (mounted) Navigator.pop(context, 'discarded');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('Could not discard the session: $e', error: true);
      }
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? LiftrColors.danger : null,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final legs = _intervals ?? const [];
    final totals = RunTotals.from(legs);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('Save session',
                  style: Theme.of(context).textTheme.displayMedium),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: LiftrColors.accent),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                      children: [
                        _TotalsPanel(totals: totals),
                        const SizedBox(height: LiftrSpacing.x24),
                        _label(lt, 'TITLE'),
                        const SizedBox(height: LiftrSpacing.x6),
                        _field(lt, _nameCtrl, hint: 'Morning run'),
                        const SizedBox(height: LiftrSpacing.x16),
                        _label(lt, 'NOTES'),
                        const SizedBox(height: LiftrSpacing.x6),
                        _field(lt, _notesCtrl,
                            hint: 'How did it feel?', lines: 3),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: LiftrColors.accentText),
                          )
                        : const Text('Save session'),
                  ),
                  const SizedBox(height: LiftrSpacing.x8),
                  TextButton(
                    onPressed: _busy ? null : _discard,
                    child: Text('Discard',
                        style: TextStyle(color: lt.danger)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(LiftrTheme lt, String text) => Text(
        text,
        style: TextStyle(
            fontSize: LiftrType.x11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.08,
            color: lt.textMuted),
      );

  Widget _field(
    LiftrTheme lt,
    TextEditingController ctrl, {
    required String hint,
    int lines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: lt.card,
        border: Border.all(color: lt.border, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.field),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: lines,
        style: TextStyle(fontSize: LiftrType.x13, color: lt.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: LiftrType.x13, color: lt.textDim),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x12),
          fillColor: Colors.transparent,
        ),
      ),
    );
  }
}

/// The four numbers that describe a session — distance, time, intervals, pace.
class _TotalsPanel extends StatelessWidget {
  final RunTotals totals;
  const _TotalsPanel({required this.totals});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Container(
      padding: const EdgeInsets.all(LiftrSpacing.x20),
      decoration: BoxDecoration(
        color: lt.accentBg,
        border: Border.all(color: LiftrColors.accent, width: LiftrBorders.thin),
        borderRadius: BorderRadius.circular(LiftrRadii.sheet),
      ),
      child: Column(
        children: [
          Text(
            formatDistance(totals.distanceMeters),
            style: const TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontSize: 52,
                color: LiftrColors.accentDark),
          ),
          const SizedBox(height: LiftrSpacing.x16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Cell(label: 'TIME', value: formatDuration(totals.durationSeconds)),
              _Cell(
                  label: 'INTERVALS', value: '${totals.intervalCount}'),
              _Cell(
                  label: 'AVG PACE',
                  value: formatPace(
                      totals.distanceMeters, totals.durationSeconds)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  const _Cell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: LiftrType.x16,
                fontWeight: FontWeight.w600,
                color: lt.textPrimary)),
        const SizedBox(height: LiftrSpacing.x2),
        Text(label,
            style: TextStyle(
                fontSize: LiftrType.x10,
                letterSpacing: 0.08,
                color: lt.accentMid)),
      ],
    );
  }
}
