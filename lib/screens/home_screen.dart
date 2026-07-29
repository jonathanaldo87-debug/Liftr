import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/prefs.dart';
import '../services/run_backup.dart';
import '../services/routine_service.dart';
import '../services/run_service.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../utils/run_math.dart';
import 'add_exercise_screen.dart';
import 'add_run_screen.dart';
import 'exercise_detail_screen.dart';
import 'run_tracking_screen.dart';
import 'log_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';
import 'routines_screen.dart';

/// Shell for the four tabs. The bottom bar used to move its own highlight and
/// nothing else — every tab but Home showed the Home screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;
  DateTime _selectedDate = DateTime.now();

  /// Bumped to force the Home tab to rebuild from scratch (and so refetch) when
  /// you come back to it or jump to a date from the Log tab.
  int _homeEpoch = 0;

  /// The unguarded sign-out. Only ever called after [confirmAndSignOut] has had
  /// its say, which is what stops a guest wiping their history by accident.
  Future<void> _signOut() async {
    await AuthService.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _openDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _navIndex = 0;
      _homeEpoch++;
    });
  }

  Widget get _tab {
    switch (_navIndex) {
      case 1:
        return LogTab(onOpenDate: _openDate);
      case 2:
        return const ProgressTab();
      case 3:
        return ProfileTab(onSignOut: _signOut);
      default:
        return _TodayTab(
          key: ValueKey('${_selectedDate.toIso8601String()}#$_homeEpoch'),
          initialDate: _selectedDate,
          onDateChanged: (d) => _selectedDate = d,
          // Guarded: the avatar menu here can sign out too, and a guest would
          // lose everything without the warning.
          onSignOut: () => confirmAndSignOut(context, _signOut),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Each tab is built fresh on selection rather than kept alive in an
      // IndexedStack, so switching back to it always shows current data.
      body: _tab,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() {
          // Re-tapping Home refreshes it.
          if (i == 0 && _navIndex == 0) _homeEpoch++;
          _navIndex = i;
        }),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.list_outlined),
              activeIcon: Icon(Icons.list),
              label: 'Log'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: 'Progress'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}

// ── Home tab ──────────────────────────────────────────────────
class _TodayTab extends StatefulWidget {
  final DateTime initialDate;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onSignOut;

  const _TodayTab({
    super.key,
    required this.initialDate,
    required this.onDateChanged,
    required this.onSignOut,
  });

  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  late DateTime _selectedDate = widget.initialDate;

  /// The disciplines this user trains, in catalog order — the chips on offer.
  List<Discipline> _disciplines = [];

  /// The chip in effect. Null means "All": show every discipline's session for
  /// the day.
  String? _selectedDiscipline;

  /// A day now holds up to one session per discipline (a gym workout AND a run
  /// are two rows), so this can no longer be a single session.
  List<WorkoutSessions> _sessions = [];

  /// Exercises keyed by session id. Only gym sessions have any — it's the one
  /// discipline with a child table so far.
  Map<String, List<WorkoutExercises>> _exercisesBySession = {};

  /// Intervals for the day's distance sessions, keyed the same way.
  Map<String, List<DistanceInterval>> _runsBySession = {};

  /// `yyyy-MM-dd` of every day that has a session — the calendar dots. The strip
  /// used to hardcode `hasWorkout: (_) => false`, so no dot ever appeared.
  Set<String> _sessionDates = {};

  /// Which routine runs on each weekday, 1..7.
  ///
  /// Fetched once rather than per date: it's seven rows and it doesn't change as
  /// you page the calendar, so looking it up by weekday costs nothing while a
  /// per-date query would put a round trip behind every tap on the strip.
  WeeklySchedule _schedule = {};

  /// The routine scheduled for the day being looked at, if any. Absent means a
  /// rest day — that's all "rest" has ever meant here.
  Routine? get _scheduledRoutine => _schedule[_selectedDate.weekday];

  /// Whether any routine exists yet.
  ///
  /// Gates the one-time nudge in the empty state. Routines otherwise only
  /// advertise themselves to people already using them — the fill prompt needs
  /// a routine to exist before it can appear, so without this the feature is
  /// invisible to exactly the person who'd benefit most.
  ///
  /// Starts true so the nudge can't flash on screen during the first load and
  /// then vanish.
  bool _hasRoutines = true;

  /// A past session temporarily unlocked for editing, by session id.
  ///
  /// Deliberately transient UI state, never persisted: the default for a day
  /// that's already gone is read-only, so a stray tap can't rewrite last week's
  /// workout. Changing the date or the filter drops it — you've navigated away,
  /// so the unlock has served its purpose.
  String? _editableSessionId;

  bool _isLoading = false;

  /// Whether [s] accepts changes right now.
  ///
  /// Today is live, the past is history until you unlock it, and a day that
  /// hasn't happened takes nothing at all. Keyed on the day rather than on any
  /// state of the session, which is what the run card always did — the gym card
  /// used to key off `is_active` instead, and that flag is gone.
  ///
  /// Note this answers for a *day*, so it's true on today even before a session
  /// exists. Callers that need a row to change still have to check they have
  /// one.
  bool _canEdit(WorkoutSessions? s) {
    if (isFutureDay(_selectedDate)) return false;
    if (_isToday(_selectedDate)) return true;
    final id = s?.sessionId;
    return id != null && id == _editableSessionId;
  }

  /// Edit ⇄ Cancel on a past session.
  ///
  /// Today never gets here — it's always editable, so there'd be nothing to
  /// toggle.
  void _toggleEdit(WorkoutSessions s) => setState(() {
        _editableSessionId =
            _editableSessionId == s.sessionId ? null : s.sessionId;
      });

  /// The EDIT ⇄ DONE handler for a card, or null when there's nothing to
  /// toggle: today is already open, a future day takes nothing, and a day with
  /// no session has nothing to unlock.
  ///
  /// One rule for both cards now. They used to disagree — the gym card hid the
  /// chip for the active session, the run card hid it for today — because they
  /// were locking on different things.
  VoidCallback? _toggleFor(WorkoutSessions? s) {
    if (s == null || !isPastDay(_selectedDate)) return null;
    return () => _toggleEdit(s);
  }

  /// Re-locks whatever was unlocked. Called on any navigation away from the
  /// thing you unlocked.
  void _relock() => _editableSessionId = null;

  /// Whether the "you have an unfinished run" prompt has already had its one
  /// shot this mount. Guards against it reappearing on every rebuild.
  bool _recoveryChecked = false;

  @override
  void initState() {
    super.initState();
    _loadDisciplines();
    _loadSchedule();
    _loadData();
    // After the first frame, once a context is safely available for a dialog.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeOfferRecovery());
  }

  /// Separate from [_loadData]: the discipline list doesn't change when you page
  /// the calendar, so it shouldn't be refetched on every date tap.
  Future<void> _loadDisciplines() async {
    final all = await WorkoutService.getDisciplines();
    if (!mounted) return;

    final enabled = Prefs.enabledDisciplines;
    setState(() {
      _disciplines = all.where((d) => enabled.contains(d.key)).toList();
      // If the saved list somehow matches nothing in the catalog, offering no
      // chips at all would strand the user — fall back to everything.
      if (_disciplines.isEmpty) _disciplines = all;
    });
  }

  /// Separate from [_loadData] for the same reason as the disciplines: the week
  /// is the same week whichever day you're looking at.
  ///
  /// Editing routines happens in Profile, and switching tabs rebuilds this one
  /// from scratch, so there's no staleness to guard against here.
  Future<void> _loadSchedule() async {
    try {
      final schedule = await RoutineService.getSchedule();
      final hasAny = schedule.isNotEmpty || await RoutineService.hasAny();
      if (mounted) {
        setState(() {
          _schedule = schedule;
          _hasRoutines = hasAny;
        });
      }
    } catch (_) {
      // A schedule that won't load costs you the fill prompt and nothing else —
      // every other way of logging still works, so this stays quiet rather than
      // throwing a snackbar over a screen that's otherwise fine.
    }
  }

  /// The gym session for the day, if there is one.
  WorkoutSessions? get _gymSession {
    for (final s in _sessions) {
      if (s.discipline == Discipline.gymKey) return s;
    }
    return null;
  }

  List<WorkoutExercises> _exercisesFor(WorkoutSessions? s) =>
      _exercisesBySession[s?.sessionId] ?? const [];

  List<DistanceInterval> _intervalsFor(WorkoutSessions? s) =>
      _runsBySession[s?.sessionId] ?? const [];

  /// The day's session for a discipline, if there is one.
  WorkoutSessions? _sessionFor(String disciplineKey) {
    for (final s in _sessions) {
      if (s.discipline == disciplineKey) return s;
    }
    return null;
  }

