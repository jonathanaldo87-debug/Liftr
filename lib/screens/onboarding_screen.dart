import 'package:flutter/material.dart';
import '../services/prefs.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'home_screen.dart';

/// Shown once, on first launch after signing in.
///
/// NOTE: the answers are recorded (and shown on Profile) but don't yet change
/// how the app behaves — it logs gym lifts regardless of what you pick here.
/// The non-Gym activities and the "use a template" option are aspirational:
/// nothing downstream reads them yet.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Page 1 state
  int _selectedActivity = 0;
  final _activities = [
    ('🏋️', 'Gym', 'Weights & machines'),
    ('🧘', 'Pilates', 'Core & flexibility'),
    ('🏃', 'Running', 'Cardio & pace'),
    ('🏊', 'Swimming', 'Laps & strokes'),
    ('🚴', 'Cycling', 'Speed & distance'),
    ('➕', 'Custom', 'Define your own'),
  ];

  // Page 2 state
  int _selectedLevel = 1;
  final _levels = ['Beginner', 'Intermediate', 'Advanced'];

  // Page 3 state
  int _selectedTemplate = 0;

  bool _isFinishing = false;

  Future<void> _nextPage() async {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      return;
    }

    // "Get started" used to be a no-op — the button did nothing at all.
    setState(() => _isFinishing = true);
    await Prefs.completeOnboarding(
      activity: _activities[_selectedActivity].$2,
      level: _levels[_selectedLevel],
    );

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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: ProgressDots(total: 3, current: _currentPage),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _currentPage = p),
                children: [
                  _ActivityPage(
                    activities: _activities,
                    selected: _selectedActivity,
                    onSelect: (i) => setState(() => _selectedActivity = i),
                  ),
                  _LevelPage(
                    activityName: _activities[_selectedActivity].$2,
                    levels: _levels,
                    selected: _selectedLevel,
                    onSelect: (i) => setState(() => _selectedLevel = i),
                  ),
                  _TemplatePage(
                    selected: _selectedTemplate,
                    onSelect: (i) => setState(() => _selectedTemplate = i),
                  ),
                ],
              ),
            ),

            // Next button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ElevatedButton(
                onPressed: _isFinishing ? null : _nextPage,
                child: _isFinishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: LiftrColors.accentText,
                        ),
                      )
                    : Text(_currentPage == 2 ? 'Get started' : 'Next →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityPage extends StatelessWidget {
  final List<(String, String, String)> activities;
  final int selected;
  final ValueChanged<int> onSelect;
  const _ActivityPage({required this.activities, required this.selected, required this.onSelect});

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
            'Pick your primary workout type',
            style: TextStyle(fontSize: 13, color: lt.textMuted),
          ),
          const SizedBox(height: LiftrSpacing.x24),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: List.generate(activities.length, (i) {
              final (emoji, name, desc) = activities[i];
              return ActivityCard(
                emoji: emoji,
                name: name,
                description: desc,
                selected: selected == i,
                onTap: () => onSelect(i),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _LevelPage extends StatelessWidget {
  final String activityName;
  final List<String> levels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _LevelPage({
    required this.activityName,
    required this.levels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: LiftrSpacing.x8),
          Text('What\'s your\n$activityName level?', style: tt.displayMedium),
          const SizedBox(height: LiftrSpacing.x6),
          Text(
            'We\'ll personalise your experience',
            style: TextStyle(fontSize: 13, color: lt.textMuted),
          ),
          const SizedBox(height: LiftrSpacing.x32),

          ...List.generate(levels.length, (i) {
            final isSelected = selected == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(LiftrSpacing.x18),
                  decoration: BoxDecoration(
                    color: isSelected ? lt.accentBg : lt.card,
                    border: Border.all(
                      color: isSelected ? LiftrColors.accent : lt.border,
                      width: isSelected ? LiftrBorders.thin : LiftrBorders.hairline,
                    ),
                    borderRadius: BorderRadius.circular(LiftrRadii.card),
                  ),
                  child: Row(
                    children: [
                      Text(
                        levels[i],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? LiftrColors.accent : lt.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (isSelected)
                        Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: LiftrColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, size: 12, color: LiftrColors.accentText),
                        )
                      else
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: lt.border, width: LiftrBorders.hairline),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: LiftrSpacing.x8),
          Text(
            ['Start with the fundamentals and build habits.', 'You know the movements — let\'s push further.', 'Advanced programming, heavier loads.'][selected],
            style: TextStyle(fontSize: 12, color: lt.textMuted),
          ),
        ],
      ),
    );
  }
}

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
            'You can always change this later',
            style: TextStyle(fontSize: 13, color: lt.textMuted),
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
                      width: isSelected ? LiftrBorders.thin : LiftrBorders.hairline,
                    ),
                    borderRadius: BorderRadius.circular(LiftrRadii.panel),
                  ),
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: LiftrSpacing.x16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: isSelected ? LiftrColors.accent : lt.textPrimary,
                              ),
                            ),
                            const SizedBox(height: LiftrSpacing.x3),
                            Text(desc, style: TextStyle(fontSize: 12, color: lt.textMuted)),
                            const SizedBox(height: LiftrSpacing.x4),
                            Text(
                              sub,
                              style: TextStyle(
                                fontSize: 11,
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
