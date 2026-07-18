import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/prefs.dart';
import '../services/workout_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'home_screen.dart';

/// Shown once, on first launch after signing in, and re-runnable from Profile.
///
/// Picks the disciplines you train. That answer is load-bearing: it decides
/// which chips the home screen offers, so this is no longer a decorative
/// questionnaire.
///
/// The flow is 1 or 2 pages depending on the answer — templates are a gym-only
/// concept, so a runner never sees that page.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  /// Straight from the `disciplines` table — never a hardcoded list, so adding
  /// swimming is an INSERT rather than a release.
  List<Discipline> _disciplines = [];
  bool _isLoading = true;

  /// Multi-select: people cross-train. Pre-seeded from whatever's already saved
  /// so re-running this from Profile shows your current answer rather than a
  /// blank slate.
  late Set<String> _selected = Prefs.enabledDisciplines.toSet();

  int _selectedTemplate = 0;
  bool _isFinishing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await WorkoutService.getDisciplines();
    if (!mounted) return;
    setState(() {
      _disciplines = list;
      // Drop anything saved that the catalog no longer offers (a discipline
      // could be retired), but never end up with an empty selection.
      _selected = _selected.where((k) => list.any((d) => d.key == k)).toSet();
      if (_selected.isEmpty && list.isNotEmpty) _selected = {list.first.key};
      _isLoading = false;
    });
  }

  /// Templates are a gym idea. Someone who only runs shouldn't be asked.
  bool get _showsTemplates => _selected.contains(Discipline.gymKey);

  int get _pageCount => _showsTemplates ? 2 : 1;

  bool get _isLastPage => _currentPage >= _pageCount - 1;

  void _toggle(String key) {
    setState(() {
      // Never allow zero: with no discipline there's nothing to log.
      if (_selected.contains(key) && _selected.length > 1) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }

      // Deselecting gym removes the template page underneath us.
      if (_currentPage > _pageCount - 1) {
        _currentPage = _pageCount - 1;
        _pageController.jumpToPage(_currentPage);
      }
    });
  }

  Future<void> _next() async {
    if (!_isLastPage) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      return;
    }

    setState(() => _isFinishing = true);

    // Save in catalog order, so the home chips are stable rather than ordered by
    // whatever the user happened to tap first.
    final ordered = _disciplines
        .map((d) => d.key)
        .where(_selected.contains)
        .toList();
    await Prefs.completeOnboarding(disciplines: ordered);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: LiftrColors.accent),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Only worth showing when there's more than one page to track.
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: _pageCount > 1
                  ? ProgressDots(total: _pageCount, current: _currentPage)
                  : const SizedBox(height: 3),
            ),

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _currentPage = p),
                children: [
                  _DisciplinePage(
                    disciplines: _disciplines,
                    selected: _selected,
                    onToggle: _toggle,
                  ),
                  if (_showsTemplates)
                    _TemplatePage(
                      selected: _selectedTemplate,
                      onSelect: (i) => setState(() => _selectedTemplate = i),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ElevatedButton(
                onPressed: _isFinishing ? null : _next,
                child: _isFinishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: LiftrColors.accentText,
                        ),
                      )
                    : Text(_isLastPage ? 'Get started' : 'Next →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 1: what do you train (multi-select) ──────────────────
class _DisciplinePage extends StatelessWidget {
  final List<Discipline> disciplines;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _DisciplinePage({
    required this.disciplines,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: LiftrSpacing.x8),
          Text('What do you\ntrain?', style: tt.displayMedium),
          const SizedBox(height: LiftrSpacing.x6),
          Text(
            'Pick everything you do — you can change this later.',
            style: TextStyle(fontSize: LiftrType.x13, color: lt.textMuted),
          ),
          const SizedBox(height: LiftrSpacing.x24),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: disciplines
                .map((d) => ActivityCard(
                      emoji: d.emoji,
                      name: d.label,
                      description: d.description,
                      selected: selected.contains(d.key),
                      onTap: () => onToggle(d.key),
                    ))
                .toList(),
          ),

          const SizedBox(height: LiftrSpacing.x12),
          Text(
            selected.length == 1
                ? '1 selected'
                : '${selected.length} selected',
            style: TextStyle(fontSize: LiftrType.x12, color: lt.textDim),
          ),
        ],
      ),
    );
  }
}

// ── Page 2: gym templates (gym only) ──────────────────────────
class _TemplatePage extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _TemplatePage({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;

    final options = [
      (
        '📋',
        'Use a template',
        'Start with a pre-built programme',
        'Recommended for beginners',
      ),
      (
        '⬜',
        'Blank slate',
        'Build your own workout from scratch',
        'Full control from day one',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: LiftrSpacing.x8),
          Text('How do you want\nto start?', style: tt.displayMedium),
          const SizedBox(height: LiftrSpacing.x6),
          Text(
            'For your gym sessions. You can always change this later.',
            style: TextStyle(fontSize: LiftrType.x13, color: lt.textMuted),
          ),
          const SizedBox(height: LiftrSpacing.x32),

          ...List.generate(options.length, (i) {
            final (emoji, title, desc, sub) = options[i];
            final isSelected = selected == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(LiftrSpacing.x20),
                  decoration: BoxDecoration(
                    color: isSelected ? lt.accentBg : lt.card,
                    border: Border.all(
                      color: isSelected ? LiftrColors.accent : lt.border,
                      width:
                          isSelected ? LiftrBorders.thin : LiftrBorders.hairline,
                    ),
                    borderRadius: BorderRadius.circular(LiftrRadii.panel),
                  ),
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: LiftrType.x28)),
                      const SizedBox(width: LiftrSpacing.x16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: LiftrType.x15,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? LiftrColors.accent
                                    : lt.textPrimary,
                              ),
                            ),
                            const SizedBox(height: LiftrSpacing.x3),
                            Text(desc,
                                style: TextStyle(
                                    fontSize: LiftrType.x12, color: lt.textMuted)),
                            const SizedBox(height: LiftrSpacing.x4),
                            Text(
                              sub,
                              style: TextStyle(
                                fontSize: LiftrType.x11,
                                color: isSelected ? lt.accentMid : lt.textDim,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