  /// How a discipline logs — 'sets', 'distance', or 'none'.
  ///
  /// Falls back to 'none' for a discipline the catalog hasn't loaded yet, which
  /// renders as "nothing to log into" rather than guessing at a UI that can't
  /// save anywhere.
  String _lookupLogging(String key) {
    for (final d in _disciplines) {
      if (d.key == key) return d.loggingType;
    }
    return Discipline.loggingNone;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await WorkoutService.getSessionsForDate(_selectedDate);

      // Each discipline's children, loaded by what that discipline logs rather
      // than by its key — migration 013 gave disciplines a logging_type exactly
      // so this doesn't become a growing chain of `if (key == ...)`.
      final byId = <String, List<WorkoutExercises>>{};
      final runsById = <String, List<DistanceInterval>>{};
      for (final s in sessions) {
        final id = s.sessionId;
        if (id == null) continue;

        final logging = _lookupLogging(s.discipline);
        if (logging == Discipline.loggingSets) {
          byId[id] = await WorkoutService.getWorkoutExercises(id);
        } else if (logging == Discipline.loggingDistance) {
          runsById[id] = await RunService.getIntervals(id);
        }
      }

      // A generous window around the selected day so paging the calendar left
      // or right doesn't need another round trip.
      final dates = await WorkoutService.getSessionDates(
        _selectedDate.subtract(const Duration(days: 60)),
        _selectedDate.add(const Duration(days: 60)),
      );

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _exercisesBySession = byId;
          _runsBySession = runsById;
          _sessionDates = dates;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not load this day: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDateSelected(DateTime d) {
    setState(() {
      _selectedDate = d;
      _relock(); // navigated to another day — the unlock doesn't follow you
    });
    widget.onDateChanged(d);
    _loadData();
  }

  bool _hasWorkout(DateTime d) => _sessionDates.contains(_key(d));

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The discipline the primary button will add to, or null when that's still
  /// an open question and it has to ask.
  ///
  /// The selected chip decides it. That reverses an earlier rule here — "the
  /// chips filter what you're looking at; picking a filter must never decide
  /// what a tap creates" — which was right when the button was "Start session",
  /// a day-level act the filter had no business steering. It isn't any more:
  /// the button says "Add exercise" while the gym card is on screen, so the
  /// label states outright what it will do and there's nothing left to be
  /// surprised by. On "All" it genuinely is an open question, hence the picker.
  ///
  /// One discipline configured means there's nothing to choose between, whatever
  /// the chip says.
  Discipline? get _target {
    if (_disciplines.length == 1) return _disciplines.first;
    final key = _selectedDiscipline;
    if (key == null) return null;
    return _disciplineFor(key);
  }

  /// The only way anything gets logged: one button, one verb, always in the
  /// same place.
  ///
  /// There's no session to start or end any more — [_addExercise] and the run
  /// flows create the day's session on save, so "add" is the whole vocabulary.
  Future<void> _logSomething() async {
    if (_disciplines.isEmpty) return;

    // Nothing to log on a day that hasn't happened. The button is hidden for
    // one, so this only catches a tap that raced the date changing.
    if (isFutureDay(_selectedDate)) return;

    final chosen = _target ?? await _pickDiscipline();
    if (chosen == null || !mounted) return;

    await _openDiscipline(chosen);
  }

  /// What the primary button says.
  ///
  /// Names the act, not the bookkeeping: on the gym chip it's "Add exercise"
  /// because that is precisely what the tap does.
  String get _addLabel {
    final d = _target;
    if (d == null) return 'Log something';
    if (d.logsDistance) return 'Add a run';
    if (d.isGym) return 'Add exercise';
    return 'Add ${d.label.toLowerCase()}';
  }

  /// Whether anything can be added to what's on screen right now.
  bool get _canLogHere {
    if (isFutureDay(_selectedDate)) return false;
    // A discipline whose logging screen doesn't exist yet has nothing to add
    // to; its card says as much, and a button promising otherwise would lie.
    final d = _target;
    return d == null || d.logsDistance || d.isGym;
  }

  /// What an empty day suggests you do — which depends on whether there's a
  /// button below to do it with.
  ///
  /// Ends mid-sentence when [_routineNudge] is live: [_EmptyState] finishes it
  /// with the tappable half, so the two read as one sentence rather than a hint
  /// with an advert bolted underneath.
  String get _emptyHint {
    if (isFutureDay(_selectedDate)) return kNotYetHint;
    if (!_canLogHere) return 'Nothing logged on this day.';
    if (_routineNudge != null) return 'Nothing logged.\nTap "$_addLabel" below';
    return 'Nothing logged.\nTap "$_addLabel" below to put something in.';
  }

  /// The one-time nudge toward routines, or null when it shouldn't show.
  ///
  /// Gone the moment you have a routine — it exists to close the gap where the
  /// feature is invisible to anyone not already using it, and past that point
  /// it would just be nagging. Also gone where there's no way to log anyway,
  /// since the sentence it completes wouldn't be there either.
  VoidCallback? get _routineNudge =>
      (_hasRoutines || !_canLogHere) ? null : _openRoutines;

  /// Opens the routines screen and picks up anything set up while in there.
  Future<void> _openRoutines() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RoutinesScreen()),
    );
    if (mounted) await _loadSchedule();
  }

  Future<Discipline?> _pickDiscipline() {
    final lt = context.lt;
    return showModalBottomSheet<Discipline>(
      context: context,
      backgroundColor: lt.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LiftrRadii.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: LiftrSpacing.x18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
              child: Text('What do you want to log?',
                  style: Theme.of(ctx).textTheme.displaySmall),
            ),
            const SizedBox(height: LiftrSpacing.x12),
            for (final d in _disciplines)
              ListTile(
                leading: Text(d.emoji,
                    style: const TextStyle(fontSize: LiftrType.x22)),
                title: Text(d.label,
                    style: TextStyle(
                        fontSize: LiftrType.x15, color: lt.textPrimary)),
                subtitle: d.description.isEmpty
                    ? null
                    : Text(d.description,
                        style: TextStyle(
                            fontSize: LiftrType.x12, color: lt.textMuted)),
                onTap: () => Navigator.pop(ctx, d),
              ),
            const SizedBox(height: LiftrSpacing.x12),
          ],
        ),
      ),
    );
  }

  /// Routes to a discipline's own way of logging.
  ///
  /// Nothing is created here. Every route below writes the day's session when
  /// it saves, which is what makes backing out of any of them free — this used
  /// to create and activate the gym session up front so that "start" meant
  /// something on its own, and left a hollow row behind whenever you changed
  /// your mind.
  Future<void> _openDiscipline(Discipline d) async {
    // Move the lens onto what we're adding to, so the result lands in view.
    setState(() => _selectedDiscipline = d.key);

    if (d.logsDistance) {
      await _addDistance(d);
      return;
    }

    // Seeded, but with no logging screen yet. Moving the filter is the whole of
    // what can be done, and the card there explains itself.
    if (!d.isGym) return;

    await _addExercise();
  }

  /// A distance discipline has two ways in, and only today has both: follow one
  /// live, or write down one you've already done. A day that's gone can only be
  /// the second, so it goes straight there rather than offering to track a run
  /// that's already over.
  Future<void> _addDistance(Discipline d) async {
    if (!_isToday(_selectedDate)) {
      await _addRun();
      return;
    }

    final tracked = await _pickRunMode();
    if (tracked == null || !mounted) return;

    if (!tracked) {
      await _addRun();
      return;
    }

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RunTrackingScreen(date: _selectedDate, discipline: d),
      ),
    );
    if (!mounted) return;
    // Reload regardless of the result: an abandoned run may still have written
    // legs before it was abandoned.
    await _loadData();
    if (saved == true) _relock();
  }

  /// Track it live, or type it in. Null if dismissed.
  Future<bool?> _pickRunMode() {
    final lt = context.lt;
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: lt.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LiftrRadii.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: LiftrSpacing.x18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
              child:
                  Text('Add a run', style: Theme.of(ctx).textTheme.displaySmall),
            ),
            const SizedBox(height: LiftrSpacing.x12),
            ListTile(
              leading: const Icon(Icons.my_location,
                  color: LiftrColors.accentDark, size: LiftrType.x22),
              title: Text('Track it live',
                  style: TextStyle(
                      fontSize: LiftrType.x15, color: lt.textPrimary)),
              subtitle: Text('Follow it with GPS from here',
                  style:
                      TextStyle(fontSize: LiftrType.x12, color: lt.textMuted)),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined,
                  color: lt.textSecondary, size: LiftrType.x22),
              title: Text('Enter it manually',
                  style: TextStyle(
                      fontSize: LiftrType.x15, color: lt.textPrimary)),
              subtitle: Text('Type in one you\'ve already done',
                  style:
                      TextStyle(fontSize: LiftrType.x12, color: lt.textMuted)),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: LiftrSpacing.x12),
          ],
        ),
      ),
    );
  }

  /// Keeps a past day you just added to editable.
  ///
  /// Its session may only have come into existence on that save, and a past day
  /// is read-only by default — without this, what you just entered would come
  /// straight back locked behind an EDIT chip.
  void _unlockIfPast(WorkoutSessions? s) {
    final id = s?.sessionId;
    if (id != null && isPastDay(_selectedDate)) {
      setState(() => _editableSessionId = id);
    }
  }

  /// Offers to pick up a run that a crash interrupted, once per launch.
  ///
  /// Completed intervals are already saved — only the leg that was in progress
  /// when the app died lives in the local backup, so this is about that one leg.
  /// Resume reopens the tracked flow where it stopped; discard throws the leg
  /// away, and takes the session with it if nothing else was ever saved into it,
  /// rather than leaving a run with no runs on the calendar.
  Future<void> _maybeOfferRecovery() async {
    if (_recoveryChecked || !mounted) return;
    _recoveryChecked = true;

    final backup = await RunBackupStore.read();
    if (backup == null || !mounted) return;

    final lt = context.lt;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: lt.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LiftrRadii.card)),
        title: Text('Unfinished run',
            style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary)),
        content: Text(
          'A run was interrupted — ${formatDistance(backup.distanceMeters)} in '
          '${formatDuration(backup.elapsedSeconds)}. Pick it back up, or discard '
          'this leg?',
          style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text('Discard', style: TextStyle(color: lt.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'resume'),
            child: const Text('Resume',
                style: TextStyle(color: LiftrColors.accentDark)),
          ),
        ],
      ),
    );

    if (action == 'discard') {
      await RunBackupStore.clear();
      try {
        final legs = await RunService.getIntervals(backup.sessionId);
        // A crash during the very first leg — nothing worth keeping, so the
        // hollow session goes rather than lingering as a run with no runs.
        // Earlier legs are real and simply stay where they are.
        if (legs.isEmpty) await RunService.discardSession(backup.sessionId);
      } catch (_) {}
      if (mounted) await _loadData();
      return;
    }

    if (action == 'resume' && mounted) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RunTrackingScreen(
            date: backup.date,
            discipline: _disciplineFor(backup.disciplineKey),
            resume: backup,
          ),
        ),
      );
      if (mounted && saved != null) await _loadData();
    }
  }

  bool _isToday(DateTime? d) => isToday(d);

  Discipline _disciplineFor(String key) => _disciplines.firstWhere(
        (d) => d.key == key,
        orElse: () => Discipline(key: key, label: key, emoji: '•'),
      );


  /// Opens the gym add-exercise flow, which get-or-creates the day's gym
  /// session as a side effect of saving.
  Future<void> _addExercise() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddExerciseScreen(sessionDate: _selectedDate),
      ),
    );
    await _loadData();
    if (mounted) _unlockIfPast(_gymSession);
  }

  Future<void> _openExercise(WorkoutExercises ex) async {
    // Carry the lock through. Without this you could tap past a read-only card
    // straight into a screen that edits sets, and the lock would be theatre.
    final readOnly = !_canEdit(_gymSession);

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseDetailScreen(
          exercise: ex,
          selectedDate: _selectedDate,
          readOnly: readOnly,
        ),
      ),
    );
    if (changed == true) await _loadData();
  }

  Future<void> _deleteExercise(WorkoutExercises ex) async {
    final id = ex.exerciseId;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Remove exercise?',
        message: '${ex.name} and its logged sets will be removed from this '
            'workout.',
      ),
    );
    if (confirmed != true) return;

    try {
      await WorkoutService.deleteWorkoutExercise(id);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not remove it: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    }
  }

  /// Whether a past day needs the backfill button at all.
  ///
  /// Only where nothing already on screen lets you in. A gym session that
  /// exists has its own EDIT chip, and the run card offers "Add a run" whatever
  /// the day — pairing either with a button that ends up in the same place
  /// gives you two controls and no reason to prefer one.
  ///
  /// What's left is the case the chip can't cover: a past day with no session
  /// to unlock. `onToggleEdit` is null when there's no session, so without this
  /// button that day has no way in at all.
  /// The day's one action, or null when there's nothing to offer.
  ///
  /// One slot, one verb. It used to hold "Start session", "End gym session",
  /// "Log past session" or nothing depending on the date and on whether a
  /// session was open — four meanings in the position your thumb rests on,
  /// with the rarest of them (End) taking the most prominent control in the
  /// app for the whole time you were training.
  Widget? _primaryAction() {
    if (!_canLogHere) return null;

    return ElevatedButton(
      onPressed: _disciplines.isEmpty ? null : _logSomething,
      child: Text(_addLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;

    final primaryAction = _primaryAction();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formattedFullDate(_selectedDate),
                        style: TextStyle(
                            fontSize: LiftrType.x12, color: lt.textMuted),
                      ),
                      const SizedBox(height: LiftrSpacing.x2),
                      Text(
                        // Was hardcoded to "Hey, Alex 👋". For a guest this is
                        // the generated username ("Hey, Swift 👋").
                        'Hey, ${AuthService.shortName} 👋',
                        style: tt.displaySmall,
                      ),
                    ],
                  ),
                ),
                _AvatarMenu(
                  initials: AuthService.initials,
                  onSignOut: widget.onSignOut,
                ),
              ],
            ),
          ),

          _CalendarStrip(
            selectedDate: _selectedDate,
            onDateSelected: _onDateSelected,
            hasWorkout: _hasWorkout,
          ),

          const SizedBox(height: LiftrSpacing.x12),

          // What am I looking at? Sits directly above the card it filters.
          _DisciplineChips(
            disciplines: _disciplines,
            selected: _selectedDiscipline,
            onSelect: (key) => setState(() {
              _selectedDiscipline = key;
              _relock(); // changed the lens — anything unlocked re-locks
            }),
          ),

          const SizedBox(height: LiftrSpacing.x10),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _dayContent(),
            ),
          ),

          // The one way anything gets logged, in the one place it always is.
          if (primaryAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: primaryAction,
            ),
        ],
      ),
    );
  }

  /// Opens the manual run form for the selected day. `logManualRun` writes the
  /// day's session itself, so nothing has to exist first.
  Future<void> _addRun() async {
    _relock();
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddRunScreen(date: _selectedDate)),
    );
    if (saved != true) return;

    await _loadData();
    final key = _selectedDiscipline;
    if (mounted && key != null) _unlockIfPast(_sessionFor(key));
  }

  /// Opens a logged run. Editing and deleting both happen in there, the way an
  /// exercise is changed from its detail screen rather than from the card.
  Future<void> _openRun(
    DistanceInterval interval, {
    required bool readOnly,
    required int otherRunsToday,
  }) async {
    _relock();
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRunScreen(
          date: _selectedDate,
          interval: interval,
          readOnly: readOnly,
          otherRunsToday: otherRunsToday,
        ),
      ),
    );
    if (changed == true) await _loadData();
  }

  /// Acts on the day's scheduled routine, which means something different per
  /// discipline.
  ///
  /// A sets routine is *copied in*: its exercises become rows you then log sets
  /// against. A distance routine is *handed over*: its targets go to the tracker
  /// and nothing is written until you've actually run, because a
  /// `distance_intervals` row means a run that happened. The routine removes the
  /// setup either way; only the gym half has anything to write up front.
  ///
  /// Either way it runs from an explicit tap alone — browsing to a Thursday must
  /// never create a workout you didn't do.
  Future<void> _fillFromRoutine(Routine routine) async {
    final d = _disciplineFor(routine.discipline);

    if (d.logsDistance) {
      setState(() => _selectedDiscipline = routine.discipline);
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RunTrackingScreen(
            date: _selectedDate,
            discipline: d,
            // From the top: this path only fires on a day with nothing run,
            // so every leg is still ahead.
            plannedLegs: routine.legs,
          ),
        ),
      );
      if (!mounted) return;
      await _loadData();
      if (saved == true) _relock();
      return;
    }

    try {
      await RoutineService.fillSession(_selectedDate, routine);
      if (!mounted) return;

      await _loadData();
      if (!mounted) return;

      // Land on what was just filled rather than leaving you on "All" to go
      // looking for it.
      setState(() => _selectedDiscipline = routine.discipline);
      _unlockIfPast(_sessionFor(routine.discipline));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not fill the day: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    }
  }

  /// Runs planned leg [slot], carrying whatever's still ahead of it.
  ///
  /// The tracker gets that leg and every unrun one after it, so its own "add
  /// another interval" flow keeps moving through the plan and you needn't come
  /// back here between reps. Coming back is offered, not required — whichever
  /// legs got run show their results when you return, and the rest are still
  /// there waiting, each with its own Start.
  ///
  /// Legs already run are left out of the queue, and legs *before* [slot] are
  /// too: going back for one you skipped stays a deliberate tap on its row.
  Future<void> _startPlannedLeg(
      Discipline d, Routine? routine, int slot) async {
    final done = {
      for (final i in _intervalsFor(_sessionFor(d.key)))
        if (i.planSlot != null) i.planSlot!,
    };

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RunTrackingScreen(
          date: _selectedDate,
          discipline: d,
          plannedLegs: routine?.legsFrom(slot, doneSlots: done) ?? const [],
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
    if (saved == true) _relock();
  }

  /// The card(s) under the chips: every discipline's session on "All", or just
  /// the one you filtered to.
  Widget _dayContent() {
    // An empty day with something scheduled leads with the offer instead of an
    // empty state that only tells you there's nothing there.
    //
    // Gated on the *whole day* being empty, not just this discipline's slot: on
    // "All" the card would otherwise replace a run you'd already logged with a
    // prompt about the gym.
    //
    // And it steps aside on a distance discipline's own chip, where [_RunCard]
    // has more to say than the prompt does — it lists the planned legs and
    // starts them one at a time, which is the whole point of looking at that
    // chip. The prompt still covers "All", where it's the day's summary.
    final routine = _scheduledRoutine;
    final routineIsDistance =
        routine != null && _disciplineFor(routine.discipline).logsDistance;

    if (routine != null &&
        !_isLoading &&
        _sessions.isEmpty &&
        (_selectedDiscipline == null ||
            (_selectedDiscipline == routine.discipline &&
                !routineIsDistance))) {
      return _RoutinePromptCard(
        date: _selectedDate,
        routine: routine,
        emoji: _disciplineFor(routine.discipline).emoji,
        isDistance: _disciplineFor(routine.discipline).logsDistance,
        // A day that hasn't happened shows what's coming but can't be filled —
        // there's nothing to log yet, and writing one would be a workout you
        // haven't done.
        onFill: isFutureDay(_selectedDate)
            ? null
            : () => _fillFromRoutine(routine),
      );
    }

    if (_selectedDiscipline == Discipline.gymKey) {
      final gym = _gymSession;
      return _WorkoutCard(
        date: _selectedDate,
        session: gym,
        exercises: _exercisesFor(gym),
        isLoading: _isLoading,
        emptyMessage: _emptyHint,
        onSetUpRoutine: _routineNudge,
        isEditable: _canEdit(gym),
        onToggleEdit: _toggleFor(gym),
        onExerciseTap: _openExercise,
        onExerciseDelete: _deleteExercise,
      );
    }

    if (_selectedDiscipline != null) {
      final d = _disciplines.firstWhere(
        (x) => x.key == _selectedDiscipline,
        orElse: () =>
            Discipline(key: _selectedDiscipline!, label: '', emoji: '•'),
      );

      // Distance disciplines log runs. Keyed off what the discipline says it
      // logs, not off 'running' — seeding cycling with logging_type 'distance'
      // gets this card without touching Dart, which is the promise 009 made.
      if (d.logsDistance) {
        final session = _sessionFor(d.key);
        return _RunCard(
          date: _selectedDate,
          discipline: d,
          session: session,
          intervals: _intervalsFor(session),
          // Only this discipline's own routine. A gym day scheduled on the same
          // date has nothing to say about running legs.
          routine: routine?.discipline == d.key ? routine : null,
          isLoading: _isLoading,
          isEditable: _canEdit(session),
          onToggleEdit: _toggleFor(session),
          // You can only run today. The past is history and the future hasn't
          // happened — both are why this is null rather than a disabled button.
          onStartLeg: _isToday(_selectedDate)
              ? (from) => _startPlannedLeg(d, routine, from)
              : null,
          onOpenInterval: (i) => _openRun(
            i,
            readOnly: !_canEdit(session),
            // Every run on the day but this one — the ones whose name would
            // change along with it.
            otherRunsToday: _intervalsFor(session).length - 1,
          ),
        );
      }

      // Seeded, but with no child table or UI yet.
      return _ComingSoonCard(discipline: d);
    }

    // "All" — everything logged today, whatever the discipline.
    return _AllSessionsCard(
      date: _selectedDate,
      sessions: _sessions,
      disciplines: _disciplines,
      exercisesBySession: _exercisesBySession,
      runsBySession: _runsBySession,
      isLoading: _isLoading,
      emptyMessage: _emptyHint,
      onSetUpRoutine: _routineNudge,
      // One rule for every discipline now, so this needs no routing by logging
      // type the way it did while gym and running locked on different things.
      isEditable: _canEdit,
      onOpenDiscipline: (key) => setState(() {
        _selectedDiscipline = key;
        _relock();
      }),
      onExerciseTap: _openExercise,
      onExerciseDelete: _deleteExercise,
      onOpenInterval: (s, i) => _openRun(
        i,
        readOnly: !_canEdit(s),
        otherRunsToday: _intervalsFor(s).length - 1,
      ),
    );
  }

  String _formattedFullDate(DateTime d) => weekdayDate(d);
}

