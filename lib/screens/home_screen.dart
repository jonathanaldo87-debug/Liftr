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
import 'login_screen.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';
import 'routines_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;
  DateTime _selectedDate = DateTime.now();

  int _homeEpoch = 0;

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Widget get _tab {
    switch (_navIndex) {
      case 1:
        return const ProgressTab();
      case 2:
        return ProfileTab(onSignOut: _signOut);
      default:
        return _TodayTab(
          key: ValueKey('${_selectedDate.toIso8601String()}#$_homeEpoch'),
          initialDate: _selectedDate,
          onDateChanged: (d) => _selectedDate = d,
          onSignOut: () => confirmAndSignOut(context, _signOut),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tab,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() {
          if (i == 0 && _navIndex == 0) _homeEpoch++;
          _navIndex = i;
        }),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
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

  List<Discipline> _disciplines = [];

  String? _selectedDiscipline;

  List<WorkoutSessions> _sessions = [];

  Map<String, List<WorkoutExercises>> _exercisesBySession = {};

  Map<String, List<DistanceInterval>> _runsBySession = {};

  Set<String> _sessionDates = {};

  WeeklySchedule _schedule = {};

  Routine? get _scheduledRoutine => _schedule[_selectedDate.weekday];

  bool _hasRoutines = true;

  String? _editableSessionId;

  bool _isLoading = false;

  bool _canEdit(WorkoutSessions? s) {
    if (isFutureDay(_selectedDate)) return false;
    if (_isToday(_selectedDate)) return true;
    final id = s?.sessionId;
    return id != null && id == _editableSessionId;
  }

  void _toggleEdit(WorkoutSessions s) => setState(() {
        _editableSessionId =
            _editableSessionId == s.sessionId ? null : s.sessionId;
      });

  VoidCallback? _toggleFor(WorkoutSessions? s) {
    if (s == null || !isPastDay(_selectedDate)) return null;
    return () => _toggleEdit(s);
  }

  void _relock() => _editableSessionId = null;

  bool _recoveryChecked = false;

  @override
  void initState() {
    super.initState();
    _loadDisciplines();
    _loadSchedule();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferRecovery());
  }

  Future<void> _loadDisciplines() async {
    final all = await WorkoutService.getDisciplines();
    if (!mounted) return;

    final enabled = Prefs.enabledDisciplines;
    setState(() {
      _disciplines = all.where((d) => enabled.contains(d.key)).toList();
      if (_disciplines.isEmpty) _disciplines = all;
    });
  }

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
    } catch (_) {}
  }

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

  WorkoutSessions? _sessionFor(String disciplineKey) {
    for (final s in _sessions) {
      if (s.discipline == disciplineKey) return s;
    }
    return null;
  }

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

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _exercisesBySession = byId;
          _runsBySession = runsById;
        });
      }

      await _loadSessionDates(_selectedDate);
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
      _relock();
    });
    widget.onDateChanged(d);
    _loadData();
  }

  Future<void> _loadSessionDates(DateTime around) async {
    final dates = await WorkoutService.getSessionDates(
      DateTime(around.year, around.month - 2),
      DateTime(around.year, around.month + 3, 0),
    );
    if (mounted) setState(() => _sessionDates = dates);
  }

  bool _hasWorkout(DateTime d) => _sessionDates.contains(_key(d));

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Discipline? get _target {
    if (_disciplines.length == 1) return _disciplines.first;
    final key = _selectedDiscipline;
    if (key == null) return null;
    return _disciplineFor(key);
  }

  Future<void> _logSomething() async {
    if (_disciplines.isEmpty) return;

    if (isFutureDay(_selectedDate)) return;

    final chosen = _target ?? await _pickDiscipline();
    if (chosen == null || !mounted) return;

    await _openDiscipline(chosen);
  }

  String get _addLabel {
    final d = _target;
    if (d == null) return 'Log something';
    if (d.logsDistance) return 'Add a run';
    if (d.isGym) return 'Add exercise';
    return 'Add ${d.label.toLowerCase()}';
  }

  bool get _canLogHere {
    if (isFutureDay(_selectedDate)) return false;
    final d = _target;
    return d == null || d.logsDistance || d.isGym;
  }

  String get _emptyHint {
    if (isFutureDay(_selectedDate)) return kNotYetHint;
    if (!_canLogHere) return 'Nothing logged on this day.';
    if (_routineNudge != null) return 'Nothing logged.\nTap "$_addLabel" below';
    return 'Nothing logged.\nTap "$_addLabel" below to put something in.';
  }

  VoidCallback? get _routineNudge =>
      (_hasRoutines || !_canLogHere) ? null : _openRoutines;

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

  Future<void> _openDiscipline(Discipline d) async {
    setState(() => _selectedDiscipline = d.key);

    if (d.logsDistance) {
      await _addDistance(d);
      return;
    }

    if (!d.isGym) return;

    await _addExercise();
  }

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
    await _loadData();
    if (saved == true) _relock();
  }

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
              child: Text('Add a run',
                  style: Theme.of(ctx).textTheme.displaySmall),
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

  void _unlockIfPast(WorkoutSessions? s) {
    final id = s?.sessionId;
    if (id != null && isPastDay(_selectedDate)) {
      setState(() => _editableSessionId = id);
    }
  }

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

  Future<void> _deleteSession(WorkoutSessions s, Discipline d) async {
    final id = s.sessionId;
    if (id == null) return;

    final n =
        d.logsDistance ? _intervalsFor(s).length : _exercisesFor(s).length;
    final unit = d.logsDistance ? 'run' : 'exercise';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Delete ${s.name ?? 'this session'}?',
        message: n == 0
            ? 'This session is empty, so nothing logged is lost.'
            : 'Its $n $unit${n == 1 ? '' : 's'} and everything logged in '
                'them will be permanently removed.',
      ),
    );
    if (confirmed != true) return;

    try {
      await WorkoutService.deleteWorkoutSession(id);
      _relock();
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete it: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    }
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
            onVisibleMonthChanged: _loadSessionDates,
          ),
          const SizedBox(height: LiftrSpacing.x12),
          _DisciplineChips(
            disciplines: _disciplines,
            selected: _selectedDiscipline,
            // A filter row earns its space only once there's more than one
            // thing on the day to filter between.
            showFullRow: _sessions.length >= 2,
            onSelect: (key) => setState(() {
              _selectedDiscipline = key;
              _relock();
            }),
          ),
          const SizedBox(height: LiftrSpacing.x10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _dayContent(),
            ),
          ),
          if (primaryAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: primaryAction,
            ),
        ],
      ),
    );
  }

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

  VoidCallback? _fillFor(String disciplineKey) {
    final r = _scheduledRoutine;
    if (r == null || r.discipline != disciplineKey) return null;
    if (r.isEmpty || isFutureDay(_selectedDate)) return null;
    return () => _fillFromRoutine(r);
  }

  Widget _dayContent() {
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
        onFill:
            isFutureDay(_selectedDate) ? null : () => _fillFromRoutine(routine),
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
        onFillRoutine: _fillFor(Discipline.gymKey),
        onDeleteSession: gym == null
            ? null
            : () => _deleteSession(gym, _disciplineFor(Discipline.gymKey)),
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

      if (d.logsDistance) {
        final session = _sessionFor(d.key);
        return _RunCard(
          date: _selectedDate,
          discipline: d,
          session: session,
          intervals: _intervalsFor(session),
          routine: routine?.discipline == d.key ? routine : null,
          isLoading: _isLoading,
          isEditable: _canEdit(session),
          onToggleEdit: _toggleFor(session),
          onFillRoutine: _fillFor(d.key),
          onDeleteSession:
              session == null ? null : () => _deleteSession(session, d),
          onStartLeg: _isToday(_selectedDate)
              ? (from) => _startPlannedLeg(d, routine, from)
              : null,
          onOpenInterval: (i) => _openRun(
            i,
            readOnly: !_canEdit(session),
            otherRunsToday: _intervalsFor(session).length - 1,
          ),
        );
      }

      return _ComingSoonCard(discipline: d);
    }

    return _AllSessionsCard(
      date: _selectedDate,
      sessions: _sessions,
      disciplines: _disciplines,
      exercisesBySession: _exercisesBySession,
      runsBySession: _runsBySession,
      isLoading: _isLoading,
      emptyMessage: _emptyHint,
      onSetUpRoutine: _routineNudge,
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

class _DisciplineChips extends StatelessWidget {
  final List<Discipline> disciplines;

  final String? selected;
  final ValueChanged<String?> onSelect;

  /// Whether the day has enough going on to be worth a whole row of chips.
  ///
  /// Most days hold one session, and a scrolling filter row over one thing is
  /// noise. The pill still gets you anywhere the row could.
  final bool showFullRow;

  const _DisciplineChips({
    required this.disciplines,
    required this.selected,
    required this.onSelect,
    required this.showFullRow,
  });

  static const _maxVisible = 3;

  @override
  Widget build(BuildContext context) {
    if (disciplines.isEmpty) return const SizedBox.shrink();

    // Nothing to filter between.
    if (disciplines.length < 2) return const SizedBox.shrink();

    if (!showFullRow) return _pill(context);

    final overflows = disciplines.length > _maxVisible;
    var visible = overflows
        ? disciplines.take(_maxVisible - 1).toList()
        : List<Discipline>.from(disciplines);
    var hidden = disciplines.where((d) => !visible.contains(d)).toList();

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
              onTap: () => _pickDiscipline(context),
            ),
          ],
        ],
      ),
    );
  }

  /// The quiet form: what you're looking at, and a way to change it.
  Widget _pill(BuildContext context) {
    final current = selected == null
        ? null
        : disciplines.firstWhere((d) => d.key == selected,
            orElse: () =>
                Discipline(key: selected!, label: selected!, emoji: '•'));

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
        child: _Chip(
          label: current?.label ?? 'All',
          emoji: current?.emoji,
          trailing: Icons.expand_more,
          isSelected: false,
          onTap: () => _pickDiscipline(context),
        ),
      ),
    );
  }

  /// Every lens on offer, All included -- the pill has no row behind it to fall
  /// back on, so the sheet has to be complete.
  Future<void> _pickDiscipline(BuildContext context) async {
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
            const SectionLabel('Show'),
            const SizedBox(height: LiftrSpacing.x8),
            ListTile(
              leading: Icon(Icons.apps, size: 20, color: lt.textSecondary),
              title: Text('All',
                  style: TextStyle(
                      fontSize: LiftrType.x14, color: lt.textPrimary)),
              trailing: selected == null
                  ? Icon(Icons.check, size: 18, color: lt.accentStrong)
                  : null,
              onTap: () => Navigator.pop(ctx, _allSentinel),
            ),
            for (final d in disciplines)
              ListTile(
                leading: Text(d.emoji,
                    style: const TextStyle(fontSize: LiftrType.x20)),
                title: Text(d.label,
                    style: TextStyle(
                        fontSize: LiftrType.x14, color: lt.textPrimary)),
                trailing: selected == d.key
                    ? Icon(Icons.check, size: 18, color: lt.accentStrong)
                    : null,
                onTap: () => Navigator.pop(ctx, d.key),
              ),
            const SizedBox(height: LiftrSpacing.x8),
          ],
        ),
      ),
    );

    // Null is "dismissed"; All needs a value of its own to be distinguishable.
    if (picked == null) return;
    onSelect(picked == _allSentinel ? null : picked);
  }

  static const _allSentinel = '__all__';
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

