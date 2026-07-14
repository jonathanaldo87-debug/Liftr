import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'add_exercise_screen.dart';
import 'exercise_detail_screen.dart';
import 'login_screen.dart';

// ── Home Screen ───────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDate = DateTime.now();
  int _navIndex = 0;

  WorkoutSessions? _session;
  List<WorkoutExercises> _exercises = [];
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
      final exercises = session?.sessionId != null
          ? await WorkoutService.getWorkoutExercises(session!.sessionId!)
          : <WorkoutExercises>[];
      if (mounted) {
        setState(() {
          _session = session;
          _exercises = exercises;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDateSelected(DateTime d) {
    setState(() => _selectedDate = d);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────
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
                        Text('Hey, Alex 👋', style: tt.displaySmall),
                      ],
                    ),
                  ),
                  _AvatarMenu(
                    onSignOut: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),

            // ── Calendar strip ───────────────────────────────
            _CalendarStrip(
              selectedDate: _selectedDate,
              onDateSelected: _onDateSelected,
              hasWorkout: (_) => false,
            ),

            const SizedBox(height: 4),

            // ── Workout card ─────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: _WorkoutCard(
                  date: _selectedDate,
                  session: _session,
                  exercises: _exercises,
                  isLoading: _isLoading,
                  onAddExercise: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddExerciseScreen(sessionDate: _selectedDate),
                      ),
                    ).then((_) => _loadData());
                  },
                  onExerciseTap: (ex) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExerciseDetailScreen(
                          exerciseName: ex.catalogDetail?.name ?? '',
                          selectedDate: _selectedDate,
                          exerciseId: ex.exerciseId ?? '',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.list_outlined), activeIcon: Icon(Icons.list), label: 'Log'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Progress'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  String _formattedFullDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}

// ── Avatar menu ───────────────────────────────────────────────
class _AvatarMenu extends StatelessWidget {
  final VoidCallback onSignOut;
  const _AvatarMenu({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return PopupMenuButton<String>(
      onSelected: (v) { if (v == 'signout') onSignOut(); },
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
              Text('Sign out', style: TextStyle(fontSize: 13, color: lt.textSecondary)),
            ],
          ),
        ),
      ],
      child: const AvatarCircle('AL'),
    );
  }
}

// ── Calendar Strip ────────────────────────────────────────────
class _CalendarStrip extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool Function(DateTime) hasWorkout;
  const _CalendarStrip({required this.selectedDate, required this.onDateSelected, required this.hasWorkout});

  @override
  State<_CalendarStrip> createState() => _CalendarStripState();
}

class _CalendarStripState extends State<_CalendarStrip> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _getWeekStart(widget.selectedDate);
  }

  DateTime _getWeekStart(DateTime d) {
    return d.subtract(Duration(days: d.weekday - 1));
  }

  void _shiftWeek(int delta) {
    setState(() => _weekStart = _weekStart.add(Duration(days: delta * 7)));
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final now = DateTime.now();
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Month + nav
          Row(
            children: [
              Text(
                '${monthNames[_weekStart.month - 1]} ${_weekStart.year}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: lt.textPrimary),
              ),
              const Spacer(),
              IconSquareButton(
                icon: Icon(Icons.chevron_left, size: 16, color: lt.textSecondary),
                onTap: () => _shiftWeek(-1),
              ),
              const SizedBox(width: 8),
              IconSquareButton(
                icon: Icon(Icons.chevron_right, size: 16, color: lt.textSecondary),
                onTap: () => _shiftWeek(1),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 7 day strip
          Row(
            children: List.generate(7, (i) {
              final day = _weekStart.add(Duration(days: i));
              final isSelected = day.year == widget.selectedDate.year &&
                  day.month == widget.selectedDate.month &&
                  day.day == widget.selectedDate.day;
              final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
              final hasWork = widget.hasWorkout(day);

              return Expanded(
                child: GestureDetector(
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
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
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
  const _WorkoutCard({
    required this.date,
    required this.session,
    required this.exercises,
    required this.isLoading,
    required this.onAddExercise,
    required this.onExerciseTap,
  });

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month) return 'Today';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Container(
      decoration: BoxDecoration(
        color: lt.surface,
        border: Border.all(color: lt.borderSubtle, width: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────
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
                        '${_dayLabel(date)} · ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.day}',
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
                          color: session != null ? lt.textPrimary : lt.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // ── Add exercise button ───────────────────────────
          GestureDetector(
            onTap: onAddExercise,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

          // ── Exercise list / states ───────────────────────
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
                        ? const _EmptyState(message: 'No exercises yet.\nTap "Add exercise" to get started.')
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: exercises.length,
                            itemBuilder: (_, i) => _ExerciseRow(
                              exercise: exercises[i],
                              onTap: () => onExerciseTap(exercises[i]),
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
  const _EmptyState({this.message = 'No session found.\nTap "Add exercise" to create one.'});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: lt.textDim,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

// ── Exercise Row ──────────────────────────────────────────────
class _ExerciseRow extends StatelessWidget {
  final WorkoutExercises exercise;
  final VoidCallback onTap;
  const _ExerciseRow({required this.exercise, required this.onTap});

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
  Widget build(BuildContext context) {
    final lt = context.lt;
    final detail = exercise.catalogDetail;
    final name = detail?.name ?? 'Unknown exercise';
    final subtitle = detail?.muscleGroup ?? detail?.category ?? '';
    final emoji = _muscleEmoji(detail?.muscleGroup);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Icon
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: lt.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),

            // Info
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
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: lt.textMuted),
                    ),
                  ],
                ],
              ),
            ),

            ThreeDotMenu(
              onEdit: () {},
              onDelete: () {},
            ),
          ],
        ),
      ),
    );
  }
}
