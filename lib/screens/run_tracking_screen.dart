import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/models.dart';
import '../services/location_service.dart';
import '../services/run_backup.dart';
import '../services/run_notification.dart';
import '../services/run_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../utils/run_math.dart';
import 'run_save_screen.dart';

/// The tracked run — GPS from here down, and the one screen that owns the live
/// session while it's happening.
///
/// Built as a single widget with an internal phase rather than a stack of routes
/// because setup → acquiring → countdown → running → summary all share one live
/// thing: the GPS subscription, the accumulator, the wakelock, the notification.
/// Pushing a new route per phase would tear those down and rebuild them between
/// every step, and "Add another interval" would have to reassemble the session
/// from nothing. The save screen is a separate route because by then the run is
/// over and there's nothing live left to hand it.
///
/// Pops `true` if anything was saved, so the home screen knows to reload.
class RunTrackingScreen extends StatefulWidget {
  /// The day the run is filed under.
  final DateTime date;

  /// Supplies the label and emoji, and the `discipline_key` the session is
  /// created against — so a cycling discipline seeded as `logging_type =
  /// 'distance'` gets this screen without a line changing here.
  final Discipline discipline;

  /// A leg recovered from a crash, or null for a fresh start. When present the
  /// screen skips setup and picks that leg up where it stopped.
  final RunBackup? resume;

  const RunTrackingScreen({
    super.key,
    required this.date,
    required this.discipline,
    this.resume,
  });

  @override
  State<RunTrackingScreen> createState() => _RunTrackingScreenState();
}

/// The step of the flow currently on screen. See the class doc for why these are
/// phases of one widget rather than separate routes.
enum _Phase { setup, acquiring, countdown, running, summary }

class _RunTrackingScreenState extends State<RunTrackingScreen> {
  _Phase _phase = _Phase.setup;

  // ── The session ──────────────────────────────────────────────
  /// Created on the first Start and reused for every interval after. Null until
  /// then — an empty run claims no session.
  String? _sessionId;

  /// The legs already saved to Supabase this session, in order. Appended to as
  /// each finishes; loaded up front on a crash recovery.
  final List<DistanceInterval> _completed = [];

  /// The leg just finished — what the summary screen leads with.
  DistanceInterval? _justCompleted;

  // ── The current leg ──────────────────────────────────────────
  /// Target for the leg being set up / run, in metres. Null is a free run.
  double? _targetMeters;

  /// The last target the user picked, remembered so "Add another interval"
  /// pre-fills it rather than making them type the same 5 km again.
  double? _lastTarget;

  final _acc = DistanceAccumulator();
  double _distance = 0;

  StreamSubscription<GpsSample>? _gpsSub;

  /// Whether fixes are being counted. False during acquiring and the countdown,
  /// so the walk to the start line and the 3-2-1 don't end up in the distance.
  bool _tracking = false;

  // Elapsed time is measured against the wall clock, not a tick count: a timer
  // that misses beats while the app is backgrounded would under-report a run,
  // whereas the difference from a start instant is right the moment the app
  // comes back.
  DateTime? _legStartWall;
  int _baseElapsed = 0;
  int _elapsedSeconds = 0;

  Timer? _ticker;
  Timer? _backupTimer;

  // ── Acquiring state ──────────────────────────────────────────
  double? _lastAccuracy;

  // ── Setup inputs ─────────────────────────────────────────────
  final _targetCtrl = TextEditingController();
  bool _freeRun = false;

  /// What stopped the run from starting, so the setup screen can say the right
  /// thing. Null when nothing's wrong.
  LocationAccess? _accessError;

  bool _starting = false;

  /// Common targets, in metres — one tap instead of typing.
  static const _quickTargets = <double>[1000, 3000, 5000, 10000];