class _AllSessionsCard extends StatelessWidget {
  final DateTime date;
  final List<WorkoutSessions> sessions;
  final List<Discipline> disciplines;
  final Map<String, List<WorkoutExercises>> exercisesBySession;
  final Map<String, List<DistanceInterval>> runsBySession;
  final bool isLoading;

  final String emptyMessage;

  final VoidCallback? onSetUpRoutine;

  final bool Function(WorkoutSessions) isEditable;

  final ValueChanged<String> onOpenDiscipline;

  final ValueChanged<WorkoutExercises> onExerciseTap;
  final ValueChanged<WorkoutExercises> onExerciseDelete;

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
          _CardHeader(
            date: date,
            title: sessions.isEmpty ? 'No sessions' : 'Everything logged',
            isPlaceholder: sessions.isEmpty,
            badge: sessions.isEmpty
                ? null
                : '${sessions.length} session${sessions.length == 1 ? '' : 's'}',
          ),
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
                : sessions.isEmpty
                    ? _EmptyState(
                        message: emptyMessage,
                        onSetUpRoutine: onSetUpRoutine,
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: LiftrSpacing.x6),
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

  List<Widget> _group(WorkoutSessions s, {required bool isFirst}) {
    final d = _lookup(s.discipline);
    final rows = _rowsFor(s, d);

    return [
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

class _RoutinePromptCard extends StatefulWidget {
  final DateTime date;
  final Routine routine;
  final String emoji;

  final bool isDistance;

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
  bool _filling = false;

  Future<void> _fill() async {
    setState(() => _filling = true);
    widget.onFill!();
  }

  bool get _isRun => widget.routine.intervals.isNotEmpty || widget.isDistance;

  String get _contents {
    final r = widget.routine;
    if (r.intervals.isNotEmpty) {
      return [
        for (final i in r.intervals) formatDistance(i.targetDistanceMeters)
      ].join(' · ');
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

class _RunCard extends StatelessWidget {
  final DateTime date;

  final Discipline discipline;

  final WorkoutSessions? session;
  final List<DistanceInterval> intervals;

  final Routine? routine;

  final bool isLoading;

  final bool isEditable;

  final VoidCallback? onToggleEdit;

  final VoidCallback? onFillRoutine;

  final VoidCallback? onDeleteSession;

  final ValueChanged<DistanceInterval> onOpenInterval;

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
    required this.onFillRoutine,
    required this.onDeleteSession,
    required this.onOpenInterval,
    required this.onStartLeg,
  });

  List<PlannedLeg> get _planned => routine?.legs ?? const [];

  DistanceInterval? _runFor(int slot) {
    for (final i in intervals) {
      if (i.planSlot == slot) return i;
    }
    return null;
  }

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
          _CardHeader(
            date: date,
            title: session?.name ?? routine?.name ?? 'No session',
            isPlaceholder: (session ?? routine) == null,
            badge: _planned.isNotEmpty
                ? '${intervals.length}/${_planned.length}'
                : intervals.isEmpty
                    ? null
                    : formatDistance(totals.distanceMeters),
            isEditable: isEditable,
            onToggleEdit: onToggleEdit,
            onFillRoutine: onFillRoutine,
            onDelete: onDeleteSession,
          ),
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
                          for (final leg in _planned) _legRow(leg),
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

  String get _rowName => session?.name?.trim().isNotEmpty == true
      ? session!.name!
      : discipline.label;

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
      onStart: onStartLeg == null ? null : () => onStartLeg!(leg.slot),
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

class _PlannedLegRow extends StatelessWidget {
  final int legNumber;
  final double targetMeters;

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

class _IntervalRow extends StatelessWidget {
  final DistanceInterval interval;

  final String emoji;

  final String name;

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
            Icon(Icons.chevron_right, size: 18, color: lt.textDim),
          ],
        ),
      ),
    );
  }
}

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

class _CalendarStrip extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool Function(DateTime) hasWorkout;