// ── Discipline chips ──────────────────────────────────────────
/// "What am I looking at?" — an All chip plus one per discipline you train.
///
/// Capped at [_maxVisible] so the row can't run off the screen once there are
/// six disciplines; the rest collapse into an "Other" chip that opens a sheet.
/// The chip you have selected is always visible, even if it lives in the
/// overflow — otherwise picking from the sheet would appear to do nothing.
class _DisciplineChips extends StatelessWidget {
  final List<Discipline> disciplines;

  /// Null = All.
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _DisciplineChips({
    required this.disciplines,
    required this.selected,
    required this.onSelect,
  });

  /// Beyond this many, the tail goes behind "Other". Three plus All is what fits
  /// comfortably on a narrow phone.
  static const _maxVisible = 3;

  @override
  Widget build(BuildContext context) {
    if (disciplines.isEmpty) return const SizedBox.shrink();

    final overflows = disciplines.length > _maxVisible;
    var visible = overflows
        ? disciplines.take(_maxVisible - 1).toList()
        : List<Discipline>.from(disciplines);
    var hidden = disciplines.where((d) => !visible.contains(d)).toList();

    // Keep the selection on screen: swap it into the last visible slot.
    if (selected != null && !visible.any((d) => d.key == selected)) {
      final picked = hidden.where((d) => d.key == selected).toList();
      if (picked.isNotEmpty) {
        visible = [...visible, picked.first];
        hidden = hidden.where((d) => d.key != selected).toList();
      }
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
        children: [
          _Chip(
            label: 'All',
            isSelected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final d in visible) ...[
            const SizedBox(width: LiftrSpacing.x6),
            _Chip(
              label: d.label,
              emoji: d.emoji,
              isSelected: selected == d.key,
              onTap: () => onSelect(d.key),
            ),
          ],
          if (hidden.isNotEmpty) ...[
            const SizedBox(width: LiftrSpacing.x6),
            _Chip(
              label: 'Other',
              trailing: Icons.expand_more,
              isSelected: false,
              onTap: () => _pickOther(context, hidden),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickOther(BuildContext context, List<Discipline> hidden) async {
    final lt = context.lt;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: lt.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LiftrRadii.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: LiftrSpacing.x12),
            const SectionLabel('Other disciplines'),
            const SizedBox(height: LiftrSpacing.x8),
            for (final d in hidden)
              ListTile(
                leading: Text(d.emoji,
                    style: const TextStyle(fontSize: LiftrType.x20)),
                title: Text(d.label,
                    style: TextStyle(
                        fontSize: LiftrType.x14, color: lt.textPrimary)),
                onTap: () => Navigator.pop(ctx, d.key),
              ),
            const SizedBox(height: LiftrSpacing.x8),
          ],
        ),
      ),
    );
    if (picked != null) onSelect(picked);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String? emoji;
  final IconData? trailing;
  final bool isSelected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.emoji,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x12),
        decoration: BoxDecoration(
          color: isSelected ? LiftrColors.accent : lt.card,
          border: Border.all(
            color: isSelected ? LiftrColors.accent : lt.border,
            width: LiftrBorders.hairline,
          ),
          borderRadius: BorderRadius.circular(LiftrRadii.panel),
        ),
        child: Row(
          children: [
            if (emoji != null) ...[
              Text(emoji!, style: const TextStyle(fontSize: LiftrType.x13)),
              const SizedBox(width: LiftrSpacing.x6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: LiftrType.x13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? LiftrColors.accentText : lt.textSecondary,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: LiftrSpacing.x2),
              Icon(trailing, size: 14, color: lt.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

// ── All-disciplines view ──────────────────────────────────────
/// Everything logged on this day, grouped by the session it belongs to.
///
/// The chips are a filter and nothing else, so "All" has to be the union of
/// what they filter: the same rows the gym and run cards show, one group per
/// session. It used to be a list of summary rows you tapped through to see any
/// of it, which made "All" a menu rather than a lens.
///
/// It still can't just stack [_WorkoutCard] and [_RunCard] — both size
/// themselves with an Expanded and would need an arbitrary fixed height inside
/// a scroll view. The rows are reused instead, which is what keeps a group here
/// identical to the card it came from, down to the edit lock on each one.
class _AllSessionsCard extends StatelessWidget {
  final DateTime date;
  final List<WorkoutSessions> sessions;
  final List<Discipline> disciplines;
  final Map<String, List<WorkoutExercises>> exercisesBySession;
  final Map<String, List<DistanceInterval>> runsBySession;
  final bool isLoading;

  /// What to say when the day is empty. Supplied rather than fixed: the hint
  /// names the button below it, and on a future day there isn't one.
  final String emptyMessage;

  /// Completes [emptyMessage] with a tappable offer of routines. Null once the
  /// user has any.
  final VoidCallback? onSetUpRoutine;

  /// Whether a session's rows accept changes.
  ///
  /// Asked per session rather than passed as one flag: a day holds several, and
  /// the answer genuinely differs between them — the gym one may be the session
  /// you're in while the run beside it is already history.
  final bool Function(WorkoutSessions) isEditable;

  /// Jumps to a discipline's own chip, which is where adding to it lives.
  final ValueChanged<String> onOpenDiscipline;

  final ValueChanged<WorkoutExercises> onExerciseTap;
  final ValueChanged<WorkoutExercises> onExerciseDelete;

  /// Takes the session as well as the leg: the caller needs it to work out the
  /// lock and how many other runs share the day.
  final void Function(WorkoutSessions, DistanceInterval) onOpenInterval;

  const _AllSessionsCard({
    required this.date,
    required this.sessions,
    required this.disciplines,
    required this.exercisesBySession,
    required this.runsBySession,
    required this.isLoading,
    required this.emptyMessage,
    required this.onSetUpRoutine,
    required this.isEditable,
    required this.onOpenDiscipline,
    required this.onExerciseTap,
    required this.onExerciseDelete,
    required this.onOpenInterval,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    // Same chrome as the discipline cards, for the same reason they match each
    // other: changing the chip should change what's in the card, not how the
    // screen works.
    return Container(
      decoration: BoxDecoration(
        color: lt.surface,
        border:
            Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.sheet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${dayLabel(date)} · ${shortDate(date)}',
                        style: TextStyle(
                          fontSize: LiftrType.x11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.08,
                          color: lt.textMuted,
                        ),
                      ),
                      const SizedBox(height: LiftrSpacing.x3),
                      Text(
                        sessions.isEmpty ? 'No sessions' : 'Everything logged',
                        style: TextStyle(
                          fontSize: LiftrType.x16,
                          fontWeight: FontWeight.w500,
                          color: sessions.isEmpty ? lt.textDim : lt.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (sessions.isNotEmpty)
                  AccentChip(
                      '${sessions.length} session${sessions.length == 1 ? '' : 's'}'),
              ],
            ),
          ),

          const Divider(),

          // Expanded for the same reason the other cards use it: the card fills
          // the height it's given, so the empty state sits in the middle rather
          // than clinging to the top.
          Expanded(
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LiftrColors.accent,
                      ),
                    ),
                  )
                : sessions.isEmpty
                    ? _EmptyState(
                        message: emptyMessage,
                        onSetUpRoutine: onSetUpRoutine,
                      )
                    : ListView(
                        padding: const EdgeInsets.only(
                            bottom: LiftrSpacing.x6),
                        children: [
                          for (var i = 0; i < sessions.length; i++)
                            ..._group(sessions[i], isFirst: i == 0),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  /// One session: its header, then its own rows.
  List<Widget> _group(WorkoutSessions s, {required bool isFirst}) {
    final d = _lookup(s.discipline);
    final rows = _rowsFor(s, d);

    return [
      // A rule between groups rather than above the first, which already has
      // the header's divider above it.
      if (!isFirst) const Divider(),
      _GroupHeader(
        emoji: d.emoji,
        title: _titleFor(s, d),
        badge: _badgeFor(s, d),
        onTap: () => onOpenDiscipline(s.discipline),
      ),
      if (rows.isEmpty) _GroupEmptyRow(discipline: d) else ...rows,
    ];
  }

  /// The rows for a session, chosen by what its discipline logs — the same
  /// branch [_TodayTabState._loadData] uses to fetch them.
  List<Widget> _rowsFor(WorkoutSessions s, Discipline d) {
    final id = s.sessionId;
    if (id == null) return const [];

    if (d.logsDistance) {
      return [
        for (final i in runsBySession[id] ?? const <DistanceInterval>[])
          _IntervalRow(
            interval: i,
            emoji: d.emoji,
            name: _titleFor(s, d),
            // Unnumbered here: "All" summarises what happened across every
            // discipline and has no plan in hand to number legs against.
            legNumber: null,
            onTap: () => onOpenInterval(s, i),
          ),
      ];
    }

    final editable = isEditable(s);
    return [
      for (final e in exercisesBySession[id] ?? const <WorkoutExercises>[])
        _ExerciseRow(
          exercise: e,
          isEditable: editable,
          onTap: () => onExerciseTap(e),
          onDelete: () => onExerciseDelete(e),
        ),
    ];
  }

  String _titleFor(WorkoutSessions s, Discipline d) =>
      s.name?.trim().isNotEmpty == true ? s.name!.trim() : d.label;

  /// The one number worth seeing before opening a group — the same figure each
  /// discipline's own card puts in its header.
  String? _badgeFor(WorkoutSessions s, Discipline d) {
    final id = s.sessionId;
    if (id == null) return null;

    if (d.logsDistance) {
      final intervals = runsBySession[id] ?? const <DistanceInterval>[];
      if (intervals.isEmpty) return null;
      return formatDistance(RunTotals.from(intervals).distanceMeters);
    }

    final n = (exercisesBySession[id] ?? const []).length;
    return n == 0 ? null : '$n EX';
  }

  Discipline _lookup(String key) => disciplines.firstWhere(
        (d) => d.key == key,
        orElse: () => Discipline(key: key, label: key, emoji: '•'),
      );
}

/// The label above a group's rows, and the way through to the discipline's own
/// chip — which is where adding to it lives, since "All" is a lens rather than
/// a place you log from.
class _GroupHeader extends StatelessWidget {
  final String emoji;
  final String title;
  final String? badge;
  final VoidCallback onTap;

  const _GroupHeader({
    required this.emoji,
    required this.title,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: LiftrType.x13)),
            const SizedBox(width: LiftrSpacing.x8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: LiftrType.x12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.08,
                  color: lt.textSecondary,
                ),
              ),
            ),
            if (badge != null) ...[
              AccentChip(badge!),
              const SizedBox(width: LiftrSpacing.x6),
            ],
            Icon(Icons.chevron_right, size: 16, color: lt.textDim),
          ],
        ),
      ),
    );
  }
}

