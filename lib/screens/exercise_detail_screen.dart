import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class ExerciseDetailScreen extends StatefulWidget {
  final String exerciseName;
  final DateTime selectedDate;
  final String exerciseId;
  const ExerciseDetailScreen({
    super.key,
    required this.exerciseName,
    required this.selectedDate,
    required this.exerciseId,
  });

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();

  // Stub history data: (label, weight)
  final _history = const [
    ('Feb 1', 60.0), ('Feb 8', 65.0), ('Feb 15', 67.5), ('Feb 22', 70.0),
    ('Mar 1', 72.5), ('Mar 8', 75.0), ('Mar 15', 80.0),
  ];

  List<ExerciseSets> _sets = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSets();
  }

  Future<void> _loadSets() async {
    setState(() => _isLoading = true);
    try {
      final sets = await WorkoutService.getExerciseSets(widget.exerciseId);
      if (mounted) setState(() => _sets = sets);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Nav header ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: lt.card,
                        border: Border.all(color: lt.border, width: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.chevron_left, size: 20, color: lt.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.exerciseName,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                  ThreeDotMenu(onEdit: () {}, onDelete: () {}),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Weight progress chart ────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: lt.surface,
                        border: Border.all(color: lt.borderSubtle, width: 0.5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Weight progress',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: lt.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '80 kg ↑',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: LiftrColors.accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 100,
                            child: CustomPaint(
                              size: const Size(double.infinity, 100),
                              painter: _ChartPainter(
                                data: _history.map((e) => e.$2).toList(),
                                labels: _history.map((e) => e.$1).toList(),
                                accentColor: LiftrColors.accent,
                                gridColor: lt.borderSubtle,
                                labelColor: lt.textDim,
                                isDark: context.isDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Notes (placeholder) ──────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: lt.card,
                        border: Border.all(color: lt.border, width: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        maxLines: 2,
                        style: TextStyle(fontSize: 13, color: lt.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Add a note for this session…',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Sets header ──────────────────────────
                    Row(
                      children: [
                        Text(
                          'SETS · ${['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'][widget.selectedDate.month - 1]} ${widget.selectedDate.day}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.08,
                            color: lt.textMuted,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {},
                          child: Text(
                            '+ Add set',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: lt.accentMid,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Set rows ─────────────────────────────
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      ...List.generate(_sets.length, (i) {
                        final s = _sets[i];
                        final done = s.isCompleted ?? false;
                        final isActive = !done;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isActive ? lt.accentBg : lt.surface,
                              border: Border.all(
                                color: isActive ? LiftrColors.accent : lt.borderSubtle,
                                width: isActive ? 1.0 : 0.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    'S${s.setNumber ?? i + 1}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isActive ? lt.accentMid : lt.textMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    done
                                        ? '${s.reps ?? 0} reps · ${s.weightKg ?? 0} kg'
                                        : 'Enter weight →',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: done ? lt.textPrimary : lt.textMuted,
                                    ),
                                  ),
                                ),
                                if (done)
                                  Text(
                                    '✓ Done',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: lt.accentMid,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 4),

                    // ── Weight input ─────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: lt.accentBg,
                        border: Border.all(color: LiftrColors.accent, width: 1.0),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SET ${_sets.length + 1} · LOG WEIGHT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.08,
                              color: lt.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Weight field
                              Expanded(
                                flex: 2,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: lt.card,
                                    border: Border.all(color: lt.border, width: 0.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: TextField(
                                    controller: _weightCtrl,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: LiftrColors.accent,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                                      fillColor: Colors.transparent,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  'kg',
                                  style: TextStyle(fontSize: 13, color: lt.textMuted, fontWeight: FontWeight.w500),
                                ),
                              ),
                              // Reps field
                              Column(
                                children: [
                                  Text(
                                    'Reps',
                                    style: TextStyle(fontSize: 11, color: lt.textMuted),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 56,
                                    decoration: BoxDecoration(
                                      color: lt.card,
                                      border: Border.all(color: lt.border, width: 0.5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: TextField(
                                      controller: _repsCtrl,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: lt.textPrimary,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                                        fillColor: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              // Save button
                              ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(64, 44),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text('Save', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Line Chart Painter ────────────────────────────────────────
class _ChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color accentColor;
  final Color gridColor;
  final Color labelColor;
  final bool isDark;

  const _ChartPainter({
    required this.data,
    required this.labels,
    required this.accentColor,
    required this.gridColor,
    required this.labelColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final minVal = data.reduce((a, b) => a < b ? a : b);
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);

    final chartH = size.height - 18; // leave room for labels
    final padX = 8.0;
    final usableW = size.width - padX * 2;

    double x(int i) => padX + (i / (data.length - 1)) * usableW;
    double y(double v) => chartH - ((v - minVal) / range) * (chartH - 12) - 4;

    // Grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 0; i < 3; i++) {
      final yy = 8.0 + (chartH - 12) * i / 2;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), gridPaint);
    }

    // Area fill
    final path = Path();
    path.moveTo(x(0), y(data[0]));
    for (var i = 1; i < data.length; i++) {
      final cp1x = x(i - 1) + (x(i) - x(i - 1)) * 0.5;
      path.cubicTo(cp1x, y(data[i - 1]), cp1x, y(data[i]), x(i), y(data[i]));
    }
    path.lineTo(x(data.length - 1), chartH);
    path.lineTo(x(0), chartH);
    path.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accentColor.withOpacity(0.3), accentColor.withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartH));
    canvas.drawPath(path, fillPaint);

    // Line
    final linePath = Path();
    linePath.moveTo(x(0), y(data[0]));
    for (var i = 1; i < data.length; i++) {
      final cp1x = x(i - 1) + (x(i) - x(i - 1)) * 0.5;
      linePath.cubicTo(cp1x, y(data[i - 1]), cp1x, y(data[i]), x(i), y(data[i]));
    }
    final linePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Dots
    final dotPaint = Paint()..color = accentColor;
    final holePaint = Paint()..color = isDark ? const Color(0xFF15151A) : Colors.white;
    for (var i = 0; i < data.length; i++) {
      canvas.drawCircle(Offset(x(i), y(data[i])), i == data.length - 1 ? 4.5 : 3, dotPaint);
      if (i == data.length - 1) {
        canvas.drawCircle(Offset(x(i), y(data[i])), 2.5, holePaint);
      }
    }

    // Labels (first and last only)
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, Offset pos, TextAlign align) {
      tp.text = TextSpan(
        text: text,
        style: TextStyle(fontSize: 9, color: labelColor, fontFamily: 'DMSans'),
      );
      tp.textAlign = align;
      tp.layout();
      final dx = align == TextAlign.right ? pos.dx - tp.width : pos.dx;
      tp.paint(canvas, Offset(dx, pos.dy));
    }

    drawLabel(labels.first, Offset(x(0) - 2, chartH + 4), TextAlign.left);
    drawLabel(labels.last, Offset(x(data.length - 1) + 2, chartH + 4), TextAlign.right);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.data != data || old.isDark != isDark;
}
