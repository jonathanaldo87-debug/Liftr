import 'package:flutter/material.dart';

import '../services/run_service.dart';
import '../theme/app_theme.dart';
import '../utils/run_math.dart';

/// Logging a run that already happened.
///
/// The whole of running, for now, and deliberately the first part built: it
/// needs no GPS, no permissions and no live state, so it's the one path that
/// works on a treadmill, indoors, or when you forgot to start tracking. Every
/// failure mode of the tracked flow eventually lands here.
///
/// Pops true if something was saved.
class AddRunScreen extends StatefulWidget {
  /// The day the run goes on — taken from the home screen's calendar rather
  /// than asked for again here. You already picked a date to get this far.
  final DateTime date;

  const AddRunScreen({super.key, required this.date});

  @override
  State<AddRunScreen> createState() => _AddRunScreenState();
}

class _AddRunScreenState extends State<AddRunScreen> {
  final _distanceCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _secondsCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Recompute the pace line as the numbers change — it's the fastest way to
    // notice you typed minutes into the hours box.
    for (final c in [_distanceCtrl, _hoursCtrl, _minutesCtrl, _secondsCtrl]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in [
      _distanceCtrl,
      _hoursCtrl,
      _minutesCtrl,
      _secondsCtrl,
      _nameCtrl,
      _notesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Kilometres in the field, metres in the database. People say "5.2 km", and
  /// asking for 5200 would be a small daily tax for no benefit.
  double? get _distanceMeters {
    final km = double.tryParse(_distanceCtrl.text.trim().replaceAll(',', '.'));
    if (km == null || km <= 0) return null;
    return km * 1000;
  }

  int get _durationSeconds {
    final h = int.tryParse(_hoursCtrl.text.trim()) ?? 0;
    final m = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    final s = int.tryParse(_secondsCtrl.text.trim()) ?? 0;
    return h * 3600 + m * 60 + s;
  }

  bool get _canSave =>
      _distanceMeters != null && _durationSeconds > 0 && !_isSaving;

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? LiftrColors.danger : null,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _save() async {
    final meters = _distanceMeters;
    final seconds = _durationSeconds;

    if (meters == null) {
      _toast('How far did you go?', error: true);
      return;
    }
    if (seconds <= 0) {
      _toast('How long did it take?', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await RunService.logManualRun(
        date: widget.date,
        distanceMeters: meters,
        durationSeconds: seconds,
        name: _nameCtrl.text,
        notes: _notesCtrl.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _toast('Could not save the run: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final meters = _distanceMeters;
    final seconds = _durationSeconds;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(lt),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                children: [
                  _label(lt, 'DISTANCE'),
                  const SizedBox(height: LiftrSpacing.x6),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: _field(lt, _distanceCtrl,
                            hint: '5.2', numeric: true, big: true),
                      ),
                      const SizedBox(width: LiftrSpacing.x10),
                      Text('km',
                          style: TextStyle(
                              fontSize: LiftrType.x14, color: lt.textMuted)),
                    ],
                  ),

                  const SizedBox(height: LiftrSpacing.x20),
                  _label(lt, 'TIME'),
                  const SizedBox(height: LiftrSpacing.x6),
                  Row(
                    children: [
                      Expanded(
                        child: _field(lt, _hoursCtrl,
                            hint: '0', numeric: true, suffix: 'h'),
                      ),
                      const SizedBox(width: LiftrSpacing.x8),
                      Expanded(
                        child: _field(lt, _minutesCtrl,
                            hint: '32', numeric: true, suffix: 'm'),
                      ),
                      const SizedBox(width: LiftrSpacing.x8),
                      Expanded(
                        child: _field(lt, _secondsCtrl,
                            hint: '10', numeric: true, suffix: 's'),
                      ),
                    ],
                  ),

                  // The one derived number worth showing while typing: a pace
                  // that reads as nonsense is how you catch a mistyped field
                  // before it's saved.
                  const SizedBox(height: LiftrSpacing.x12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: LiftrSpacing.x14,
                        vertical: LiftrSpacing.x12),
                    decoration: BoxDecoration(
                      color: lt.card,
                      border: Border.all(
                          color: lt.borderSubtle, width: LiftrBorders.hairline),
                      borderRadius: BorderRadius.circular(LiftrRadii.field),
                    ),
                    child: Row(
                      children: [
                        Text('Pace',
                            style: TextStyle(
                                fontSize: LiftrType.x12,
                                color: lt.textSecondary)),
                        const Spacer(),
                        Text(
                          meters == null ? '—' : formatPace(meters, seconds),
                          style: TextStyle(
                            fontSize: LiftrType.x16,
                            fontWeight: FontWeight.w600,
                            color: meters == null
                                ? lt.textDim
                                : LiftrColors.accentDark,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: LiftrSpacing.x20),
                  _label(lt, 'NAME'),
                  const SizedBox(height: LiftrSpacing.x6),
                  _field(lt, _nameCtrl, hint: 'Morning run'),

                  const SizedBox(height: LiftrSpacing.x16),
                  _label(lt, 'NOTES'),
                  const SizedBox(height: LiftrSpacing.x6),
                  _field(lt, _notesCtrl, hint: 'How did it feel?', lines: 3),

                  const SizedBox(height: LiftrSpacing.x24),
                  ElevatedButton(
                    onPressed: _canSave ? _save : null,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: LiftrColors.accentText),
                          )
                        : const Text('Save run'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(LiftrTheme lt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context, false),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: lt.card,
                border:
                    Border.all(color: lt.border, width: LiftrBorders.hairline),
                borderRadius: BorderRadius.circular(LiftrRadii.control),
              ),
              child:
                  Icon(Icons.chevron_left, size: 20, color: lt.textSecondary),
            ),
          ),
          const SizedBox(width: LiftrSpacing.x10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add a run',
                    style: Theme.of(context).textTheme.displaySmall),
                Text(
                  _dateLabel,
                  style:
                      TextStyle(fontSize: LiftrType.x11, color: lt.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _dateLabel {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final d = widget.date;
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _label(LiftrTheme lt, String text) => Text(
        text,
        style: TextStyle(
          fontSize: LiftrType.x11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.08,
          color: lt.textMuted,
        ),
      );

  Widget _field(
    LiftrTheme lt,
    TextEditingController ctrl, {
    required String hint,
    bool numeric = false,
    bool big = false,
    int lines = 1,
    String? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: lt.card,
        border: Border.all(color: lt.border, width: LiftrBorders.hairline),
        borderRadius: BorderRadius.circular(LiftrRadii.field),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: lines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: TextStyle(
          fontSize: big ? LiftrType.x20 : LiftrType.x13,
          fontWeight: big ? FontWeight.w600 : FontWeight.w400,
          color: big ? LiftrColors.accent : lt.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontSize: big ? LiftrType.x20 : LiftrType.x13, color: lt.textDim),
          suffixText: suffix,
          suffixStyle: TextStyle(fontSize: LiftrType.x12, color: lt.textMuted),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: LiftrSpacing.x14, vertical: LiftrSpacing.x12),
          fillColor: Colors.transparent,
        ),
      ),
    );
  }
}