/// A session that exists but holds nothing yet — everything in it was deleted,
/// or its discipline's logging screen isn't built. Saying so beats a header
/// with nothing under it.
class _GroupEmptyRow extends StatelessWidget {
  final Discipline discipline;
  const _GroupEmptyRow({required this.discipline});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Text(
        discipline.loggingType == Discipline.loggingNone
            ? '${discipline.label} logging is on the way'
            : 'Nothing logged in this session yet',
        style: TextStyle(fontSize: LiftrType.x12, color: lt.textDim),
      ),
    );
  }
}

// ── Scheduled routine ─────────────────────────────────────────
/// What's on today, and the one tap that puts it in.
///
/// Takes the place of the empty state rather than sitting beside it: on a day
/// you've scheduled something for, "nothing logged yet" is the least useful
/// thing the card could say. The primary button below is untouched — this is
/// content, not a second control competing with it.
class _RoutinePromptCard extends StatefulWidget {
  final DateTime date;
  final Routine routine;
  final String emoji;

  /// Whether this routine's discipline logs distance.
  ///
  /// Passed in rather than inferred from the routine's own contents: a distance
  /// routine with no targets is a valid plan — "just go for a run" — and reading
  /// its emptiness as "this is a gym day" would offer the wrong button.
  final bool isDistance;

