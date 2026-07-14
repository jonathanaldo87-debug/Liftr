import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://fenwzvwhmutoappysqdr.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlbnd6dndobXV0b2FwcHlzcWRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3NDg2OTUsImV4cCI6MjA4OTMyNDY5NX0.edotP7cZbnSO5KruZXkqkWXXewBgLRqLdpXYNx0AZLI',
  );

  runApp(const LiftrApp());
}

class LiftrApp extends StatefulWidget {
  const LiftrApp({super.key});

  // Static method so child widgets can toggle theme
  static _LiftrAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_LiftrAppState>()!;

  @override
  State<LiftrApp> createState() => _LiftrAppState();
}

class _LiftrAppState extends State<LiftrApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  ThemeMode get themeMode => _themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liftr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: Supabase.instance.client.auth.currentSession != null
          ? const HomeScreen()
          : const LoginScreen(),
    );
  }
}
