import 'package:flutter/material.dart';
import 'app_theme.dart';

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
          colors: [LiftrColors.accent, LiftrColors.accentDark],
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

    canvas.drawCircle(Offset(cx, cy), r, paint);

    canvas.drawLine(Offset(cx - r * 0.8, cy), Offset(cx + r * 0.8, cy), paint);
    canvas.drawLine(
        Offset(cx + r * 0.2, cy - r * 0.5), Offset(cx + r * 0.8, cy), paint);
    canvas.drawLine(
        Offset(cx + r * 0.2, cy + r * 0.5), Offset(cx + r * 0.8, cy), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: LiftrType.x11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.08,
        color: context.lt.textMuted,
      ),
    );
  }
}

class AccentChip extends StatelessWidget {
  final String label;
  const AccentChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LiftrSpacing.x10, vertical: LiftrSpacing.x4),
      decoration: BoxDecoration(
        color: context.lt.accentBg,
        border: Border.all(
            color: context.lt.accentBorder, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.panel),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: LiftrType.x10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.06,
          color: context.lt.accentTextColor,
        ),
      ),
    );
  }
}

class MenuAction {
  final String label;
  final VoidCallback onTap;

  final bool isDanger;

  const MenuAction(this.label, this.onTap, {this.isDanger = false});
}

class ThreeDotMenu extends StatelessWidget {
  final List<MenuAction> actions;

  final bool boxed;

  const ThreeDotMenu({
    super.key,
    required this.actions,
    this.boxed = false,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    final dots = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (_) => Container(
          width: 3.5,
          height: 3.5,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          decoration: BoxDecoration(
            color: lt.textDim,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );

    return PopupMenuButton<String>(
      icon: boxed
          ? Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: lt.card,
                border:
                    Border.all(color: lt.border, width: LiftrBorders.hairline),
                borderRadius: BorderRadius.circular(LiftrRadii.control),
              ),
              child: Center(child: dots),
            )
          : dots,
      iconSize: boxed ? 32 : 24,
      padding: EdgeInsets.zero,
      color: lt.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LiftrRadii.field),
        side: BorderSide(color: lt.border, width: LiftrBorders.hairline),
      ),
      onSelected: (v) => actions[int.parse(v)].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem(
            value: '$i',
            height: 40,
            child: Text(
              actions[i].label,
              style: TextStyle(
                fontSize: LiftrType.x13,
                color:
                    actions[i].isDanger ? LiftrColors.danger : lt.textPrimary,
              ),
            ),
          ),
      ],
    );
  }
}

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
            fontSize: LiftrType.x14,
            fontWeight: FontWeight.w600,
            fontFamily: 'DMSans',
          ),
        ),
      ),
    );
  }
}

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
          border: Border.all(
              color: context.lt.border, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.control),
        ),
        child: Center(child: icon),
      ),
    );
  }
}

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
          margin: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x3),
          width: isActive ? 20 : 8,
          height: 3,
          decoration: BoxDecoration(
            color: isActive ? LiftrColors.accent : context.lt.border,
            borderRadius: BorderRadius.circular(LiftrRadii.pip),
          ),
        );
      }),
    );
  }
}

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
        padding: const EdgeInsets.all(LiftrSpacing.x14),
        decoration: BoxDecoration(
          color: selected ? context.lt.accentBg : context.lt.card,
          border: Border.all(
            color: selected ? LiftrColors.accent : context.lt.border,
            width: selected ? LiftrBorders.thin : LiftrBorders.hairline,
          ),
          borderRadius: BorderRadius.circular(LiftrRadii.card),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: LiftrType.x22)),
                const SizedBox(height: LiftrSpacing.x8),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: LiftrType.x13,
                    fontWeight: FontWeight.w500,
                    color: context.lt.textPrimary,
                  ),
                ),
                const SizedBox(height: LiftrSpacing.x2),
                Text(
                  description,
                  style: TextStyle(
                      fontSize: LiftrType.x11, color: context.lt.textMuted),
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
                  decoration: BoxDecoration(
                    color: context.lt.accentStrong,
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
