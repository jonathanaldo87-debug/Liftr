import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Every workout you've logged, newest first. Reached from the Log tab, which
/// previously did nothing but highlight itself.
class LogTab extends StatefulWidget {
  /// Opens the given date on the Home tab.
  final ValueChanged<DateTime> onOpenDate;

  const LogTab({super.key, required this.onOpenDate});

  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> {
  List<SessionSummary> _sessions = [];
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
      final sessions = await WorkoutService.getSessionHistory();
      if (mounted) setState(() => _sessions = sessions);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(SessionSummary s) async {
    final id = s.session.sessionId;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Delete workout?',
        message: '${s.session.name ?? 'This session'} and its '
            '${s.exerciseCount} exercise${s.exerciseCount == 1 ? '' : 's'} '
            '(and all their sets) will be permanently removed.',
      ),
    );
    if (confirmed != true) return;

    try {
      await WorkoutService.deleteWorkoutSession(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete: $e'),
          backgroundColor: const Color(0xFFE24B4A),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isLoading
                      ? 'Loading…'
                      : '${_sessions.length} workout${_sessions.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: lt.textMuted),
                ),
                const SizedBox(height: 2),
                Text('History', style: tt.displaySmall),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: LiftrColors.accent,
              child: _body(lt),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(LiftrTheme lt) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: LiftrColors.accent),
        ),
      );
    }

    if (_error != null) {
      return _Scrollable(
        child: Text(
          'Could not load your history.\n$_error',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: lt.textDim, height: 1.6),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return _Scrollable(
        child: Text(
          'No workouts yet.\nLog one from the Home tab and it shows up here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: lt.textDim, height: 1.6),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: _sessions.length,
      itemBuilder: (_, i) => _SessionCard(
        summary: _sessions[i],
        onTap: () {
          final d = _sessions[i].session.sessionDate;
          if (d != null) widget.onOpenDate(d);
        },
        onDelete: () => _delete(_sessions[i]),
      ),
    );
  }
}

/// Keeps pull-to-refresh working on an otherwise empty screen.
class _Scrollable extends StatelessWidget {
  final Widget child;
  const _Scrollable({required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: child,
              ),
            ),
          ),
        ),
      );
}

class _SessionCard extends StatelessWidget {
  final SessionSummary summary;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.summary,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final s = summary.session;
    final date = s.sessionDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: lt.surface,
            border: Border.all(color: lt.borderSubtle, width: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Date block
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: lt.accentBg,
                  border: Border.all(color: lt.accentBorder, width: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      date == null ? '—' : _month(date),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: lt.accentMid,
                      ),
                    ),
                    Text(
                      date == null ? '' : '${date.day}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: lt.accentTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name ?? 'Untitled session',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: lt.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.exerciseCount} exercise'
                      '${summary.exerciseCount == 1 ? '' : 's'}'
                      '${date == null ? '' : ' · ${_relative(date)}'}',
                      style: TextStyle(fontSize: 11, color: lt.textMuted),
                    ),
                  ],
                ),
              ),
              ThreeDotMenu(onEdit: onTap, onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }

  static String _month(DateTime d) {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return months[d.month - 1];
  }

  static String _relative(DateTime d) {
    final today = DateTime.now();
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;

    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    if (days < 14) return 'last week';
    if (days < 60) return '${(days / 7).floor()} weeks ago';
    return '${(days / 30).floor()} months ago';
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: TextStyle(fontSize: 16, color: lt.textPrimary)),
      content:
          Text(message, style: TextStyle(fontSize: 13, color: lt.textSecondary)),
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