  /// Null on a day that hasn't happened, where the card states the plan and
  /// offers nothing to press.
  final VoidCallback? onFill;

  const _RoutinePromptCard({
    required this.date,
    required this.routine,
    required this.emoji,
    required this.isDistance,
    required this.onFill,
  });

  @override
  State<_RoutinePromptCard> createState() => _RoutinePromptCardState();
}

class _RoutinePromptCardState extends State<_RoutinePromptCard> {
  /// Local, because the fill is one insert and the reload behind it takes long
  /// enough to double-tap through. The parent rebuilds this away on success, so
  /// it never has to be cleared.
  bool _filling = false;

  Future<void> _fill() async {
    setState(() => _filling = true);
    widget.onFill!();
  }

  /// A distance routine hands off to the tracker rather than writing anything,
  /// so the button has to say so — "Fill this in" would promise a day already
  /// logged, when what's about to happen is a run.
  bool get _isRun => widget.routine.intervals.isNotEmpty || widget.isDistance;

  /// The planned legs, or the exercise names — whichever this routine holds.
  String get _contents {
    final r = widget.routine;
    if (r.intervals.isNotEmpty) {
      return [for (final i in r.intervals) formatDistance(i.targetDistanceMeters)]
          .join(' · ');
    }
    return [for (final e in r.exercises) e.name].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final r = widget.routine;
    final n = r.itemCount;

    return Container(
      decoration: BoxDecoration(
        color: lt.surface,
        border:
            Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.sheet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              '${dayLabel(widget.date)} · ${shortDate(widget.date)}',
              style: TextStyle(
                fontSize: LiftrType.x11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.08,
                color: lt.textMuted,
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: LiftrSpacing.x24, vertical: LiftrSpacing.x16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.emoji,
                        style: const TextStyle(fontSize: LiftrType.x32)),
                    const SizedBox(height: LiftrSpacing.x12),
                    Text(
                      r.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: LiftrType.x18,
                        fontWeight: FontWeight.w600,
                        color: lt.textPrimary,
                      ),
                    ),
                    const SizedBox(height: LiftrSpacing.x4),
                    Text(
                      // An empty distance routine isn't unfinished — it means
                      // "just go", which the tracker handles as a free run. An
                      // empty gym one genuinely has nothing to put in.
                      n > 0
                          ? r.summary
                          : _isRun
                              ? 'No set distance — just go'
                              : 'This routine has nothing in it yet',
                      style: TextStyle(
                          fontSize: LiftrType.x12, color: lt.textMuted),
                    ),

                    if (n > 1) ...[
                      const SizedBox(height: LiftrSpacing.x14),
                      // The contents themselves, so you can see it's the right
                      // day before committing to it.
                      Text(
                        _contents,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: LiftrType.x11,
                          color: lt.textDim,
                          height: 1.6,
                        ),
                      ),
                    ],

                    // A run needs no contents to be startable — an empty
                    // distance routine is still a run you can go on.
                    if (widget.onFill != null && (n > 0 || _isRun)) ...[
                      const SizedBox(height: LiftrSpacing.x20),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _filling ? null : _fill,
                          child: _filling
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: LiftrColors.accentText,
                                  ),
                                )
                              : Text(_isRun ? 'Start the run' : 'Fill this in'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Discipline without a UI yet ───────────────────────────────
class _ComingSoonCard extends StatelessWidget {
  final Discipline discipline;
  const _ComingSoonCard({required this.discipline});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Container(
      decoration: BoxDecoration(
        color: lt.surface,
        border:
            Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.sheet),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(discipline.emoji,
                  style: const TextStyle(fontSize: LiftrType.x32)),
              const SizedBox(height: LiftrSpacing.x12),
              Text(
                '${discipline.label} logging is on the way',
                style: TextStyle(
                  fontSize: LiftrType.x14,
                  fontWeight: FontWeight.w500,
                  color: lt.textPrimary,
                ),
              ),
              const SizedBox(height: LiftrSpacing.x6),
              Text(
                'The discipline is set up — its logging screen is next.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: LiftrType.x12, color: lt.textDim, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Run card ──────────────────────────────────────────────────
/// The day's running: what's planned, what's done, and the way to start the
/// next leg.
///
/// Built to the same shape as [_WorkoutCard] — same header, same divider, same
/// Expanded list region — so switching the discipline chip changes what's in
/// the card rather than how the screen works. It goes further than that now:
/// the gym card lists the exercises you're working through, and this lists the
/// legs, so the two disciplines finally read the same way. Running used to hide
/// behind a single "Start the run" that swallowed the whole session.
///
/// **The plan is never stored as intervals.** [plannedTargets] comes from the
/// day's routine and [intervals] from the session, and this merges them for
/// display only: leg *n* of the plan pairs with the *n*th run you actually did.
/// A `distance_intervals` row means a run that happened, so writing planned ones
/// would put 0 m in 0:00 into your history and drag the day's totals down.
/// Migration 022's header has the long version.
///
/// A session holds several intervals rather than one: "go again" after a
/// kilometre appends, which is also what keeps a second run on the same day
/// from colliding with the one-session-per-day-per-discipline index from 009.
class _RunCard extends StatelessWidget {
  final DateTime date;

  /// Supplies the row emoji, so this card serves any distance discipline rather
  /// than assuming running.
  final Discipline discipline;

  final WorkoutSessions? session;
  final List<DistanceInterval> intervals;

  /// The day's routine, if one is scheduled. Supplies the planned legs and the
  /// name to show before a session exists.
  final Routine? routine;

  final bool isLoading;

  /// Read-only unless the day is today or you've tapped EDIT, so a day gone by
  /// can't be altered by a stray tap while you're looking back at it.
  final bool isEditable;

  /// Toggles EDIT ⇄ DONE. Null when there's nothing to toggle.
  final VoidCallback? onToggleEdit;

  /// Opens a logged run. Deleting it happens in there, not from this card.
  final ValueChanged<DistanceInterval> onOpenInterval;

  /// Starts the planned leg at this index in the plan. Null on a day you can't
  /// run — one that hasn't happened, or one already gone by.
  final ValueChanged<int>? onStartLeg;

  const _RunCard({
    required this.date,
    required this.discipline,
    required this.session,
    required this.intervals,
    required this.routine,
    required this.isLoading,
    required this.isEditable,
    required this.onToggleEdit,
    required this.onOpenInterval,
    required this.onStartLeg,
  });

  /// The day's planned legs, run or not. Empty when no routine is scheduled, or
  /// when the routine deliberately plans nothing — "just go for a run".
  List<PlannedLeg> get _planned => routine?.legs ?? const [];

  /// The run that filled a given plan slot, if one has.
  ///
  /// This is what makes a leg's result land back in its own row: a run started
  /// from leg 3 recorded a 3, so it shows in leg 3's place while 1, 2 and 4 stay
  /// planned. Takes the first match — two runs claiming a slot is a state the UI
  /// can't produce, since a filled slot shows its log rather than a Start.
  DistanceInterval? _runFor(int slot) {
    for (final i in intervals) {
      if (i.planSlot == slot) return i;
    }
    return null;
  }

  /// Runs that answer to no planned leg: logged manually, tracked on a day with
  /// no routine, or an extra leg past the plan. Listed after the planned block,
  /// unnumbered — they're real, the plan just has nothing to say about them.
  List<DistanceInterval> get _unplanned {
    final slots = {for (final leg in _planned) leg.slot};
    return [
      for (final i in intervals)
        if (i.planSlot == null || !slots.contains(i.planSlot)) i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final totals = RunTotals.from(intervals);

    return Container(
      decoration: BoxDecoration(
        color: lt.surface,
        border:
            Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.sheet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${dayLabel(date)} · ${shortDate(date)}',
                        style: TextStyle(
                          fontSize: LiftrType.x11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.08,
                          color: lt.textMuted,
                        ),
                      ),
                      const SizedBox(height: LiftrSpacing.x3),
                      Text(
                        // Before the first leg there's no session to name, but
                        // there may well be a plan — and "No session" on a day
                        // with four legs waiting reads as though nothing's on.
                        session?.name ?? routine?.name ?? 'No session',
                        style: TextStyle(
                          fontSize: LiftrType.x16,
                          fontWeight: FontWeight.w500,
                          color: (session ?? routine) != null
                              ? lt.textPrimary
                              : lt.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                // Progress against the plan, or the total once there's no plan
                // to measure against — either way, the single number worth
                // seeing before opening anything.
                if (_planned.isNotEmpty) ...[
                  AccentChip('${intervals.length}/${_planned.length}'),
                  const SizedBox(width: LiftrSpacing.x6),
                ] else if (intervals.isNotEmpty) ...[
                  AccentChip(formatDistance(totals.distanceMeters)),
                  const SizedBox(width: LiftrSpacing.x6),
                ],
                // Stays put and flips label rather than disappearing — a
                // control that vanishes on tap gives you nothing to undo with.
                if (onToggleEdit != null)
                  _EditToggleChip(
                    isEditing: isEditable,
                    onTap: onToggleEdit!,
                  ),
              ],
            ),
          ),

          // No inline "Add a run" any more. Adding is the button at the bottom
          // of the screen, in one place, whatever you're looking at — an add
          // row here as well meant two controls for one act, each appearing
          // under its own conditions.
          const Divider(),

          // Expanded, so the card fills the height it is given and the empty
          // state sits in the middle of it rather than clinging to the top with
          // a screen of dead space underneath.
          Expanded(
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LiftrColors.accent,
                      ),
                    ),
                  )
                : (intervals.isEmpty && _planned.isEmpty)
                    ? _EmptyState(
                        message: isFutureDay(date)
                            ? kNotYetHint
                            : 'No runs logged for this day.\n'
                                'Tap "Add a run" below to put one in.')
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                            vertical: LiftrSpacing.x6),
                        children: [
                          // The plan, in its own order. Each leg shows its run
                          // if it has one and a Start if it doesn't — so a
                          // finished leg replaces its own planned row and the
                          // rest carry on waiting.
                          for (final leg in _planned)
                            _legRow(leg),

                          // Then anything the plan didn't ask for.
                          for (final extra in _unplanned)
                            _IntervalRow(
                              interval: extra,
                              emoji: discipline.emoji,
                              legNumber: null,
                              name: _rowName,
                              onTap: () => onOpenInterval(extra),
                            ),

                          if (intervals.length > 1) _totalsRow(lt, totals),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  /// Falls back to the discipline rather than showing an empty title if a
  /// session somehow has no name.
  String get _rowName => session?.name?.trim().isNotEmpty == true
      ? session!.name!
      : discipline.label;

  /// One leg of the plan: what you ran, or an offer to run it.
  Widget _legRow(PlannedLeg leg) {
    final run = _runFor(leg.slot);
    if (run != null) {
      return _IntervalRow(
        interval: run,
        emoji: discipline.emoji,
        legNumber: leg.slot,
        name: _rowName,
        onTap: () => onOpenInterval(run),
      );
    }

    return _PlannedLegRow(
      legNumber: leg.slot,
      targetMeters: leg.targetMeters,
      // Every unrun leg is startable, not just the next one. The run records
      // which slot it was, so leg 3 stays leg 3 whether you run it first or
      // last — nothing here depends on doing them in order.
      onStart:
          onStartLeg == null ? null : () => onStartLeg!(leg.slot),
    );
  }

  Widget _totalsRow(LiftrTheme lt, RunTotals totals) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Text(
            '${totals.intervalCount} runs',
            style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
          ),
          const Spacer(),
          Text(
            '${formatDuration(totals.durationSeconds)} · '
            '${formatPace(totals.distanceMeters, totals.durationSeconds)}',
            style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Planned leg ───────────────────────────────────────────────
/// A leg the routine plans but you haven't run yet.
///
/// Shaped like [_IntervalRow] so a plan turning into history changes the row's
/// contents rather than swapping it for something that looks unrelated. Nothing
/// behind it exists in the database — see [_RunCard].
class _PlannedLegRow extends StatelessWidget {
  final int legNumber;
  final double targetMeters;

  /// Null only on days you can't run — a day gone by, or one that hasn't
  /// happened. Every unrun leg of a runnable day offers to start.
  final VoidCallback? onStart;

  const _PlannedLegRow({
    required this.legNumber,
    required this.targetMeters,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final runnable = onStart != null;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LiftrSpacing.x16, vertical: LiftrSpacing.x10),
      child: Row(
        children: [
          // A hollow numbered tile against the done legs' filled emoji one: the
          // difference between "run" and "still to run" should be visible down
          // the left edge without reading a word of it.
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              border: Border.all(
                color: runnable ? lt.accentBorder : lt.border,
                width: LiftrBorders.hairline,
              ),
              borderRadius: BorderRadius.circular(LiftrRadii.control),
            ),
            child: Center(
              child: Text(
                '$legNumber',
                style: TextStyle(
                  fontSize: LiftrType.x13,
                  fontWeight: FontWeight.w500,
                  color: runnable ? lt.accentMid : lt.textDim,
                ),
              ),
            ),
          ),
          const SizedBox(width: LiftrSpacing.x10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDistance(targetMeters),
                  style: TextStyle(
                    fontSize: LiftrType.x13,
                    fontWeight: FontWeight.w500,
                    color: runnable ? lt.textPrimary : lt.textDim,
                  ),
                ),
                const SizedBox(height: LiftrSpacing.x2),
                Text(
                  'Not run yet',
                  style:
                      TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
                ),
              ],
            ),
          ),
          if (runnable)
            GestureDetector(
              onTap: onStart,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x8),
                decoration: BoxDecoration(
                  color: LiftrColors.accent,
                  borderRadius: BorderRadius.circular(LiftrRadii.panel),
                ),
                child: const Text(
                  'Start',
                  style: TextStyle(
                    fontSize: LiftrType.x12,
                    fontWeight: FontWeight.w600,
                    color: LiftrColors.accentText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Interval Row ──────────────────────────────────────────────
/// One leg of a run, shaped like [_ExerciseRow] so the two cards read as the
/// same screen with different contents in it.
class _IntervalRow extends StatelessWidget {
  final DistanceInterval interval;

  /// The discipline's own emoji, filling the tile an exercise fills with its
  /// muscle-group icon. Passed in rather than hardcoded to a runner: a cycling
  /// discipline seeded as `logging_type = 'distance'` gets its own here.
  final String emoji;

  /// The session's name — what an exercise row shows as its title.
  ///
  /// Every run of the day carries the same one, because the name lives on the
  /// session they share. Repeating it per row is the cost of the numbers moving
  /// down to the subtitle, where they read as detail rather than identity.
  final String name;

  /// Its position in the day's plan, when there is one. Null on an ad-hoc run,
  /// where there's no sequence for a number to mean anything within.
  final int? legNumber;

  final VoidCallback onTap;

  const _IntervalRow({
    required this.interval,
    required this.emoji,
    required this.name,
    required this.legNumber,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    // The name leads and the numbers follow, the same way an exercise row reads
    // "Bench Press / Barbell · Chest" rather than leading with its equipment.
    final subtitle = [
      formatDistance(interval.actualDistanceMeters),
      formatDuration(interval.durationSeconds),
      formatPace(interval.actualDistanceMeters, interval.durationSeconds),
    ].where((p) => p.isNotEmpty && p != '—').join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x16, vertical: LiftrSpacing.x10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: lt.card,
                borderRadius: BorderRadius.circular(LiftrRadii.control),
              ),
              child: Center(
                child: Text(emoji,
                    style: const TextStyle(fontSize: LiftrType.x16)),
              ),
            ),
            const SizedBox(width: LiftrSpacing.x10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Numbered inside a plan, so a done leg and the pending one
                    // under it line up as the same sequence.
                    legNumber == null ? name : 'Leg $legNumber · $name',
                    style: TextStyle(
                      fontSize: LiftrType.x13,
                      fontWeight: FontWeight.w500,
                      color: lt.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: LiftrSpacing.x2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: LiftrType.x11, color: lt.textMuted)),
                  ],
                ],
              ),
            ),
            // Always a chevron, never a menu. The row's job is to open the run;
            // deleting it belongs on the screen that opens, the same way an
            // exercise is deleted from its detail screen rather than from here.
            Icon(Icons.chevron_right, size: 18, color: lt.textDim),
          ],
        ),
      ),
    );
  }
}