  @override
  void initState() {
    super.initState();
    final resume = widget.resume;
    if (resume != null) {
      // Straight into a recovered run: the session and its saved legs already
      // exist, so load them and re-acquire GPS rather than showing setup.
      _sessionId = resume.sessionId;
      _targetMeters = resume.targetMeters;
      _lastTarget = resume.lastTargetMeters ?? resume.targetMeters;
      _distance = resume.distanceMeters;
      _elapsedSeconds = resume.elapsedSeconds;
      _baseElapsed = resume.elapsedSeconds;
      _acc.restore(resume.distanceMeters);
      _loadCompleted();
      _beginAcquiring();
    }
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _ticker?.cancel();
    _backupTimer?.cancel();
    _targetCtrl.dispose();
    // Belt and braces: whatever route we leave by, the screen shouldn't stay lit
    // or leave a notification behind.
    WakelockPlus.disable();
    RunNotification.clear();
    super.dispose();
  }

  /// Pulls the session's already-saved legs in, for the summary list after a
  /// recovery. Best-effort: a run can be resumed without them, they just won't
  /// show in the prior-intervals list until the next reload.
  Future<void> _loadCompleted() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final legs = await RunService.getIntervals(id);
      if (!mounted) return;
      setState(() {
        _completed
          ..clear()
          ..addAll(legs);
      });
    } catch (_) {}
  }

  // ── Starting a leg ───────────────────────────────────────────

  double? _parseTargetMeters() {
    final km = double.tryParse(_targetCtrl.text.trim().replaceAll(',', '.'));
    if (km == null || km <= 0) return null;
    return km * 1000;
  }

  Future<void> _startLeg() async {
    final target = _freeRun ? null : _parseTargetMeters();
    if (!_freeRun && target == null) {
      _toast('How far are you aiming to run?');
      return;
    }

    setState(() {
      _starting = true;
      _accessError = null;
    });

    // GPS permission first: without it there's nothing to track, and the ask has
    // obvious context here — you just tapped Start on a run.
    final access = await LocationService.ensurePermission();
    if (access != LocationAccess.granted) {
      if (mounted) {
        setState(() {
          _starting = false;
          _accessError = access;
        });
      }
      return;
    }

    // The notification is a nicety, so its permission is requested but not
    // waited on: a denied notification must not stop a run.
    unawaited(RunNotification.ensurePermission());

    try {
      _sessionId ??= await _ensureSession();
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        _toast('Could not start the session: $e', error: true);
      }
      return;
    }

    _targetMeters = target;
    if (target != null) _lastTarget = target;

    _acc.reset();
    _distance = 0;
    _elapsedSeconds = 0;
    _baseElapsed = 0;

    await WakelockPlus.enable();
    unawaited(RunNotification.update(
      title: '${widget.discipline.label} — getting GPS',
      body: 'Waiting for a strong signal…',
    ));

    if (mounted) setState(() => _starting = false);
    _beginAcquiring();
  }

  /// Creates and activates the session, or reuses today's if one's already
  /// there. Mirrors the gym flow's "start means something even before you log".
  Future<String> _ensureSession() => WorkoutService.startSession(
        widget.date,
        _defaultName,
        discipline: widget.discipline.key,
      );

  String get _defaultName => widget.discipline.isGym ? 'Session' : 'Run';

  // ── Acquiring GPS ────────────────────────────────────────────

  void _beginAcquiring() {
    setState(() {
      _phase = _Phase.acquiring;
      _lastAccuracy = null;
    });
    _subscribe();
  }

  void _subscribe() {
    _gpsSub?.cancel();
    _gpsSub = LocationService.positionStream().listen(
      _onSample,
      onError: (Object e) {
        // A stream error mid-run isn't fatal — the OS often recovers on its own
        // — so it's surfaced quietly rather than tearing the run down.
        if (mounted && _phase == _Phase.acquiring) {
          _toast('GPS error: $e', error: true);
        }
      },
    );
  }

  void _onSample(GpsSample sample) {
    if (!mounted) return;

    if (_phase == _Phase.acquiring) {
      setState(() => _lastAccuracy = sample.accuracy);
      if (isUsableFix(sample)) {
        // A recovered run resumes straight away; a fresh one counts down first.
        if (widget.resume != null && !_tracking) {
          _startRunning(resumed: true);
        } else {
          _beginCountdown();
        }
      }
      return;
    }

    if (_phase == _Phase.running && _tracking) {
      final added = _acc.add(sample);
      if (added > 0 || _acc.hasBaseline) {
        setState(() => _distance = _acc.totalMeters);
        _maybeReachedTarget();
      }
      setState(() => _lastAccuracy = sample.accuracy);
    }
  }

  // ── Countdown ────────────────────────────────────────────────

  void _beginCountdown() {
    setState(() => _phase = _Phase.countdown);
  }

  // ── Running ──────────────────────────────────────────────────

  void _startRunning({bool resumed = false}) {
    setState(() => _phase = _Phase.running);
    _tracking = true;

    if (!resumed) {
      // Fresh baseline at GO, so distance is only ever counted from the line —
      // the fixes gathered while acquiring and counting down are discarded.
      _acc.reset();
      _distance = 0;
      _baseElapsed = 0;
    } else {
      // Recovered: keep the restored total, and don't invent a segment between
      // the last pre-crash fix and the first new one — restore() already dropped
      // the baseline for exactly this.
      _acc.restore(_distance);
    }

    _legStartWall = DateTime.now();
    _startTicker();
    _startBackupTimer();
    unawaited(_pushNotification());
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _legStartWall;
      if (start == null) return;
      final elapsed = _baseElapsed + DateTime.now().difference(start).inSeconds;
      setState(() => _elapsedSeconds = elapsed);
      // The notification only needs the coarse picture; refreshing it every
      // second would be churn for a line nobody's watching that closely.
      if (elapsed % 5 == 0) unawaited(_pushNotification());
    });
  }

  void _startBackupTimer() {
    _backupTimer?.cancel();
    _backupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final id = _sessionId;
      if (id == null || !_tracking) return;
      unawaited(RunBackupStore.save(RunBackup(
        sessionId: id,
        date: widget.date,
        disciplineKey: widget.discipline.key,
        targetMeters: _targetMeters,
        distanceMeters: _distance,
        elapsedSeconds: _elapsedSeconds,
        lastTargetMeters: _lastTarget,
      )));
    });
  }

  void _maybeReachedTarget() {
    final target = _targetMeters;
    if (target != null && _distance >= target) {
      _finishLeg(reachedTarget: true);
    }
  }

  // ── Finishing a leg ──────────────────────────────────────────

  Future<void> _finishLeg({required bool reachedTarget}) async {
    if (!_tracking) return; // stop tapped as the target lands — run once
    _tracking = false;

    _gpsSub?.cancel();
    _gpsSub = null;
    _ticker?.cancel();
    _backupTimer?.cancel();
    await WakelockPlus.disable();
    unawaited(_buzz());

    final duration = _elapsedSeconds;
    final distance = _distance;
    final target = _targetMeters;
    final id = _sessionId;

    if (id == null) return; // shouldn't happen — a leg only runs on a session

    // Persist immediately, retrying on failure: this leg exists nowhere else
    // yet, and dropping it silently because the network blinked would lose the
    // run you just did.
    String? intervalId;
    while (mounted) {
      try {
        intervalId = await RunService.addInterval(
          id,
          targetDistanceMeters: target,
          actualDistanceMeters: distance,
          durationSeconds: duration,
        );
        break;
      } catch (e) {
        final retry = await _confirmRetrySave(e);
        if (!retry) break; // gave up — the leg is lost, but by choice
      }
    }

    if (intervalId != null) {
      _completed.add(DistanceInterval(
        intervalId: intervalId,
        sessionId: id,
        targetDistanceMeters: target,
        actualDistanceMeters: distance,
        durationSeconds: duration,
        sortOrder: _completed.length + 1,
      ));
      _justCompleted = _completed.last;
    }

    // The leg has a home now (or was abandoned) — nothing left to recover.
    await RunBackupStore.clear();

    unawaited(RunNotification.update(
      title: '${widget.discipline.label} in progress',
      body: '${_completed.length} '
          'interval${_completed.length == 1 ? '' : 's'} · '
          '${formatDistance(_sessionDistance)}',
    ));

    if (mounted) setState(() => _phase = _Phase.summary);
  }

  double get _sessionDistance =>
      _completed.fold(0.0, (sum, i) => sum + i.actualDistanceMeters);

  Future<bool> _confirmRetrySave(Object error) async {
    final lt = context.lt;
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text('Could not save this interval',
            style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary)),
        content: Text(
          'Your run is finished, but saving it failed:\n\n$error',
          style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Discard leg', style: TextStyle(color: lt.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retry',
                style: TextStyle(color: LiftrColors.accentDark)),
          ),
        ],
      ),
    );
    return retry ?? false;
  }

  Future<void> _buzz() async {
    try {
      final has = await Vibration.hasVibrator();
      if (has == true) {
        // A distinct triple-pulse — long enough to feel through a sleeve without
        // watching the screen, which is the whole point of it.
        Vibration.vibrate(pattern: const [0, 300, 150, 300, 150, 300]);
      }
    } catch (_) {}
  }

  Future<void> _pushNotification() {
    final label = _targetMeters == null
        ? 'Free run'
        : '${formatDistance(remainingMeters(_targetMeters!, _distance))} to go';
    return RunNotification.update(
      title: '${widget.discipline.label} in progress',
      body: '$label · ${formatDuration(_elapsedSeconds)}',
    );
  }

  // ── After a leg ──────────────────────────────────────────────

  /// Back to setup for the next interval, remembering the last target.
  void _addAnother() {
    setState(() {
      _justCompleted = null;
      _targetMeters = null;
      _distance = 0;
      _elapsedSeconds = 0;
      _lastAccuracy = null;
      if (_lastTarget != null && !_freeRun) {
        _targetCtrl.text = _kmText(_lastTarget!);
      }
      _phase = _Phase.setup;
    });
  }

  Future<void> _endSession() async {
    final id = _sessionId;
    if (id == null) return;

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => RunSaveScreen(
          sessionId: id,
          date: widget.date,
          discipline: widget.discipline,
        ),
      ),
    );

    // Only a completed save or discard ends the run. Backing out of the save
    // screen returns null and drops us back on the summary, still in it.
    if (result == 'saved' || result == 'discarded') {
      await RunNotification.clear();
      if (mounted) Navigator.pop(context, result == 'saved');
    }
  }

  // ── Leaving mid-run ──────────────────────────────────────────

  Future<void> _abandon() async {
    _tracking = false;
    _gpsSub?.cancel();
    _ticker?.cancel();
    _backupTimer?.cancel();
    await WakelockPlus.disable();
    await RunBackupStore.clear();
    await RunNotification.clear();

    final id = _sessionId;
    if (id != null) {
      try {
        if (_completed.isEmpty) {
          // Nothing was ever saved into it — delete the empty session rather
          // than leaving a hollow row that shows as a run with no runs.
          await RunService.discardSession(id);
        } else {
          // Keep the legs that did save; just stop being "in" the session.
          await WorkoutService.endSession(id);
        }
      } catch (_) {}
    }

    if (mounted) Navigator.pop(context, _completed.isNotEmpty);
  }

  Future<bool> _confirmAbandon() async {
    final lt = context.lt;
    final live = _phase == _Phase.running || _phase == _Phase.acquiring;
    final saved = _completed.isNotEmpty;

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text(
          live ? 'Stop and leave this run?' : 'Leave this session?',
          style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary),
        ),
        content: Text(
          live
              ? 'This interval isn\'t saved yet and will be lost.'
                  '${saved ? ' Your earlier intervals are kept.' : ''}'
              : saved
                  ? 'Your saved intervals are kept — you just won\'t be in the '
                      'session any more.'
                  : 'Nothing has been saved, so the session is thrown away.',
          style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep running', style: TextStyle(color: lt.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Leave', style: TextStyle(color: lt.danger)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  // ── Build ────────────────────────────────────────────────────

  bool get _canPopFreely =>
      _phase == _Phase.setup && _completed.isEmpty && _sessionId == null;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPopFreely,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmAbandon()) await _abandon();
      },
      child: switch (_phase) {
        _Phase.setup => _SetupView(
            discipline: widget.discipline,
            targetCtrl: _targetCtrl,
            freeRun: _freeRun,
            quickTargets: _quickTargets,
            starting: _starting,
            accessError: _accessError,
            intervalNumber: _completed.length + 1,
            onFreeRunChanged: (v) => setState(() => _freeRun = v),
            onQuickTarget: (m) => setState(() {
              _freeRun = false;
              _targetCtrl.text = _kmText(m);
            }),
            onStart: _startLeg,
            onBack: () => Navigator.maybePop(context),
            onFixSettings: _handleAccessError,
          ),
        _Phase.acquiring => _AcquiringView(
            accuracy: _lastAccuracy,
            rejected: _acc.rejectedCount,
            onCancel: () async {
              if (await _confirmAbandon()) await _abandon();
            },
          ),
        _Phase.countdown => _CountdownView(onDone: _startRunning),
        _Phase.running => _RunningView(
            targetMeters: _targetMeters,
            distance: _distance,
            elapsedSeconds: _elapsedSeconds,
            onStop: () => _finishLeg(reachedTarget: false),
          ),
        _Phase.summary => _SummaryView(
            discipline: widget.discipline,
            justCompleted: _justCompleted,
            all: _completed,
            onAddAnother: _addAnother,
            onEndSession: _endSession,
          ),
      },
    );
  }

  Future<void> _handleAccessError() async {
    switch (_accessError) {
      case LocationAccess.deniedForever:
        await LocationService.openSettings();
        break;
      case LocationAccess.serviceDisabled:
        await LocationService.openLocationSettings();
        break;
      default:
        // Plain denied — just ask again by trying to start.
        await _startLeg();
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

  static String _kmText(double meters) {
    final km = meters / 1000;
    return km == km.roundToDouble()
        ? km.toStringAsFixed(0)
        : km.toStringAsFixed(2);
  }
}

// ══ Setup ═══════════════════════════════════════════════════════
/// Target distance (or free run) and the Start button — the one screen between
/// picking Running and being out on it.
class _SetupView extends StatelessWidget {
  final Discipline discipline;
  final TextEditingController targetCtrl;
  final bool freeRun;
  final List<double> quickTargets;
  final bool starting;
  final LocationAccess? accessError;
  final int intervalNumber;
  final ValueChanged<bool> onFreeRunChanged;
  final ValueChanged<double> onQuickTarget;
  final VoidCallback onStart;
  final VoidCallback onBack;
  final VoidCallback onFixSettings;

  const _SetupView({
    required this.discipline,
    required this.targetCtrl,
    required this.freeRun,
    required this.quickTargets,
    required this.starting,
    required this.accessError,
    required this.intervalNumber,
    required this.onFreeRunChanged,
    required this.onQuickTarget,
    required this.onStart,
    required this.onBack,
    required this.onFixSettings,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: onBack,
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${discipline.emoji}  ${discipline.label}',
                          style: Theme.of(context).textTheme.displaySmall),
                      if (intervalNumber > 1)
                        Text('Interval $intervalNumber',
                            style: TextStyle(
                                fontSize: LiftrType.x11, color: lt.textMuted)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: LiftrSpacing.x28),

              Text(
                freeRun ? 'Free run' : 'Target distance',
                style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
              ),
              const SizedBox(height: LiftrSpacing.x10),

              if (!freeRun) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: targetCtrl,
                        autofocus: false,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                          fontFamily: 'DMSerifDisplay',
                          fontSize: 56,
                          color: LiftrColors.accent,
                        ),
                        decoration: InputDecoration(
                          hintText: '5',
                          hintStyle: TextStyle(
                              fontFamily: 'DMSerifDisplay',
                              fontSize: 56,
                              color: lt.textDim),
                          border: InputBorder.none,
                          isDense: true,
                          fillColor: Colors.transparent,
                          filled: true,
                        ),
                      ),
                    ),
                    Text('km',
                        style:
                            TextStyle(fontSize: LiftrType.x18, color: lt.textMuted)),
                  ],
                ),
                const SizedBox(height: LiftrSpacing.x16),
                Wrap(
                  spacing: LiftrSpacing.x8,
                  children: [
                    for (final m in quickTargets)
                      _QuickChip(
                        label: '${(m / 1000).toStringAsFixed(0)} km',
                        onTap: () => onQuickTarget(m),
                      ),
                  ],
                ),
              ] else
                Text(
                  'No target — run until you stop. Distance and time are still '
                  'tracked.',
                  style: TextStyle(
                      fontSize: LiftrType.x13,
                      color: lt.textSecondary,
                      height: 1.5),
                ),

              const SizedBox(height: LiftrSpacing.x24),
              _FreeRunToggle(value: freeRun, onChanged: onFreeRunChanged),

              if (accessError != null) ...[
                const SizedBox(height: LiftrSpacing.x20),
                _AccessErrorBanner(access: accessError!, onFix: onFixSettings),
              ],

              const Spacer(),
              ElevatedButton(
                onPressed: starting ? null : onStart,
                child: starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: LiftrColors.accentText),
                      )
                    : const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x8),
        decoration: BoxDecoration(
          color: lt.card,
          border: Border.all(color: lt.border, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.panel),
        ),
        child: Text(label,
            style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary)),
      ),
    );
  }
}

