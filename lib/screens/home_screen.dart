import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/prefs.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../utils/format.dart';
import 'add_exercise_screen.dart';
import 'exercise_detail_screen.dart';
import 'log_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';

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
          if (i == 0 && _navIndex == 0) _homeEpoch++; // re-tapping Home refreshes
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

  /// `yyyy-MM-dd` of every day that has a session — the calendar dots. The strip
  /// used to hardcode `hasWorkout: (_) => false`, so no dot ever appeared.
  Set<String> _sessionDates = {};

  /// The session you're on right now, if any — global, not per-date, so a
  /// session left open on Monday still shows on Tuesday.
  WorkoutSessions? _activeSession;

  /// A finished session temporarily unlocked for editing, by session id.
  ///
  /// Deliberately transient UI state, never persisted: the default for anything
  /// you're not currently doing is read-only, so a stray tap can't rewrite last
  /// week's workout. Changing the date or the filter drops it — you've navigated
  /// away, so the unlock has served its purpose.
  String? _editableSessionId;

  bool _isLoading = false;

  /// Whether [s] accepts changes right now.
  ///
  /// The session you're actively in is always editable — that's the whole point
  /// of being in it. Everything else has to be unlocked deliberately.
  bool _canEdit(WorkoutSessions? s) {
    if (s?.sessionId == null) return false;
    if (s!.isActive) return true;
    return s.sessionId == _editableSessionId;
  }

  /// Edit ⇄ Cancel on a finished session.
  ///
  /// The active session never gets here — it's always editable, so there'd be
  /// nothing to toggle.
  void _toggleEdit(WorkoutSessions s) => setState(() {
        _editableSessionId =
            _editableSessionId == s.sessionId ? null : s.sessionId;
      });

  /// Re-locks whatever was unlocked. Called on any navigation away from the
  /// thing you unlocked.
  void _relock() => _editableSessionId = null;

  @override
  void initState() {
    super.initState();
    _loadDisciplines();
    _loadData();
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

  /// The gym session for the day, if there is one.
  WorkoutSessions? get _gymSession {
    for (final s in _sessions) {
      if (s.discipline == Discipline.gymKey) return s;
    }
    return null;
  }

  List<WorkoutExercises> _exercisesFor(WorkoutSessions? s) =>
      _exercisesBySession[s?.sessionId] ?? const [];

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await WorkoutService.getSessionsForDate(_selectedDate);

      // Only gym has children today; when running gets its own child table this
      // is where its rows get loaded alongside.
      final byId = <String, List<WorkoutExercises>>{};
      for (final s in sessions) {
        final id = s.sessionId;
        if (id == null || s.discipline != Discipline.gymKey) continue;
        byId[id] = await WorkoutService.getWorkoutExercises(id);
      }

      // A generous window around the selected day so paging the calendar left
      // or right doesn't need another round trip.
      final dates = await WorkoutService.getSessionDates(
        _selectedDate.subtract(const Duration(days: 60)),
        _selectedDate.add(const Duration(days: 60)),
      );

      // Not scoped to the selected date on purpose: a session left open on
      // Monday is still the one you're on when you open the app on Tuesday.
      final active = await WorkoutService.getActiveSession();

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _exercisesBySession = byId;
          _sessionDates = dates;
          _activeSession = active;
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

  /// The one way a session gets created: declare what you're doing.
  ///
  /// "Start" is about intent, not timing — nothing records a start or end time.
  /// A session stays a plain (date + discipline) container; this just decides
  /// which one you're filling.
  ///
  /// The chips deliberately don't do this job. They filter what you're looking
  /// at; picking a filter must never decide what a tap creates.
  Future<void> _startSession() async {
    if (_disciplines.isEmpty) return;

    // Nothing to choose between — don't make them tap through a one-item menu.
    final chosen = _disciplines.length == 1
        ? _disciplines.first
        : await _pickDiscipline();

    if (chosen == null || !mounted) return;

    // One session at a time. Anything else already open has to end first —
    // whether it's today's gym session or one left running since Monday.
    final active = _activeSession;
    if (active != null && !_isSameSessionAs(active, chosen)) {
      final ok = await _confirmEndActive(active, chosen);
      if (!ok || !mounted) return;

      final id = active.sessionId;
      if (id != null) await WorkoutService.endSession(id);
    }

    if (!mounted) return;
    await _openDiscipline(chosen);
  }

  /// True when the active session *is* the one being started — resuming, not
  /// conflicting, so no prompt.
  bool _isSameSessionAs(WorkoutSessions active, Discipline chosen) {
    final d = active.sessionDate;
    final sameDay = d != null &&
        d.year == _selectedDate.year &&
        d.month == _selectedDate.month &&
        d.day == _selectedDate.day;
    return sameDay && active.discipline == chosen.key;
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
              padding:
                  const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
              child: Text('What are you doing?',
                  style: Theme.of(ctx).textTheme.displaySmall),
            ),
            const SizedBox(height: LiftrSpacing.x12),
            for (final d in _disciplines)
              ListTile(
                leading: Text(d.emoji, style: const TextStyle(fontSize: LiftrType.x22)),
                title: Text(d.label,
                    style: TextStyle(fontSize: LiftrType.x15, color: lt.textPrimary)),
                subtitle: d.description.isEmpty
                    ? null
                    : Text(d.description,
                        style: TextStyle(fontSize: LiftrType.x12, color: lt.textMuted)),
                onTap: () => Navigator.pop(ctx, d),
              ),
            const SizedBox(height: LiftrSpacing.x12),
          ],
        ),
      ),
    );
  }

  /// Routes to a discipline's logging screen. Gym is the only one with a real
  /// one so far; the rest only move the filter, so no empty session row gets
  /// written for a discipline that can't log anything yet.
  Future<void> _openDiscipline(Discipline d) async {
    // No logging screen yet, so don't write an empty session row for it — that
    // would be junk data for something you can't put anything in.
    if (!d.isGym) {
      setState(() => _selectedDiscipline = d.key);
      return;
    }

    setState(() => _selectedDiscipline = Discipline.gymKey);

    try {
      // Create and activate up front rather than leaving it to the add-exercise
      // save: "start" has to mean something even if you don't log a set yet, and
      // an empty active session is a truthful state — you did start it.
      //
      // The name is a placeholder; the add screen pre-fills it and renames on
      // save, so it's editable rather than imposed.
      await WorkoutService.startSession(
        _selectedDate,
        '${d.label} session',
        discipline: d.key,
      );
    } on ActiveSessionExists catch (e) {
      // The check in _startSession is racy by nature — the database is the real
      // guard. Reload so the UI reflects whatever actually won.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'A ${_labelFor(e.active.discipline)} session is already active.'),
          backgroundColor: LiftrColors.danger,
        ));
      }
      await _loadData();
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not start the session: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
      return;
    }

    if (!mounted) return;
    await _addExercise();
  }

  /// Ends the session you're on. Only a flag flip — everything logged stays.
  Future<void> _endSession() async {
    final active = _activeSession;
    final id = active?.sessionId;
    if (id == null) return;

    try {
      await WorkoutService.endSession(id);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not end the session: $e'),
          backgroundColor: LiftrColors.danger,
        ));
      }
    }
  }

  /// Asks before ending whatever is currently open, so nothing is ever ended
  /// silently — logging today's lifts into Monday's forgotten session would be
  /// far worse than one extra tap.
  ///
  /// Wording adapts: switching disciplines today reads differently from a
  /// session you left open days ago, even though the rule behind both is the
  /// same one-at-a-time invariant.
  Future<bool> _confirmEndActive(
      WorkoutSessions active, Discipline next) async {
    final activeLabel = _labelFor(active.discipline);
    final isStale = !_isToday(active.sessionDate);
    final when = active.sessionDate == null
        ? 'an earlier day'
        : _formattedFullDate(active.sessionDate!);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final lt = ctx.lt;
        return AlertDialog(
          backgroundColor: lt.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LiftrRadii.card)),
          title: Text(
            isStale
                ? 'You left a $activeLabel session open'
                : 'End your $activeLabel session?',
            style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary),
          ),
          content: Text(
            isStale
                ? 'That $activeLabel session from $when is still open, and only '
                    'one session can be active at a time.\n\nEnd it and start '
                    '${next.label.toLowerCase()}? Everything you logged is kept.'
                : 'Only one session can be active at a time, so your '
                    '$activeLabel session ends before ${next.label.toLowerCase()} '
                    'starts.\n\nEverything you logged is kept.',
            style:
                TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: lt.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End & continue',
                  style: TextStyle(color: LiftrColors.accent)),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  bool _isToday(DateTime? d) {
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Discipline _disciplineFor(String key) => _disciplines.firstWhere(
        (d) => d.key == key,
        orElse: () => Discipline(key: key, label: key, emoji: '•'),
      );

  String _labelFor(String key) => _disciplineFor(key).label;
  String _emojiFor(String key) => _disciplineFor(key).emoji;

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

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;

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
                        style: TextStyle(fontSize: LiftrType.x12, color: lt.textMuted),
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

          // Which session am I on? Sits directly above the card it filters.
          _DisciplineChips(
            disciplines: _disciplines,
            selected: _selectedDiscipline,
            onSelect: (key) => setState(() {
              _selectedDiscipline = key;
              _relock(); // changed the lens — anything unlocked re-locks
            }),
          ),

          const SizedBox(height: LiftrSpacing.x10),

          // Which session am I on? Shown regardless of the filter, because the
          // active session is global — hiding it behind a chip would let you
          // forget one was open at all.
          if (_activeSession != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, LiftrSpacing.x10),
              child: _ActiveSessionBanner(
                session: _activeSession!,
                label: _labelFor(_activeSession!.discipline),
                emoji: _emojiFor(_activeSession!.discipline),
                isStale: !_isToday(_activeSession!.sessionDate),
                dateLabel: _activeSession!.sessionDate == null
                    ? ''
                    : _formattedFullDate(_activeSession!.sessionDate!),
              ),
            ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _dayContent(),
            ),
          ),

          // The only route to a new session. Always available, whatever the
          // filter says — the filter is a lens, not a mode.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: _activeSession != null
                ? _EndSessionButton(
                    label: _labelFor(_activeSession!.discipline),
                    onEnd: _endSession,
                  )
                : ElevatedButton(
                    onPressed: _disciplines.isEmpty ? null : _startSession,
                    child: Text(
                      _disciplines.length == 1
                          ? 'Start ${_disciplines.first.label.toLowerCase()} session'
                          : 'Start session',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// The card(s) under the chips: every discipline's session on "All", or just
  /// the one you filtered to.
  Widget _dayContent() {
    if (_selectedDiscipline == Discipline.gymKey) {
      final gym = _gymSession;
      return _WorkoutCard(
        date: _selectedDate,
        session: gym,
        exercises: _exercisesFor(gym),
        isLoading: _isLoading,
        isEditable: _canEdit(gym),
        // Null for the active session: it's always editable, so there's nothing
        // to toggle — and offering "Cancel" would imply you could lock it.
        onToggleEdit: (gym == null || gym.isActive)
            ? null
            : () => _toggleEdit(gym),
        onAddExercise: _addExercise,
        onExerciseTap: _openExercise,
        onExerciseDelete: _deleteExercise,
      );
    }

    // A non-gym discipline: the session row is real, but nothing can log into it
    // until that discipline grows a child table and a UI.
    if (_selectedDiscipline != null) {
      final d = _disciplines.firstWhere(
        (x) => x.key == _selectedDiscipline,
        orElse: () => Discipline(key: _selectedDiscipline!, label: '', emoji: '•'),
      );
      return _ComingSoonCard(discipline: d);
    }

    // "All" — everything logged today, whatever the discipline.
    return _AllSessionsCard(
      sessions: _sessions,
      disciplines: _disciplines,
      exercisesBySession: _exercisesBySession,
      isLoading: _isLoading,
      onOpenDiscipline: (key) => setState(() {
        _selectedDiscipline = key;
        _relock();
      }),
    );
  }


  String _formattedFullDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}

// ── Active session ────────────────────────────────────────────
/// "You're on this one." The answer to which session is current — no timer, no
/// elapsed clock, just what's open.
class _ActiveSessionBanner extends StatelessWidget {
  final WorkoutSessions session;
  final String label;
  final String emoji;

  /// Left open on an earlier day. Worth calling out — it's almost always a
  /// forgotten session rather than a deliberate one.
  final bool isStale;
  final String dateLabel;

  const _ActiveSessionBanner({
    required this.session,
    required this.label,
    required this.emoji,
    required this.isStale,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x10),
      decoration: BoxDecoration(
        color: lt.accentBg,
        border: Border.all(color: LiftrColors.accent, width: LiftrBorders.thin),
        borderRadius: BorderRadius.circular(LiftrRadii.card),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: LiftrType.x18)),
          const SizedBox(width: LiftrSpacing.x10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: LiftrColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: LiftrSpacing.x6),
                    Text(
                      isStale ? 'STILL OPEN' : 'IN THIS SESSION',
                      style: TextStyle(
                        fontSize: LiftrType.x10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: lt.accentMid,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LiftrSpacing.x3),
                Text(
                  session.name ?? label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: LiftrType.x14,
                    fontWeight: FontWeight.w500,
                    color: lt.textPrimary,
                  ),
                ),
                if (isStale && dateLabel.isNotEmpty) ...[
                  const SizedBox(height: LiftrSpacing.x2),
                  Text(
                    'from $dateLabel',
                    style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EndSessionButton extends StatelessWidget {
  final String label;
  final VoidCallback onEnd;
  const _EndSessionButton({required this.label, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    // Outlined rather than filled: ending is the exit, not the thing we're
    // nudging you toward.
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onEnd,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: lt.border, width: LiftrBorders.thin),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LiftrRadii.button)),
        ),
        child: Text(
          'End ${label.toLowerCase()} session',
          style: TextStyle(
            fontSize: LiftrType.x15,
            fontWeight: FontWeight.w600,
            color: lt.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Discipline chips ──────────────────────────────────────────
/// "What session am I on?" — an All chip plus one per discipline you train.
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(LiftrRadii.sheet)),
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
                leading: Text(d.emoji, style: const TextStyle(fontSize: LiftrType.x20)),
                title: Text(d.label,
                    style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary)),
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
/// Everything logged on this day, whatever the discipline — an overview.
///
/// Deliberately a list of summary rows rather than a stack of full cards: the
/// gym card sizes itself with an Expanded and would need an arbitrary fixed
/// height to sit in a scroll view. Tap a row to jump to that discipline's chip,
/// which is where the detail lives.
class _AllSessionsCard extends StatelessWidget {
  final List<WorkoutSessions> sessions;
  final List<Discipline> disciplines;
  final Map<String, List<WorkoutExercises>> exercisesBySession;
  final bool isLoading;
  final ValueChanged<String> onOpenDiscipline;

  const _AllSessionsCard({
    required this.sessions,
    required this.disciplines,
    required this.exercisesBySession,
    required this.isLoading,
    required this.onOpenDiscipline,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: LiftrColors.accent),
        ),
      );
    }

    if (sessions.isEmpty) {
      return const _EmptyState(
        message: 'Nothing logged today.\nTap "Start session" below to begin.',
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final s in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: LiftrSpacing.x10),
            child: _SessionSummaryRow(
              session: s,
              discipline: _lookup(s.discipline),
              subtitle: _subtitleFor(s),
              onTap: () => onOpenDiscipline(s.discipline),
            ),
          ),
      ],
    );
  }

  String _subtitleFor(WorkoutSessions s) {
    if (s.discipline != Discipline.gymKey) return _lookup(s.discipline).label;
    final n = (exercisesBySession[s.sessionId] ?? const []).length;
    return '$n exercise${n == 1 ? '' : 's'}';
  }

  Discipline _lookup(String key) => disciplines.firstWhere(
        (d) => d.key == key,
        orElse: () => Discipline(key: key, label: key, emoji: '•'),
      );
}