// ── Avatar menu ───────────────────────────────────────────────
class _AvatarMenu extends StatelessWidget {
  final String initials;
  final VoidCallback onSignOut;
  const _AvatarMenu({required this.initials, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'signout') onSignOut();
      },
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LiftrRadii.field)),
      color: lt.card,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 16, color: lt.textSecondary),
              const SizedBox(width: LiftrSpacing.x10),
              Text('Sign out',
                  style: TextStyle(
                      fontSize: LiftrType.x13, color: lt.textSecondary)),
            ],
          ),
        ),
      ],
      child: AvatarCircle(initials),
    );
  }
}

// ── Calendar Strip ────────────────────────────────────────────
class _CalendarStrip extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool Function(DateTime) hasWorkout;

  const _CalendarStrip({
    required this.selectedDate,
    required this.onDateSelected,
    required this.hasWorkout,
  });

  @override
  State<_CalendarStrip> createState() => _CalendarStripState();
}

class _CalendarStripState extends State<_CalendarStrip> {
  late DateTime _weekStart = _getWeekStart(widget.selectedDate);

  @override
  void didUpdateWidget(covariant _CalendarStrip old) {
    super.didUpdateWidget(old);
    // Jumping to a date from the Log tab must move the visible week with it.
    if (old.selectedDate != widget.selectedDate) {
      _weekStart = _getWeekStart(widget.selectedDate);
    }
  }