class _FreeRunToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _FreeRunToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? LiftrColors.accent : lt.card,
              border: Border.all(
                  color: value ? LiftrColors.accent : lt.border,
                  width: LiftrBorders.hairline),
              borderRadius: BorderRadius.circular(LiftrRadii.panel),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value ? LiftrColors.accentText : lt.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: LiftrSpacing.x12),
          Text('Free run (no target)',
              style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary)),
        ],
      ),
    );
  }
}

class _AccessErrorBanner extends StatelessWidget {
  final LocationAccess access;
  final VoidCallback onFix;
  const _AccessErrorBanner({required this.access, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final (title, body, action) = switch (access) {
      LocationAccess.serviceDisabled => (
          'Location is off',
          'Turn on location services to track a run.',
          'Open settings',
        ),
      LocationAccess.deniedForever => (
          'Location permission blocked',
          'Liftr needs location to measure your run. Grant it in Settings.',
          'Open settings',
        ),
      _ => (
          'Location needed',
          'Liftr needs location to measure your run.',
          'Allow location',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(LiftrSpacing.x14),
      decoration: BoxDecoration(
        color: lt.card,
        border: Border.all(color: lt.danger, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: LiftrType.x14,
                  fontWeight: FontWeight.w600,
                  color: lt.textPrimary)),
          const SizedBox(height: LiftrSpacing.x4),
          Text(body,
              style:
                  TextStyle(fontSize: LiftrType.x12, color: lt.textSecondary)),
          const SizedBox(height: LiftrSpacing.x10),
          GestureDetector(
            onTap: onFix,
            child: Text(action,
                style: const TextStyle(
                    fontSize: LiftrType.x13,
                    fontWeight: FontWeight.w600,
                    color: LiftrColors.accentDark)),
          ),
        ],
      ),
    );
  }
}

