import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/run_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/run_math.dart';

/// Logging a run that already happened.
///
/// The whole of running, for now, and deliberately the first part built: it
/// needs no GPS, no permissions and no live state, so it's the one path that
/// works on a treadmill, indoors, or when you forgot to start tracking. Every
/// failure mode of the tracked flow eventually lands here.
///
/// Pops true if something was saved.
class AddRunScreen extends StatefulWidget {
  /// The day the run goes on — taken from the home screen's calendar rather
  /// than asked for again here. You already picked a date to get this far.
  final DateTime date;

  /// The interval being corrected, or null when logging a new one.
  ///
  /// Editing deliberately covers distance and time only. Name and notes live on
  /// the session, which every interval of the day shares, so offering them here
  /// would mean fixing one leg's distance and silently relabelling the rest.
  final DistanceInterval? interval;

  /// Opened from a day that isn't today and hasn't been unlocked.
  ///
  /// You can still read what you logged — looking back at it is the point — but
  /// nothing here may change it. Mirrors [ExerciseDetailScreen.readOnly].
  final bool readOnly;

  /// How many *other* runs share this day's session.
  ///
  /// Only used to warn that the name and notes are shared. Passed in rather
  /// than counted here: the caller already has the day's intervals loaded, and
  /// refetching them to render one line of text would be a round trip for
  /// nothing.
  final int otherRunsToday;

  const AddRunScreen({
    super.key,
    required this.date,
    this.interval,
    this.readOnly = false,
    this.otherRunsToday = 0,
  });

  @override
  State<AddRunScreen> createState() => _AddRunScreenState();
}

class _AddRunScreenState extends State<AddRunScreen> {
  final _distanceCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _secondsCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isSaving = false;

  /// The day's running session, loaded when editing so the name and notes start
  /// from what's already saved rather than blank.
  String? _sessionId;

  bool get _isEditing => widget.interval?.intervalId != null;

  @override
  void initState() {
    super.initState();
    // Recompute the pace line as the numbers change — it's the fastest way to
    // notice you typed minutes into the hours box.
    for (final c in [_distanceCtrl, _hoursCtrl, _minutesCtrl, _secondsCtrl]) {
      c.addListener(_onChanged);
    }
    _prefill();
    if (_isEditing) _loadSession();
  }

  /// Fetches the day's running session so the name and notes fields open with
  /// what's already on it.
  ///
  /// Looked up by date and discipline rather than by the interval's session id:
  /// getWorkoutSession already answers exactly this question, and adding a
  /// fetch-by-id purely for this screen would be a second way to ask it.
  Future<void> _loadSession() async {
    try {
      final session = await WorkoutService.getWorkoutSession(
        widget.date,
        discipline: RunService.disciplineKey,
      );
      if (!mounted || session == null) return;
      setState(() {
        _sessionId = session.sessionId;
        _nameCtrl.text = session.name ?? '';
        _notesCtrl.text = session.notes ?? '';
      });
    } catch (_) {
      // The name is a nicety; failing to load it must not block correcting a
      // distance, which is what you actually came here for.
    }
  }