  DateTime _getWeekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  void _shiftWeek(int delta) {
    setState(() => _weekStart = _weekStart.add(Duration(days: delta * 7)));
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                monthYear(_weekStart),
                style: TextStyle(
                  fontSize: LiftrType.x13,
                  fontWeight: FontWeight.w500,
                  color: lt.textPrimary,
                ),
              ),
              const Spacer(),
              IconSquareButton(
                icon:
                    Icon(Icons.chevron_left, size: 16, color: lt.textSecondary),
                onTap: () => _shiftWeek(-1),
              ),
              const SizedBox(width: LiftrSpacing.x8),
              IconSquareButton(
                icon: Icon(Icons.chevron_right,
                    size: 16, color: lt.textSecondary),
                onTap: () => _shiftWeek(1),
              ),
            ],
          ),
          const SizedBox(height: LiftrSpacing.x12),
          Row(
            children: List.generate(7, (i) {
              final day = _weekStart.add(Duration(days: i));
              final isSelected = day.year == widget.selectedDate.year &&
                  day.month == widget.selectedDate.month &&
                  day.day == widget.selectedDate.day;
              final isToday = day.year == now.year &&
                  day.month == now.month &&
                  day.day == now.day;
              final hasWork = widget.hasWorkout(day);

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onDateSelected(day),
                  child: Column(
                    children: [
                      Text(
                        kWeekdaysUpper[i],
                        style: TextStyle(
                          fontSize: LiftrType.x10,
                          fontWeight: FontWeight.w500,
                          color: hasWork ? lt.accentMid : lt.textDim,
                        ),
                      ),
                      const SizedBox(height: LiftrSpacing.x4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? LiftrColors.accent
                              : isToday
                                  ? lt.accentBg
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(LiftrRadii.tile),
                          border: isToday && !isSelected
                              ? Border.all(
                                  color: lt.accentBorder,
                                  width: LiftrBorders.hairline)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: LiftrType.x13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? LiftrColors.accentText
                                  : lt.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: LiftrSpacing.x4),
                      AnimatedOpacity(
                        opacity: hasWork ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            // Bright lime reads on dark but vanishes on light;
                            // accentStrong is the vivid accent made legible on
                            // both.
                            color: lt.accentStrong,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Workout Card ──────────────────────────────────────────────
class _WorkoutCard extends StatelessWidget {
  final DateTime date;
  final WorkoutSessions? session;
  final List<WorkoutExercises> exercises;
  final bool isLoading;

  /// What to say when there's no session on this day. Supplied rather than
  /// fixed: the hint names the button below it, and on a future day there
  /// isn't one.
  final String emptyMessage;

  /// Completes [emptyMessage] with a tappable offer of routines. Null once the
  /// user has any.
  final VoidCallback? onSetUpRoutine;

  /// Read-only unless the day is today or you've tapped EDIT.
  final bool isEditable;

  /// Toggles EDIT ⇄ DONE. Null when there's nothing to toggle.
  final VoidCallback? onToggleEdit;

  final ValueChanged<WorkoutExercises> onExerciseTap;
  final ValueChanged<WorkoutExercises> onExerciseDelete;

  const _WorkoutCard({
    required this.date,
    required this.session,
    required this.exercises,
    required this.isLoading,
    required this.emptyMessage,
    required this.onSetUpRoutine,
    required this.isEditable,
    required this.onToggleEdit,
    required this.onExerciseTap,
    required this.onExerciseDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Container(
      decoration: BoxDecoration(
        color: lt.surface,
        border:
            Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.sheet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${dayLabel(date)} · ${shortDate(date)}',
                        style: TextStyle(
                          fontSize: LiftrType.x11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.08,
                          color: lt.textMuted,
                        ),
                      ),
                      const SizedBox(height: LiftrSpacing.x3),
                      Text(
                        session?.name ?? 'No session',
                        style: TextStyle(
                          fontSize: LiftrType.x16,
                          fontWeight: FontWeight.w500,
                          color: session != null ? lt.textPrimary : lt.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                if (exercises.isNotEmpty) ...[
                  AccentChip('${exercises.length} EX'),
                  const SizedBox(width: LiftrSpacing.x6),
                ],
                // Stays put and flips label rather than disappearing — a control
                // that vanishes on tap gives you nothing to undo with.
                if (onToggleEdit != null)
                  _EditToggleChip(
                    isEditing: isEditable,
                    onTap: onToggleEdit!,
                  ),
              ],
            ),
          ),

          // No inline "Add exercise" any more — it lived here and only appeared
          // once a session existed and was unlocked, while the bottom of the
          // screen held a second control for the same act under different
          // conditions. Adding is the button below, always.
          const Divider(),

          Expanded(
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LiftrColors.accent,
                      ),
                    ),
                  )
                : session == null
                    ? _EmptyState(
                        message: emptyMessage,
                        onSetUpRoutine: onSetUpRoutine,
                      )
                    : exercises.isEmpty
                        ? _EmptyState(
                            message: isEditable
                                ? 'No exercises yet.\nTap "Add exercise" below to get started.'
                                : 'Nothing was logged in this session.')
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                vertical: LiftrSpacing.x6),
                            itemCount: exercises.length,
                            itemBuilder: (_, i) => _ExerciseRow(
                              exercise: exercises[i],
                              isEditable: isEditable,
                              onTap: () => onExerciseTap(exercises[i]),
                              onDelete: () => onExerciseDelete(exercises[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Edit ⇄ Cancel on a finished session.
///
/// Text-only, no padlock: a lock icon reads as "you can't", when the whole point
/// of the control is that you can.
///
/// Metrics deliberately mirror [AccentChip] exactly — padding, font size,
/// weight, letter spacing and radius — so it sits level with the "3 EX" chip
/// beside it instead of towering over it.
class _EditToggleChip extends StatelessWidget {
  /// True once unlocked, when the chip becomes the way back out.
  final bool isEditing;
  final VoidCallback onTap;

  const _EditToggleChip({required this.isEditing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x10, vertical: LiftrSpacing.x4),
        decoration: BoxDecoration(
          // Tinted while editing: the state is worth seeing at a glance, since
          // it silently expires when you change date or filter.
          color: isEditing ? lt.accentBg : lt.card,
          border: Border.all(
            color: isEditing ? lt.accentBorder : lt.border,
            width: LiftrBorders.hairline,
          ),
          borderRadius: BorderRadius.circular(LiftrRadii.panel),
        ),
        child: Text(
          isEditing ? 'DONE' : 'EDIT',
          style: TextStyle(
            fontSize: LiftrType.x10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.06,
            color: isEditing ? lt.accentTextColor : lt.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────
/// What an empty day says when there's no action to point at, because the day
/// hasn't happened. Shared so the gym and run cards word it identically.
const kNotYetHint = "Nothing here yet.\nThis day hasn't happened.";

/// Stateful only to own a [TapGestureRecognizer].
///
/// A recognizer has to be disposed, and building one inline in a stateless
/// widget mints a fresh one on every rebuild with nothing to release the last —
/// which this widget would do on every date tap.
class _EmptyState extends StatefulWidget {
  final String message;

  /// When set, [message] is finished off with a tappable offer of routines.
  ///
  /// One sentence rather than a separate line: filling the day automatically is
  /// an *alternative* to the tap you were about to make, and two stacked
  /// sentences would read as two unrelated suggestions.
  final VoidCallback? onSetUpRoutine;

  const _EmptyState({required this.message, this.onSetUpRoutine});

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  /// Reads the callback through `widget` rather than capturing it, so the
  /// recognizer survives a rebuild that swaps the callback out.
  late final TapGestureRecognizer _tap = TapGestureRecognizer()
    ..onTap = () => widget.onSetUpRoutine?.call();

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final base =
        TextStyle(fontSize: LiftrType.x13, color: lt.textDim, height: 1.6);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x32),
        child: widget.onSetUpRoutine == null
            ? Text(widget.message, textAlign: TextAlign.center, style: base)
            : Text.rich(
                TextSpan(
                  style: base,
                  children: [
                    TextSpan(text: '${widget.message} — or '),
                    TextSpan(
                      text: 'set up a routine',
                      style: TextStyle(
                        color: lt.accentMid,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                        decorationColor: lt.accentBorder,
                      ),
                      recognizer: _tap,
                    ),
                    const TextSpan(
                        text: ', and days like this fill themselves.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

// ── Exercise Row ──────────────────────────────────────────────
class _ExerciseRow extends StatelessWidget {
  final WorkoutExercises exercise;

  /// When false the row still opens — viewing history is the point — but the
  /// destructive menu is gone and the detail screen opens read-only.
  final bool isEditable;

  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExerciseRow({
    required this.exercise,
    required this.isEditable,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final detail = exercise.catalogDetail;
    final subtitle = detailLine([detail?.equipment, detail?.muscleGroup]);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x16, vertical: LiftrSpacing.x10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: lt.card,
                borderRadius: BorderRadius.circular(LiftrRadii.control),
              ),
              child: Center(
                child: Text(
                  exerciseEmoji(detail?.category, detail?.muscleGroup),
                  style: const TextStyle(fontSize: LiftrType.x16),
                ),
              ),
            ),
            const SizedBox(width: LiftrSpacing.x10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: TextStyle(
                      fontSize: LiftrType.x13,
                      fontWeight: FontWeight.w500,
                      color: lt.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: LiftrSpacing.x2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: LiftrType.x11, color: lt.textMuted)),
                  ],
                ],
              ),
            ),
            // Both modes keep the same 18px trailing icon so the row height
            // never changes; edit just swaps the chevron for an ellipsis that
            // opens the menu. `child:` (not `icon:`) is what keeps the tap
            // target from snapping to the 48px minimum a bare icon menu forces.
            if (isEditable)
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: 'Options',
                color: lt.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LiftrRadii.field),
                  side: BorderSide(
                      color: lt.border, width: LiftrBorders.hairline),
                ),
                onSelected: (v) {
                  if (v == 'edit') onTap();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    height: 40,
                    child: Text('Edit',
                        style: TextStyle(
                            fontSize: LiftrType.x13, color: lt.textPrimary)),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    height: 40,
                    child: Text('Delete',
                        style: TextStyle(
                            fontSize: LiftrType.x13,
                            color: LiftrColors.danger)),
                  ),
                ],
                child: Icon(Icons.more_horiz, size: 18, color: lt.textDim),
              )
            else
              Icon(Icons.chevron_right, size: 18, color: lt.textDim),
          ],
        ),
      ),
    );
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
