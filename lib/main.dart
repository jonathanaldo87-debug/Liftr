import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/prefs.dart';
import 'theme/app_theme.dart';
import 'widgets/rest_timer_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://fenwzvwhmutoappysqdr.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlbnd6dndobXV0b2FwcHlzcWRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3NDg2OTUsImV4cCI6MjA4OTMyNDY5NX0.edotP7cZbnSO5KruZXkqkWXXewBgLRqLdpXYNx0AZLI',
  );

  await Prefs.init();

  runApp(const LiftrApp());
}

Widget landingScreen() {
  if (!AuthService.isSignedIn) return const LoginScreen();
  return Prefs.hasOnboarded ? const HomeScreen() : const OnboardingScreen();
}

class LiftrApp extends StatefulWidget {
  const LiftrApp({super.key});

  static LiftrAppState of(BuildContext context) =>
      context.findAncestorStateOfType<LiftrAppState>()!;

  @override
  State<LiftrApp> createState() => LiftrAppState();
}

class LiftrAppState extends State<LiftrApp> {
  ThemeMode _themeMode =
      Prefs.isDarkMode ? ThemeMode.dark : ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
    Prefs.setDarkMode(_themeMode == ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liftr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      builder: (context, child) =>
          child == null ? const SizedBox.shrink() : RestTimerHost(child: child),
      home: landingScreen(),
    );
  }
}
