import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
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

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
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
          onSignOut: _signOut,
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

  WorkoutSessions? _session;
  List<WorkoutExercises> _exercises = [];

  /// `yyyy-MM-dd` of every day that has a session — the calendar dots. The strip
  /// used to hardcode `hasWorkout: (_) => false`, so no dot ever appeared.
  Set<String> _sessionDates = {};

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final session = await WorkoutService.getWorkoutSession(_selectedDate);
      final sessionId = session?.sessionId;
      final exercises = sessionId != null
          ? await WorkoutService.getWorkoutExercises(sessionId)
          : <WorkoutExercises>[];

      // A generous window around the selected day so paging the calendar left
      // or right doesn't need another round trip.
      final dates = await WorkoutService.getSessionDates(
        _selectedDate.subtract(const Duration(days: 60)),
        _selectedDate.add(const Duration(days: 60)),
      );

      if (mounted) {
        setState(() {
          _session = session;
          _exercises = exercises;
          _sessionDates = dates;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not load this day: $e'),
          backgroundColor: const Color(0xFFE24B4A),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDateSelected(DateTime d) {
    setState(() => _selectedDate = d);
    widget.onDateChanged(d);
    _loadData();
  }

  bool _hasWorkout(DateTime d) => _sessionDates.contains(_key(d));

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseDetailScreen(
          exercise: ex,
          selectedDate: _selectedDate,
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
          backgroundColor: const Color(0xFFE24B4A),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;
    final email = WorkoutService.currentUser?.email ?? '';

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
                        style: TextStyle(fontSize: 12, color: lt.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // Was hardcoded to "Hey, Alex 👋".
                        email.isEmpty
                            ? 'Hey 👋'
                            : 'Hey, ${ProfileTab.displayNameFor(email)} 👋',
                        style: tt.displaySmall,
                      ),
                    ],
                  ),
                ),
                _AvatarMenu(
                  initials:
                      email.isEmpty ? '?' : ProfileTab.initialsFor(email),
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

          const SizedBox(height: 4),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _WorkoutCard(
                date: _selectedDate,
                session: _session,
                exercises: _exercises,
                isLoading: _isLoading,
                onAddExercise: _addExercise,
                onExerciseTap: _openExercise,
                onExerciseDelete: _deleteExercise,
              ),
            ),
          ),
        ],
      ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: lt.card,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 16, color: lt.textSecondary),
              const SizedBox(width: 10),
              Text('Sign out',
                  style: TextStyle(fontSize: 13, color: lt.textSecondary)),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '${monthNames[_weekStart.month - 1]} ${_weekStart.year}',
                style: TextStyle(
                  fontSize: 13,
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
              const SizedBox(width: 8),
              IconSquareButton(
                icon: Icon(Icons.chevron_right,
                    size: 16, color: lt.textSecondary),
                onTap: () => _shiftWeek(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: hasWork ? lt.accentMid : lt.textDim,
                        ),
                      ),
                      const SizedBox(height: 4),
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
                          borderRadius: BorderRadius.circular(8),
                          border: isToday && !isSelected
                              ? Border.all(color: lt.accentBorder, width: 0.5)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 13,
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
                      const SizedBox(height: 4),
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
  final VoidCallback onAddExercise;
  final ValueChanged<WorkoutExercises> onExerciseTap;
  final ValueChanged<WorkoutExercises> onExerciseDelete;

  const _WorkoutCard({
    required this.date,
    required this.session,
    required this.exercises,
    required this.isLoading,
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
        border: Border.all(color: lt.borderSubtle, width: 0.5),
        borderRadius: BorderRadius.circular(24),
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
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.08,
                          color: lt.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        session?.name ?? 'No session',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color:
                              session != null ? lt.textPrimary : lt.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                if (exercises.isNotEmpty)
                  AccentChip('${exercises.length} EX'),
              ],
            ),
          ),

          const Divider(),

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAddExercise,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: lt.accentBg,
                      border: Border.all(color: lt.accentBorder, width: 0.5),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(Icons.add, size: 14, color: lt.accentMid),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add exercise',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: lt.accentMid,
                    ),
                  ),
                ],
              ),
            ),
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
                    ? const _EmptyState()
                    : exercises.isEmpty
                        ? const _EmptyState(
                            message:
                                'No exercises yet.\nTap "Add exercise" to get started.')
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: exercises.length,
                            itemBuilder: (_, i) => _ExerciseRow(
                              exercise: exercises[i],
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

// ── Empty State ───────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(
      {this.message = 'No session found.\nTap "Add exercise" to create one.'});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: lt.textDim, height: 1.6),
        ),
      ),
    );
  }
}

// ── Exercise Row ──────────────────────────────────────────────
class _ExerciseRow extends StatelessWidget {
  final WorkoutExercises exercise;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExerciseRow({
    required this.exercise,
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
                child: Text(
                  exerciseEmoji(detail?.category, detail?.muscleGroup),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: lt.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 11, color: lt.textMuted)),
                  ],
                ],
              ),
            ),
            ThreeDotMenu(onEdit: onTap, onDelete: onDelete),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: TextStyle(fontSize: 16, color: lt.textPrimary)),
      content: Text(message,
          style: TextStyle(fontSize: 13, color: lt.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: lt.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child:
              const Text('Delete', style: TextStyle(color: Color(0xFFE24B4A))),
        ),
      ],
    );
  }
}