  final ValueChanged<DateTime> onVisibleMonthChanged;

  const _CalendarStrip({
    required this.selectedDate,
    required this.onDateSelected,
    required this.hasWorkout,
    required this.onVisibleMonthChanged,
  });

  @override
  State<_CalendarStrip> createState() => _CalendarStripState();
}

class _CalendarStripState extends State<_CalendarStrip> {
  late DateTime _weekStart = _getWeekStart(widget.selectedDate);

  late DateTime _month = _firstOfMonth(widget.selectedDate);

  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _CalendarStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedDate != widget.selectedDate) {
      _weekStart = _getWeekStart(widget.selectedDate);
      _month = _firstOfMonth(widget.selectedDate);
    }
  }

  DateTime _getWeekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _month = _firstOfMonth(_weekStart);
      } else {
        _weekStart = _getWeekStart(widget.selectedDate);
      }
    });
    widget.onVisibleMonthChanged(_expanded ? _month : _weekStart);
  }

  void _shift(int delta) {
    setState(() {
      if (_expanded) {
        _month = DateTime(_month.year, _month.month + delta);
      } else {
        _weekStart = _weekStart.add(Duration(days: delta * 7));
      }
    });
    widget.onVisibleMonthChanged(_expanded ? _month : _weekStart);
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final label = _expanded ? _month : _weekStart;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
      child: GestureDetector(
        // Paging is a swipe now rather than two buttons. The day cells keep
        // their own taps — a horizontal drag and a tap are different gestures,
        // so they don't compete.
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity;
          if (v == null) return;
          if (v < 0) {
            _shift(1);
          } else if (v > 0) {
            _shift(-1);
          }
        },
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _toggle,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Text(
                        monthYear(label),
                        style: TextStyle(
                          fontSize: LiftrType.x13,
                          fontWeight: FontWeight.w500,
                          color: lt.textPrimary,
                        ),
                      ),
                      const SizedBox(width: LiftrSpacing.x4),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more,
                            size: 18, color: lt.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // A gesture leaves nothing on screen to discover it by, so the
                // hint stands in for the buttons it replaced.
                Text(
                  '‹ swipe ›',
                  style: TextStyle(
                    fontSize: LiftrType.x11,
                    fontWeight: FontWeight.w400,
                    color: lt.textDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LiftrSpacing.x12),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded ? _monthGrid(lt) : _weekRow(lt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekRow(LiftrTheme lt) {
    return Row(
      children: List.generate(7, (i) {
        final day = _weekStart.add(Duration(days: i));
        return Expanded(
          child: Column(
            children: [
              Text(
                kWeekdaysUpper[i],
                style: TextStyle(
                  fontSize: LiftrType.x10,
                  fontWeight: FontWeight.w500,
                  color: widget.hasWorkout(day) ? lt.accentMid : lt.textDim,
                ),
              ),
              const SizedBox(height: LiftrSpacing.x4),
              _dayCell(lt, day),
            ],
          ),
        );
      }),
    );
  }

  Widget _monthGrid(LiftrTheme lt) {
    final cells = monthGrid(_month);
    final rows = cells.length ~/ 7;

    return Column(
      children: [
        Row(
          children: [
            for (final w in kWeekdaysUpper)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: LiftrType.x10,
                      fontWeight: FontWeight.w500,
                      color: lt.textDim,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: LiftrSpacing.x8),
        for (var r = 0; r < rows; r++) ...[
          Row(
            children: List.generate(7, (c) {
              final day = cells[r * 7 + c];
              if (day == null) {
                return const Expanded(child: SizedBox(height: 40));
              }
              return Expanded(child: _dayCell(lt, day));
            }),
          ),
          if (r < rows - 1) const SizedBox(height: LiftrSpacing.x6),
        ],
      ],
    );
  }

  Widget _dayCell(LiftrTheme lt, DateTime day) {
    final isSelected = isSameDay(day, widget.selectedDate);
    final today = isToday(day);
    final hasWork = widget.hasWorkout(day);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onDateSelected(day),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isSelected
                  ? LiftrColors.accent
                  : today
                      ? lt.accentBg
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(LiftrRadii.tile),
              border: today && !isSelected
                  ? Border.all(
                      color: lt.accentBorder, width: LiftrBorders.hairline)
                  : null,
            ),
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: LiftrType.x13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? LiftrColors.accentText : lt.textSecondary,
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
                color: lt.accentStrong,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final DateTime date;
  final WorkoutSessions? session;
  final List<WorkoutExercises> exercises;
  final bool isLoading;

  final String emptyMessage;

  final VoidCallback? onSetUpRoutine;

  final bool isEditable;

  final VoidCallback? onToggleEdit;

  final VoidCallback? onFillRoutine;

  final VoidCallback? onDeleteSession;

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
    required this.onFillRoutine,
    required this.onDeleteSession,
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
          _CardHeader(
            date: date,
            title: session?.name ?? 'No session',
            isPlaceholder: session == null,
            badge: exercises.isEmpty ? null : '${exercises.length} EX',
            isEditable: isEditable,
            onToggleEdit: onToggleEdit,
            onFillRoutine: onFillRoutine,
            onDelete: onDeleteSession,
          ),
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

class _CardHeader extends StatelessWidget {
  final DateTime date;
  final String title;

  /// Dimmed when the title stands in for a session that doesn't exist yet.
  final bool isPlaceholder;

  final String? badge;

  final bool isEditable;
  final VoidCallback? onToggleEdit;

  /// Puts the day's routine into this session. Null when no routine is
  /// scheduled — which is why this lives in the menu rather than as a button:
  /// most days it isn't there at all.
  final VoidCallback? onFillRoutine;

  final VoidCallback? onDelete;

  const _CardHeader({
    required this.date,
    required this.title,
    required this.badge,
    this.isPlaceholder = false,
    this.isEditable = false,
    this.onToggleEdit,
    this.onFillRoutine,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${dayLabel(date)} · ${shortDate(date)}',
                  style: TextStyle(
                    fontSize: LiftrType.x11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.08,
                    color: lt.textMuted,
                  ),
                ),
              ),
              if (badge != null) AccentChip(badge!),
            ],
          ),
          const SizedBox(height: LiftrSpacing.x6),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: LiftrType.x22,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: isPlaceholder ? lt.textDim : lt.textPrimary,
                  ),
                ),
              ),
              if (_actions.isNotEmpty)
                ThreeDotMenu(actions: _actions, boxed: true),
            ],
          ),
        ],
      ),
    );
  }

  /// Everything you can do to this session, in one place.
  ///
  /// The EDIT chip used to sit beside the menu doing exactly one of these; two
  /// permanent controls for a card whose usual state needs neither is what this
  /// collapses. Built from whichever callbacks the card actually passed, so an
  /// entry here always goes somewhere.
  List<MenuAction> get _actions => [
        if (onToggleEdit != null)
          MenuAction(isEditable ? 'Done editing' : 'Edit sets', onToggleEdit!),
        if (onFillRoutine != null)
          MenuAction('Fill from routine', onFillRoutine!),
        if (onDelete != null)
          MenuAction('Delete session', onDelete!, isDanger: true),
      ];
}

const kNotYetHint = "Nothing here yet.\nThis day hasn't happened.";

class _EmptyState extends StatefulWidget {
  final String message;

  final VoidCallback? onSetUpRoutine;

  const _EmptyState({required this.message, this.onSetUpRoutine});

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
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

class _ExerciseRow extends StatelessWidget {
  final WorkoutExercises exercise;

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