  /// Loads the interval being corrected into the fields.
  ///
  /// Seconds are only filled when there are any: a 32-minute run should open as
  /// "32 m" with an empty seconds box, not "32 m 0 s", so the common case
  /// doesn't look like it was typed by a machine.
  void _prefill() {
    final i = widget.interval;
    if (i == null) return;

    final km = i.actualDistanceMeters / 1000;
    _distanceCtrl.text =
        km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(2);

    final s = i.durationSeconds;
    final hours = s ~/ 3600;
    final minutes = (s % 3600) ~/ 60;
    final seconds = s % 60;

    if (hours > 0) _hoursCtrl.text = '$hours';
    if (minutes > 0) _minutesCtrl.text = '$minutes';
    if (seconds > 0) _secondsCtrl.text = '$seconds';
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in [
      _distanceCtrl,
      _hoursCtrl,
      _minutesCtrl,
      _secondsCtrl,
      _nameCtrl,
      _notesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Kilometres in the field, metres in the database. People say "5.2 km", and
  /// asking for 5200 would be a small daily tax for no benefit.
  double? get _distanceMeters {
    final km = double.tryParse(_distanceCtrl.text.trim().replaceAll(',', '.'));
    if (km == null || km <= 0) return null;
    return km * 1000;
  }

  int get _durationSeconds {
    final h = int.tryParse(_hoursCtrl.text.trim()) ?? 0;
    final m = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    final s = int.tryParse(_secondsCtrl.text.trim()) ?? 0;
    return h * 3600 + m * 60 + s;
  }

  bool get _canSave =>
      !widget.readOnly &&
      _distanceMeters != null &&
      _durationSeconds > 0 &&
      !_isSaving;

  /// Removes this run, after asking.
  ///
  /// Lives here rather than behind a menu on the home card: the row's job is to
  /// open the run, and the destructive action belongs on the screen that shows
  /// you what you're about to destroy. Confirmed because there's nothing to undo
  /// it with — the distance and time came off a watch you've already put away.
  Future<void> _delete() async {
    final id = widget.interval?.intervalId;
    if (id == null) return;

    final lt = context.lt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text('Delete this run?',
            style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary)),
        content: Text(
          '${formatDistance(widget.interval!.actualDistanceMeters)} in '
          '${formatDuration(widget.interval!.durationSeconds)} will be removed.',
          style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: lt.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: LiftrColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await RunService.deleteInterval(id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('Could not delete the run: $e', error: true);
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

  Future<void> _save() async {
    final meters = _distanceMeters;
    final seconds = _durationSeconds;

    if (meters == null) {
      _toast('How far did you go?', error: true);
      return;
    }
    if (seconds <= 0) {
      _toast('How long did it take?', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await RunService.updateInterval(
          widget.interval!.intervalId!,
          actualDistanceMeters: meters,
          durationSeconds: seconds,
        );

        // The name and notes belong to the day's session, not to this leg, so
        // they're written separately — and only when the session was found.
        final sessionId = _sessionId;
        if (sessionId != null) {
          final name = _nameCtrl.text.trim();
          await WorkoutService.updateWorkoutSession(
            sessionId,
            WorkoutSessionsPayload(
              sessionDate: widget.date,
              // Never blank: an empty name would leave the card's title empty.
              name: name.isEmpty ? 'Run' : name,
              notes: _notesCtrl.text.trim().isEmpty
                  ? null
                  : _notesCtrl.text.trim(),
              discipline: RunService.disciplineKey,
            ),
          );
        }
      } else {
        await RunService.logManualRun(
          date: widget.date,
          distanceMeters: meters,
          durationSeconds: seconds,
          name: _nameCtrl.text,
          notes: _notesCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _toast('Could not save the run: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final meters = _distanceMeters;
    final seconds = _durationSeconds;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(lt),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                children: [
                  _label(lt, 'DISTANCE'),
                  const SizedBox(height: LiftrSpacing.x6),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: _field(lt, _distanceCtrl,
                            hint: '5.2', numeric: true, big: true),
                      ),
                      const SizedBox(width: LiftrSpacing.x10),
                      Text('km',
                          style: TextStyle(
                              fontSize: LiftrType.x14, color: lt.textMuted)),
                    ],
                  ),

                  const SizedBox(height: LiftrSpacing.x20),
                  _label(lt, 'TIME'),
                  const SizedBox(height: LiftrSpacing.x6),
                  Row(
                    children: [
                      Expanded(
                        child: _field(lt, _hoursCtrl,
                            hint: '0', numeric: true, suffix: 'h'),
                      ),
                      const SizedBox(width: LiftrSpacing.x8),
                      Expanded(
                        child: _field(lt, _minutesCtrl,
                            hint: '32', numeric: true, suffix: 'm'),
                      ),
                      const SizedBox(width: LiftrSpacing.x8),
                      Expanded(
                        child: _field(lt, _secondsCtrl,
                            hint: '10', numeric: true, suffix: 's'),
                      ),
                    ],
                  ),

                  // The one derived number worth showing while typing: a pace
                  // that reads as nonsense is how you catch a mistyped field
                  // before it's saved.
                  const SizedBox(height: LiftrSpacing.x12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: LiftrSpacing.x14,
                        vertical: LiftrSpacing.x12),
                    decoration: BoxDecoration(
                      color: lt.card,
                      border: Border.all(
                          color: lt.borderSubtle, width: LiftrBorders.hairline),
                      borderRadius: BorderRadius.circular(LiftrRadii.field),
                    ),
                    child: Row(
                      children: [
                        Text('Pace',
                            style: TextStyle(
                                fontSize: LiftrType.x12,
                                color: lt.textSecondary)),
                        const Spacer(),
                        Text(
                          meters == null ? '—' : formatPace(meters, seconds),
                          style: TextStyle(
                            fontSize: LiftrType.x16,
                            fontWeight: FontWeight.w600,
                            color: meters == null
                                ? lt.textDim
                                : LiftrColors.accentDark,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: LiftrSpacing.x20),
                  _label(lt, 'NAME'),
                  const SizedBox(height: LiftrSpacing.x6),
                  _field(lt, _nameCtrl, hint: 'Morning run'),

                  // Both of these live on the day's session, which every run of
                  // that day shares. Said out loud only when there's more than
                  // one, since that's the only time changing it here touches
                  // something you weren't looking at.
                  if (_isEditing && widget.otherRunsToday > 0) ...[
                    const SizedBox(height: LiftrSpacing.x6),
                    Text(
                      'Shared with the '
                      '${widget.otherRunsToday == 1 ? 'other run' : '${widget.otherRunsToday} other runs'} '
                      'logged today.',
                      style: TextStyle(
                          fontSize: LiftrType.x11, color: lt.textMuted),
                    ),
                  ],

                  const SizedBox(height: LiftrSpacing.x16),
                  _label(lt, 'NOTES'),
                  const SizedBox(height: LiftrSpacing.x6),
                  _field(lt, _notesCtrl, hint: 'How did it feel?', lines: 3),

                  // No save button on a locked day — there's nothing you could
                  // press it to do.
                  if (!widget.readOnly) ...[
                    const SizedBox(height: LiftrSpacing.x24),
                    ElevatedButton(
                      onPressed: _canSave ? _save : null,
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: LiftrColors.accentText),
                            )
                          : Text(_isEditing ? 'Save changes' : 'Save run'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(LiftrTheme lt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context, false),
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
                  widget.readOnly
                      ? 'Run'
                      : _isEditing
                          ? 'Edit run'
                          : 'Add a run',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Text(
                  _dateLabel,
                  style:
                      TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
                ),
              ],
            ),
          ),

          // Says why the controls are missing, rather than leaving them
          // mysteriously absent. Same badge as the exercise detail screen.
          if (widget.readOnly)
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
          // Deleting lives here, on the screen showing what you'd delete —
          // never behind a menu on the card that merely lists it.
          else if (_isEditing)
            GestureDetector(
              onTap: _delete,
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                    horizontal: LiftrSpacing.x6),
                child: Text(
                  'Delete',
                  style: TextStyle(
                      fontSize: LiftrType.x12, color: lt.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _dateLabel => longDate(widget.date);

  Widget _label(LiftrTheme lt, String text) => Text(
        text,
        style: TextStyle(
          fontSize: LiftrType.x11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.08,
          color: lt.textMuted,
        ),
      );

  Widget _field(
    LiftrTheme lt,
    TextEditingController ctrl, {
    required String hint,
    bool numeric = false,
    bool big = false,
    int lines = 1,
    String? suffix,
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
        // Locked days are readable but not editable — the fields still show
        // what you logged, they just won't take a keystroke.
        readOnly: widget.readOnly,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: TextStyle(
          fontSize: big ? LiftrType.x20 : LiftrType.x13,
          fontWeight: big ? FontWeight.w600 : FontWeight.w400,
          color: big ? LiftrColors.accent : lt.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontSize: big ? LiftrType.x20 : LiftrType.x13, color: lt.textDim),
          suffixText: suffix,
          suffixStyle: TextStyle(fontSize: LiftrType.x12, color: lt.textMuted),
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