// ══ Acquiring ═══════════════════════════════════════════════════
/// The wait for a lock good enough to trust — GPS pulses until accuracy drops
/// under the threshold the accumulator will accept.
class _AcquiringView extends StatefulWidget {
  final double? accuracy;
  final int rejected;
  final VoidCallback onCancel;

  const _AcquiringView({
    required this.accuracy,
    required this.rejected,
    required this.onCancel,
  });

  @override
  State<_AcquiringView> createState() => _AcquiringViewState();
}

class _AcquiringViewState extends State<_AcquiringView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final acc = widget.accuracy;
    // Once we've seen a fix but it's not good enough for a while, say so rather
    // than spinning silently — "it's working, just weak" is the reassurance.
    final struggling = acc != null && acc > kMaxAccuracyMeters;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(LiftrSpacing.x24),
          child: Column(
            children: [
              const Spacer(),
              ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.1).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: lt.accentBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: LiftrColors.accent, width: LiftrBorders.thin),
                  ),
                  child: const Icon(Icons.gps_fixed,
                      size: 40, color: LiftrColors.accentDark),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x28),
              Text('Getting a GPS lock',
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: LiftrSpacing.x8),
              Text(
                acc == null
                    ? 'Searching for satellites…'
                    : struggling
                        ? 'Accuracy ±${acc.round()} m — need ±${kMaxAccuracyMeters.round()} m. '
                            'Move to open sky.'
                        : 'Locked. Starting…',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: LiftrType.x13,
                    color: lt.textSecondary,
                    height: 1.5),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onCancel,
                child: Text('Cancel',
                    style: TextStyle(color: lt.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══ Countdown ═══════════════════════════════════════════════════
/// 3 · 2 · 1 · GO, each scaling in, then a hand-off to running.
class _CountdownView extends StatefulWidget {
  final VoidCallback onDone;
  const _CountdownView({required this.onDone});

  @override
  State<_CountdownView> createState() => _CountdownViewState();
}

class _CountdownViewState extends State<_CountdownView> {
  /// 3 → 2 → 1 → 0 (GO). Stepped every [_step].
  int _count = 3;
  Timer? _timer;
  static const _step = Duration(milliseconds: 850);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_step, (_) {
      if (_count == 0) {
        _timer?.cancel();
        widget.onDone();
        return;
      }
      setState(() => _count--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _count == 0 ? 'GO' : '$_count';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween(begin: 0.4, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Text(
            label,
            key: ValueKey(label),
            style: TextStyle(
              fontFamily: 'DMSerifDisplay',
              fontSize: label == 'GO' ? 120 : 160,
              color: label == 'GO' ? LiftrColors.accent : Colors.white,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// ══ Running ═════════════════════════════════════════════════════
/// The live run: pure black, one enormous number, and a stop button. Kept
/// deliberately still — only the number changes — so an OLED screen draws almost
/// nothing for the length of the run.
class _RunningView extends StatelessWidget {
  final double? targetMeters;
  final double distance;
  final int elapsedSeconds;
  final VoidCallback onStop;

  const _RunningView({
    required this.targetMeters,
    required this.distance,
    required this.elapsedSeconds,
    required this.onStop,
  });

  /// Base colour of the big number, warming to lime as the last 50 m tick down.
  static const _idle = Color(0xFFF5F5F0);

  @override
  Widget build(BuildContext context) {
    final target = targetMeters;
    final shown = target == null ? distance : remainingMeters(target, distance);

    final (big, unit) = _split(shown);
    final label = target == null
        ? 'COVERED'
        : shown <= 0
            ? 'TARGET REACHED'
            : 'TO GO';

    final color = _numberColor(target, distance);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // The small line up top: elapsed, and pace once there's enough
            // distance to make it meaningful.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(elapsedSeconds),
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: LiftrType.x16,
                          color: Color(0xFF9A9AA4))),
                  Text(formatPace(distance, elapsedSeconds),
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: LiftrType.x16,
                          color: Color(0xFF9A9AA4))),
                ],
              ),
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                big,
                style: TextStyle(
                  fontFamily: 'DMSerifDisplay',
                  fontSize: 140,
                  height: 1,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: LiftrSpacing.x8),
            Text(
              '$unit · $label',
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: LiftrType.x14,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
                color: Color(0xFF5A5A62),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: GestureDetector(
                onTap: onStop,
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF15151A),
                    border: Border.all(
                        color: const Color(0xFF2E2E34),
                        width: LiftrBorders.thin),
                    borderRadius: BorderRadius.circular(LiftrRadii.button),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop, color: LiftrColors.danger, size: 22),
                        SizedBox(width: LiftrSpacing.x8),
                        Text('Stop',
                            style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: LiftrType.x16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE2E2E6))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static (String, String) _split(double meters) {
    if (meters < 1000) return (meters.round().toString(), 'METRES');
    return ((meters / 1000).toStringAsFixed(2), 'KILOMETRES');
  }

  static Color _numberColor(double? target, double distance) {
    if (target == null) return LiftrColors.accent;
    final remaining = remainingMeters(target, distance);
    if (remaining > 50) return _idle;
    final t = ((50 - remaining) / 50).clamp(0.0, 1.0);
    return Color.lerp(_idle, LiftrColors.accent, t)!;
  }
}

// ══ Interval summary ════════════════════════════════════════════
/// What you just did, the legs before it, and the fork: go again, or wrap up.
class _SummaryView extends StatelessWidget {
  final Discipline discipline;
  final DistanceInterval? justCompleted;
  final List<DistanceInterval> all;
  final VoidCallback onAddAnother;
  final VoidCallback onEndSession;

  const _SummaryView({
    required this.discipline,
    required this.justCompleted,
    required this.all,
    required this.onAddAnother,
    required this.onEndSession,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final done = justCompleted;
    // The legs before this one, newest of the earlier ones first.
    final prior = all.where((i) => i.intervalId != done?.intervalId).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Interval done',
                  style: Theme.of(context).textTheme.displayMedium),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                children: [
                  if (done != null) _JustCompletedCard(interval: done),
                  if (prior.isNotEmpty) ...[
                    const SizedBox(height: LiftrSpacing.x20),
                    Text('EARLIER THIS SESSION',
                        style: TextStyle(
                            fontSize: LiftrType.x11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.08,
                            color: lt.textMuted)),
                    const SizedBox(height: LiftrSpacing.x8),
                    for (final i in prior) _PriorRow(interval: i),
                    const SizedBox(height: LiftrSpacing.x12),
                    _SessionTotalsRow(intervals: all),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: onAddAnother,
                    child: const Text('Add another interval'),
                  ),
                  const SizedBox(height: LiftrSpacing.x10),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: onEndSession,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: lt.border, width: LiftrBorders.thin),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(LiftrRadii.button)),
                      ),
                      child: Text('End session',
                          style: TextStyle(
                              fontSize: LiftrType.x15,
                              fontWeight: FontWeight.w600,
                              color: lt.textPrimary)),
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

class _JustCompletedCard extends StatelessWidget {
  final DistanceInterval interval;
  const _JustCompletedCard({required this.interval});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final short = interval.targetDistanceMeters != null && !interval.reachedTarget;

    return Container(
      padding: const EdgeInsets.all(LiftrSpacing.x20),
      decoration: BoxDecoration(
        color: lt.accentBg,
        border: Border.all(color: LiftrColors.accent, width: LiftrBorders.thin),
        borderRadius: BorderRadius.circular(LiftrRadii.sheet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            formatDistance(interval.actualDistanceMeters),
            style: const TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontSize: 52,
                color: LiftrColors.accentDark),
          ),
          const SizedBox(height: LiftrSpacing.x4),
          Text(
            short
                ? 'Stopped short of ${formatDistance(interval.targetDistanceMeters!)}'
                : interval.isFreeRun
                    ? 'Free run'
                    : 'Target reached',
            style: TextStyle(fontSize: LiftrType.x12, color: lt.accentMid),
          ),
          const SizedBox(height: LiftrSpacing.x16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(
                  label: 'TIME',
                  value: formatDuration(interval.durationSeconds)),
              _Stat(
                  label: 'PACE',
                  value: formatPace(
                      interval.actualDistanceMeters, interval.durationSeconds)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: LiftrType.x18,
                fontWeight: FontWeight.w600,
                color: lt.textPrimary)),
        const SizedBox(height: LiftrSpacing.x2),
        Text(label,
            style: TextStyle(
                fontSize: LiftrType.x10,
                letterSpacing: 0.08,
                color: lt.textMuted)),
      ],
    );
  }
}

class _PriorRow extends StatelessWidget {
  final DistanceInterval interval;
  const _PriorRow({required this.interval});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final parts = [
      formatDistance(interval.actualDistanceMeters),
      formatDuration(interval.durationSeconds),
      formatPace(interval.actualDistanceMeters, interval.durationSeconds),
    ].where((p) => p.isNotEmpty && p != '—').join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LiftrSpacing.x6),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lt.card,
              borderRadius: BorderRadius.circular(LiftrRadii.control),
            ),
            child: Text('${interval.sortOrder}',
                style: TextStyle(
                    fontSize: LiftrType.x12,
                    fontWeight: FontWeight.w600,
                    color: lt.textSecondary)),
          ),
          const SizedBox(width: LiftrSpacing.x10),
          Expanded(
            child: Text(parts,
                style:
                    TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _SessionTotalsRow extends StatelessWidget {
  final List<DistanceInterval> intervals;
  const _SessionTotalsRow({required this.intervals});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final totals = RunTotals.from(intervals);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x12),
      decoration: BoxDecoration(
        color: lt.card,
        border: Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.field),
      ),
      child: Row(
        children: [
          Text('Session total',
              style: TextStyle(fontSize: LiftrType.x12, color: lt.textSecondary)),
          const Spacer(),
          Text(
            '${formatDistance(totals.distanceMeters)}  ·  '
            '${formatDuration(totals.durationSeconds)}',
            style: TextStyle(
                fontSize: LiftrType.x13,
                fontWeight: FontWeight.w600,
                color: lt.textPrimary),
          ),
        ],
      ),
    );
  }
}
