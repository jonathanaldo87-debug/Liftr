import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';

/// Training totals across every session. The Progress tab used to be a dead
/// icon; these are the numbers the data can actually answer.
class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  WorkoutStats? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final stats = await WorkoutService.getStats();
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;
    final s = _stats;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All time', style: TextStyle(fontSize: 12, color: lt.textMuted)),
                const SizedBox(height: LiftrSpacing.x2),
                Text('Progress', style: tt.displaySmall),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: LiftrColors.accent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                children: [
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: LiftrColors.accent),
                        ),
                      ),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'Could not load your stats.\n$_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: lt.textDim, height: 1.6),
                      ),
                    )
                  else if (s == null || s.totalSessions == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'Nothing to measure yet.\nLog a few workouts and your '
                        'numbers show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: lt.textDim, height: 1.6),
                      ),
                    )
                  else ...[
                    _StreakCard(stats: s),
                    const SizedBox(height: LiftrSpacing.x10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'WORKOUTS',
                            value: '${s.totalSessions}',
                            hint: '${s.sessionsThisWeek} in the last 7 days',
                          ),
                        ),
                        const SizedBox(width: LiftrSpacing.x10),
                        Expanded(
                          child: _StatCard(
                            label: 'SETS LOGGED',
                            value: '${s.totalSets}',
                            hint: s.totalSessions == 0
                                ? ''
                                : '~${(s.totalSets / s.totalSessions).toStringAsFixed(1)} per workout',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: LiftrSpacing.x10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'TOTAL VOLUME',
                            value: _volume(s.totalVolumeKg),
                            hint: 'weight × reps, all sets',
                          ),
                        ),
                        const SizedBox(width: LiftrSpacing.x10),
                        Expanded(
                          child: _StatCard(
                            label: 'HEAVIEST SET',
                            value: s.heaviestSetKg == null
                                ? '—'
                                : '${_trim(s.heaviestSetKg!)} kg',
                            hint: 'across every lift',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: LiftrSpacing.x14),
                    Text(
                      'Per-exercise trends live on each exercise — open one from '
                      'a workout to see its weight chart.',
                      style: TextStyle(
                          fontSize: 11, color: lt.textDim, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Volume runs into the hundreds of thousands fast; raw digits are unreadable.
  static String _volume(double kg) {
    if (kg >= 1000000) return '${(kg / 1000000).toStringAsFixed(1)}M kg';
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k kg';
    return '${_trim(kg)} kg';
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _StreakCard extends StatelessWidget {
  final WorkoutStats stats;
  const _StreakCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final days = stats.streakDays;

    return Container(
      padding: const EdgeInsets.all(LiftrSpacing.x18),
      decoration: BoxDecoration(
        color: lt.accentBg,
        border: Border.all(color: lt.accentBorder, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.panel),
      ),
      child: Row(
        children: [
          Text(days > 0 ? '🔥' : '💤', style: const TextStyle(fontSize: 30)),
          const SizedBox(width: LiftrSpacing.x14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  days == 0 ? 'No active streak' : '$days day streak',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: lt.accentTextColor,
                  ),
                ),
                const SizedBox(height: LiftrSpacing.x2),
                Text(
                  days == 0
                      ? 'Log a workout today to start one.'
                      : 'Consecutive days trained. Keep it going.',
                  style: TextStyle(fontSize: 12, color: lt.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String hint;

  const _StatCard({
    required this.label,
    required this.value,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return Container(
      padding: const EdgeInsets.all(LiftrSpacing.x14),
      decoration: BoxDecoration(
        color: lt.surface,
        border: Border.all(color: lt.borderSubtle, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: lt.textMuted,
            ),
          ),
          const SizedBox(height: LiftrSpacing.x8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: LiftrColors.accent,
              ),
            ),
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: LiftrSpacing.x3),
            Text(hint, style: TextStyle(fontSize: 11, color: lt.textDim)),
          ],
        ],
      ),
    );
  }
}
