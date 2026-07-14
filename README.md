# Liftr — Flutter Workout Logger

Dark/light mode, multi-screen app scaffold.

## Project structure

```
lib/
├── main.dart                    # App entry point + dev screen launcher
├── theme/
│   ├── app_theme.dart           # ThemeData, LiftrTheme extension, color tokens
│   └── widgets.dart             # Shared reusable widgets
└── screens/
    ├── login_screen.dart        # Email/password + social SSO
    ├── onboarding_screen.dart   # 3-step: activity → level → template
    ├── home_screen.dart         # Calendar strip + workout card
    └── exercise_detail_screen.dart  # Chart + sets + weight input
```

## Quick start

```bash
# 1. Get Flutter (https://flutter.dev/docs/get-started/install)
# 2. Download DM Sans + DM Serif Display from fonts.google.com
#    Place in assets/fonts/ matching pubspec.yaml
# 3. Create the fonts directory
mkdir -p assets/fonts

# 4. Get dependencies
flutter pub get

# 5. Run
flutter run
```

## Theme system

The entire theme is driven by `LiftrTheme` — a custom `ThemeExtension` that
provides context-aware tokens for both dark and light modes.

**Usage anywhere in the widget tree:**
```dart
final lt = context.lt;          // LiftrTheme tokens
final isDark = context.isDark;  // bool
final bg = context.bgColor;     // scaffold background color
```

**Toggle programmatically:**
```dart
LiftrApp.of(context).toggleTheme();
```

**Key colors:**
| Token | Dark | Light |
|---|---|---|
| `lt.surface` | `#15151A` | `#FFFFFF` |
| `lt.card` | `#1A1A1E` | `#F0F0EA` |
| `lt.textPrimary` | `#E2E2E6` | `#1A1A1E` |
| `lt.accentBg` | `#1A2208` | `#EEFAD8` |
| `LiftrColors.accent` | `#C8F075` | `#C8F075` |

## Screens

### Login (`login_screen.dart`)
- Email + password fields with show/hide toggle
- Google + Apple SSO buttons
- "Forgot password" link
- Sign-up footer

### Onboarding (`onboarding_screen.dart`)
3 animated pages with `PageView`:
1. **Activity** — 2-column grid with 6 activity types
2. **Level** — Beginner / Intermediate / Advanced selector
3. **Template** — Use template vs blank slate

### Home (`home_screen.dart`)
- Greeting header + avatar
- 7-day calendar strip with week navigation arrows
  - Green dots indicate days with logged workouts
  - Today highlighted with accent background
  - Selected day highlighted with filled accent circle
- Workout card with:
  - Session name + level tag
  - Add exercise button
  - Exercise list with emoji icon, sets/reps, weight badge, 3-dot menu

### Exercise Detail (`exercise_detail_screen.dart`)
- Back navigation + exercise name header
- Line chart painted with `CustomPainter` (no dependencies)
- Session notes text area
- Set-by-set breakdown for selected date
- Active set highlighted with accent border
- Inline weight + reps input with Save button

## Next steps

- [ ] Wire up state management (provider / riverpod / bloc)
- [ ] Add local database (Isar or SQLite)
- [ ] Build Settings / Exercise Catalog screen
- [ ] Add richer charts with `fl_chart`
- [ ] Machine settings (seat height, back rest) for gym exercises
- [ ] Push notifications for workout reminders
- [ ] Export to CSV