class _SessionSummaryRow extends StatelessWidget {
  final WorkoutSessions session;
  final Discipline discipline;
  final String subtitle;
  final VoidCallback onTap;

  const _SessionSummaryRow({
    required this.session,
    required this.discipline,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LiftrRadii.card),
      child: Container(
        padding: const EdgeInsets.all(LiftrSpacing.x14),
        decoration: BoxDecoration(
          color: lt.surface,
          border:
              Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.card),
        ),
        child: Row(
          children: [
            Text(discipline.emoji, style: const TextStyle(fontSize: LiftrType.x18)),
            const SizedBox(width: LiftrSpacing.x10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.name ?? discipline.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: LiftrType.x14,
                      fontWeight: FontWeight.w500,
                      color: lt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: LiftrSpacing.x2),
                  Text(subtitle,
                      style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted)),
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
        border: Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.sheet),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(discipline.emoji, style: const TextStyle(fontSize: LiftrType.x32)),
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
                style: TextStyle(fontSize: LiftrType.x12, color: lt.textDim, height: 1.5),
              ),
            ],
          ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LiftrRadii.field)),
      color: lt.card,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 16, color: lt.textSecondary),
              const SizedBox(width: LiftrSpacing.x10),
              Text('Sign out',
                  style: TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary)),
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
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '${monthNames[_weekStart.month - 1]} ${_weekStart.year}',
                style: TextStyle(
                  fontSize: LiftrType.x13,
                  fontWeight: FontWeight.w500,
                  color: lt.textPrimary,
                ),
              ),
              const Spacer(),
              IconSquareButton(
                icon: Icon(Icons.chevron_left,
                    size: 16, color: lt.textSecondary),
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
                        dayNames[i],
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
                              ? Border.all(color: lt.accentBorder, width: LiftrBorders.hairline)
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
                          decoration: const BoxDecoration(
                            color: LiftrColors.accent,
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

  /// Read-only unless this is the session you're in, or you've tapped Edit.
  final bool isEditable;

  /// Toggles Edit ⇄ Cancel. Null when there's nothing to toggle — no session, or
  /// the active one (always editable).
  final VoidCallback? onToggleEdit;

  final VoidCallback onAddExercise;
  final ValueChanged<WorkoutExercises> onExerciseTap;
  final ValueChanged<WorkoutExercises> onExerciseDelete;

  const _WorkoutCard({
    required this.date,
    required this.session,
    required this.exercises,
    required this.isLoading,
    required this.isEditable,
    required this.onToggleEdit,
    required this.onAddExercise,
    required this.onExerciseTap,
    required this.onExerciseDelete,
  });

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    // Compares the year too — the old version called any Mar 3 "Today".
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return Container(
      decoration: BoxDecoration(
        color: lt.surface,
        border: Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
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
                        '${_dayLabel(date)} · ${months[date.month - 1]} ${date.day}',
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
                          color:
                              session != null ? lt.textPrimary : lt.textDim,
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

          // Only offered once the session exists, and only while editable.
          // Adding to a session you're in is a within-session action; letting it
          // conjure the session would make the filter a mode again, and
          // "Start session" is the one place that decides that.
          if (session != null && isEditable) ...[
            const Divider(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAddExercise,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: LiftrSpacing.x16, vertical: LiftrSpacing.x10),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: lt.accentBg,
                        border: Border.all(
                            color: lt.accentBorder,
                            width: LiftrBorders.hairline),
                        borderRadius: BorderRadius.circular(LiftrRadii.inset),
                      ),
                      child: Icon(Icons.add, size: 14, color: lt.accentMid),
                    ),
                    const SizedBox(width: LiftrSpacing.x8),
                    Text(
                      'Add exercise',
                      style: TextStyle(
                        fontSize: LiftrType.x13,
                        fontWeight: FontWeight.w500,
                        color: lt.accentMid,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

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
                    ? const _EmptyState()
                    : exercises.isEmpty
                        ? _EmptyState(
                            message: isEditable
                                ? 'No exercises yet.\nTap "Add exercise" to get started.'
                                : 'Nothing was logged in this session.')
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: LiftrSpacing.x6),
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
          isEditing ? 'CANCEL' : 'EDIT',
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
class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(
      {this.message =
          'Nothing here yet.\nTap "Start session" below to begin.'});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: LiftrType.x13, color: lt.textDim, height: 1.6),
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
        padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x16, vertical: LiftrSpacing.x10),
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
                        style: TextStyle(fontSize: LiftrType.x11, color: lt.textMuted)),
                  ],
                ],
              ),
            ),
            if (isEditable)
              ThreeDotMenu(onEdit: onTap, onDelete: onDelete)
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LiftrRadii.card)),
      title: Text(title, style: TextStyle(fontSize: LiftrType.x16, color: lt.textPrimary)),
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
