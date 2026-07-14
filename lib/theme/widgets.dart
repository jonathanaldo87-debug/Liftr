import 'package:flutter/material.dart';
import 'app_theme.dart';

// ── Logo Mark ─────────────────────────────────────────────────
class LiftrLogoMark extends StatelessWidget {
  final double size;
  const LiftrLogoMark({super.key, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC8F075), Color(0xFF80E850)],
        ),
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.54, size * 0.54),
          painter: _LogoPainter(),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = LiftrColors.accentText
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.36;

    // Circle
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // Arrow right through center
    canvas.drawLine(Offset(cx - r * 0.8, cy), Offset(cx + r * 0.8, cy), paint);
    canvas.drawLine(Offset(cx + r * 0.2, cy - r * 0.5), Offset(cx + r * 0.8, cy), paint);
    canvas.drawLine(Offset(cx + r * 0.2, cy + r * 0.5), Offset(cx + r * 0.8, cy), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Section Label ─────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.08,
        color: context.lt.textMuted,
      ),
    );
  }
}

// ── Accent Tag / Chip ─────────────────────────────────────────
class AccentChip extends StatelessWidget {
  final String label;
  const AccentChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.lt.accentBg,
        border: Border.all(color: context.lt.accentBorder, width: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.06,
          color: context.lt.accentTextColor,
        ),
      ),
    );
  }
}

// ── Surface Card ─────────────────────────────────────────────
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  const SurfaceCard({super.key, required this.child, this.padding, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.lt.surface,
        border: Border.all(color: context.lt.borderSubtle, width: 0.5),
        borderRadius: borderRadius ?? BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

// ── Three-dot menu button ─────────────────────────────────────
class ThreeDotMenu extends StatelessWidget {
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const ThreeDotMenu({super.key, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          3,
          (_) => Container(
            width: 3.5,
            height: 3.5,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: BoxDecoration(
              color: context.lt.textDim,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
      iconSize: 24,
      padding: EdgeInsets.zero,
      color: context.lt.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.lt.border, width: 0.5),
      ),
      onSelected: (v) {
        if (v == 'edit') onEdit?.call();
        if (v == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          height: 40,
          child: Text('Edit', style: TextStyle(fontSize: 13, color: context.lt.textPrimary)),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 40,
          child: const Text('Delete', style: TextStyle(fontSize: 13, color: Color(0xFFE24B4A))),
        ),
      ],
    );
  }
}

// ── Weight Badge ──────────────────────────────────────────────
class WeightBadge extends StatelessWidget {
  final String weight;
  const WeightBadge(this.weight, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.lt.accentBg,
        border: Border.all(color: context.lt.accentBorder, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        weight,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: LiftrColors.accent,
        ),
      ),
    );
  }
}

// ── Avatar circle ─────────────────────────────────────────────
class AvatarCircle extends StatelessWidget {
  final String initials;
  final double size;
  const AvatarCircle(this.initials, {super.key, this.size = 38});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LiftrColors.accent, LiftrColors.accentDark],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: LiftrColors.accentText,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'DMSans',
          ),
        ),
      ),
    );
  }
}

// ── Icon square button ────────────────────────────────────────
class IconSquareButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  const IconSquareButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.lt.card,
          border: Border.all(color: context.lt.border, width: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: icon),
      ),
    );
  }
}

// ── Progress step dots ────────────────────────────────────────
class ProgressDots extends StatelessWidget {
  final int total;
  final int current;
  const ProgressDots({super.key, required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 8,
          height: 3,
          decoration: BoxDecoration(
            color: isActive ? LiftrColors.accent : context.lt.border,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ── Level chip ────────────────────────────────────────────────
class LevelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const LevelChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.lt.accentBg : context.lt.card,
            border: Border.all(
              color: selected ? LiftrColors.accent : context.lt.border,
              width: selected ? 1.0 : 0.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? LiftrColors.accent : context.lt.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Activity card ─────────────────────────────────────────────
class ActivityCard extends StatelessWidget {
  final String emoji;
  final String name;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  const ActivityCard({
    super.key,
    required this.emoji,
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? context.lt.accentBg : context.lt.card,
          border: Border.all(
            color: selected ? LiftrColors.accent : context.lt.border,
            width: selected ? 1.0 : 0.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 8),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.lt.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: context.lt.textMuted),
                ),
              ],
            ),
            if (selected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
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
  }
}
