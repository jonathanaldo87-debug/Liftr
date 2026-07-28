import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/run_math.dart';

/// How far is this leg? Quick distances, or type one.
///
/// The presets match the tracker's own, so a target set here and a target set
/// mid-run are picked from the same four numbers.
///
/// Pops the chosen distance in **metres**, or null if dismissed.
///
/// Public, and in its own file, so it can be pumped in a widget test. It's pure
/// layout over the app theme — no services, nothing to stub — and the first
/// version of it shipped a layout crash that only appeared on tap. See
/// `test/target_sheet_test.dart`.
class TargetSheet extends StatefulWidget {
  const TargetSheet({super.key});

  @override
  State<TargetSheet> createState() => TargetSheetState();
}

class TargetSheetState extends State<TargetSheet> {
  final _ctrl = TextEditingController();

  static const _quick = <double>[400, 1000, 3000, 5000, 10000];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? get _typed {
    final km = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (km == null || km <= 0) return null;
    return km * 1000;
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: lt.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(LiftrRadii.sheet)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: LiftrSpacing.x18),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: LiftrSpacing.x20),
                child: Text('How far?',
                    style: Theme.of(context).textTheme.displaySmall),
              ),
              const SizedBox(height: LiftrSpacing.x14),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: LiftrSpacing.x16),
                child: Wrap(
                  spacing: LiftrSpacing.x6,
                  runSpacing: LiftrSpacing.x6,
                  children: [
                    for (final m in _quick)
                      GestureDetector(
                        onTap: () => Navigator.pop(context, m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: LiftrSpacing.x14,
                              vertical: LiftrSpacing.x10),
                          decoration: BoxDecoration(
                            color: lt.card,
                            border: Border.all(
                                color: lt.border,
                                width: LiftrBorders.hairline),
                            borderRadius:
                                BorderRadius.circular(LiftrRadii.panel),
                          ),
                          child: Text(
                            formatDistance(m),
                            style: TextStyle(
                                fontSize: LiftrType.x13,
                                color: lt.textPrimary),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: LiftrSpacing.x16),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: LiftrSpacing.x16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: LiftrSpacing.x14),
                  decoration: BoxDecoration(
                    color: lt.card,
                    border: Border.all(
                        color: lt.border, width: LiftrBorders.hairline),
                    borderRadius: BorderRadius.circular(LiftrRadii.field),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            final m = _typed;
                            if (m != null) Navigator.pop(context, m);
                          },
                          style: TextStyle(
                              fontSize: LiftrType.x14, color: lt.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'or type it',
                            hintStyle: TextStyle(
                                fontSize: LiftrType.x14, color: lt.textDim),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: LiftrSpacing.x14),
                            fillColor: Colors.transparent,
                          ),
                        ),
                      ),
                      Text('km',
                          style: TextStyle(
                              fontSize: LiftrType.x13, color: lt.textMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x12),
              // Full width, below the field rather than beside it. The theme
              // gives every ElevatedButton `minimumSize: Size.fromHeight(52)`,
              // which is an infinite width request — fine in an Expanded or a
              // bounded SizedBox, but a Row hands its non-flex children
              // unbounded width and the layout blows up. Every other button in
              // the app is full width for the same reason.
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: LiftrSpacing.x16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _typed == null
                        ? null
                        : () => Navigator.pop(context, _typed),
                    child: const Text('Add'),
                  ),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x20),
            ],
          ),
        ),
      ),
    );
  }
}
