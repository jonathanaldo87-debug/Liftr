import 'package:flutter/material.dart';

import '../services/rest_timer.dart';
import '../theme/app_theme.dart';
import '../utils/run_math.dart';

class RestTimerHost extends StatelessWidget {
  final Widget child;

  const RestTimerHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<Duration?>(
            valueListenable: RestTimer.remaining,
            child: child,
            builder: (context, left, child) => MediaQuery.removePadding(
              context: context,
              removeBottom: left != null,
              child: child!,
            ),
          ),
        ),
        ValueListenableBuilder<Duration?>(
          valueListenable: RestTimer.remaining,
          builder: (context, left, _) =>
              left == null ? const SizedBox.shrink() : _RestBar(left: left),
        ),
      ],
    );
  }
}

class _RestBar extends StatelessWidget {
  final Duration left;

  const _RestBar({required this.left});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final total = RestTimer.total.inMilliseconds;
    final elapsed = total <= 0
        ? 0.0
        : ((total - left.inMilliseconds) / total).clamp(0.0, 1.0);

    return Material(
      color: lt.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: elapsed,
                backgroundColor: lt.borderSubtle,
                valueColor:
                    const AlwaysStoppedAnimation(LiftrColors.accent),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'RESTING',
                          style: TextStyle(
                            fontSize: LiftrType.x10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.08,
                            color: lt.textMuted,
                          ),
                        ),
                        const SizedBox(height: LiftrSpacing.x2),
                        Text(
                          RestTimer.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: LiftrType.x12,
                            color: lt.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: LiftrSpacing.x10),
                  Text(
                    formatDuration(left.inSeconds),
                    style: TextStyle(
                      fontSize: LiftrType.x22,
                      fontWeight: FontWeight.w600,
                      color: lt.accentStrong,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: LiftrSpacing.x12),
                  _BarButton(
                    label: '+30s',
                    onTap: () => RestTimer.addTime(const Duration(seconds: 30)),
                  ),
                  const SizedBox(width: LiftrSpacing.x6),
                  const _BarButton(label: 'Skip', onTap: RestTimer.skip),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BarButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: LiftrSpacing.x12, vertical: LiftrSpacing.x8),
        decoration: BoxDecoration(
          color: lt.card,
          border: Border.all(color: lt.border, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.control),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: LiftrType.x12,
            fontWeight: FontWeight.w500,
            color: lt.textSecondary,
          ),
        ),
      ),
    );
  }
}
