import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/prefs.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://fenwzvwhmutoappysqdr.supabase.co',
    // Public by design: this key ships inside the APK and is only safe because
    // row-level security is enabled. Never put a service_role key here.
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlbnd6dndobXV0b2FwcHlzcWRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3NDg2OTUsImV4cCI6MjA4OTMyNDY5NX0.edotP7cZbnSO5KruZXkqkWXXewBgLRqLdpXYNx0AZLI',
  );

  // Awaited here so the first screen can be chosen synchronously, with no
  // loading flash between splash and content.
  await Prefs.init();

  runApp(const LiftrApp());
}

/// The screen to open on launch, and after signing in — as a guest or otherwise.
///
/// Signed out goes to Login. Signed in but never onboarded goes to Onboarding.
/// A guest is signed in like anyone else, so this needs no special case.
Widget landingScreen() {
  if (!AuthService.isSignedIn) return const LoginScreen();
  return Prefs.hasOnboarded ? const HomeScreen() : const OnboardingScreen();
}

class LiftrApp extends StatefulWidget {
  const LiftrApp({super.key});

  /// Lets any screen reach the theme toggle.
  static LiftrAppState of(BuildContext context) =>
      context.findAncestorStateOfType<LiftrAppState>()!;

  @override
  State<LiftrApp> createState() => LiftrAppState();
}

class LiftrAppState extends State<LiftrApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liftr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: landingScreen(),
    );
  }
}
