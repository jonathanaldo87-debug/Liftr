import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final confirm = _confirmPassCtrl.text;

    if (pass != confirm) {
      setState(() => _errorMsg = 'Passwords do not match.');
      return;
    }

    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: pass,
      );

      if (!mounted) return;

      // If email confirmation is disabled in Supabase, session is available immediately
      if (res.session != null) {
        // A brand-new account has never onboarded, so this lands on Onboarding.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => landingScreen()),
        );
      } else {
        // Email confirmation is required — show a message and go back to login
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check your email to confirm your account.')),
        );
        Navigator.pop(context);
      }
    } on AuthException catch (e) {
      setState(() => _errorMsg = e.message);
    } catch (_) {
      setState(() => _errorMsg = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: LiftrSpacing.x24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: LiftrSpacing.x28),
              Center(
                child: Column(
                  children: [
                    const LiftrLogoMark(size: 52),
                    const SizedBox(height: LiftrSpacing.x12),
                    Text('Liftr', style: tt.displaySmall),
                    const SizedBox(height: LiftrSpacing.x3),
                    Text(
                      'Track every rep',
                      style: TextStyle(fontSize: LiftrType.x12, color: lt.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LiftrSpacing.x36),

              Text('Create your\naccount.', style: tt.displayMedium),
              const SizedBox(height: LiftrSpacing.x6),
              Text(
                'Start tracking your workouts today',
                style: TextStyle(fontSize: LiftrType.x13, color: lt.textMuted),
              ),
              const SizedBox(height: LiftrSpacing.x28),

              // Email
              const SectionLabel('Email'),
              const SizedBox(height: LiftrSpacing.x6),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
                decoration: const InputDecoration(hintText: 'you@email.com'),
              ),
              const SizedBox(height: LiftrSpacing.x14),

              // Password
              const SectionLabel('Password'),
              const SizedBox(height: LiftrSpacing.x6),
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
                decoration: InputDecoration(
                  hintText: '••••••••••',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                      color: lt.textMuted,
                    ),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x14),

              // Confirm password
              const SectionLabel('Confirm Password'),
              const SizedBox(height: LiftrSpacing.x6),
              TextField(
                controller: _confirmPassCtrl,
                obscureText: _obscureConfirm,
                style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
                decoration: InputDecoration(
                  hintText: '••••••••••',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18,
                      color: lt.textMuted,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),

              // Error message
              if (_errorMsg != null) ...[
                const SizedBox(height: LiftrSpacing.x10),
                Text(
                  _errorMsg!,
                  style: const TextStyle(fontSize: LiftrType.x12, color: LiftrColors.danger),
                ),
              ],

              const SizedBox(height: LiftrSpacing.x20),

              // CTA
              ElevatedButton(
                onPressed: _isLoading ? null : _signUp,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: LiftrColors.accentText),
                      )
                    : const Text('Create Account'),
              ),
              const SizedBox(height: LiftrSpacing.x24),

              // Log in footer
              Center(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: LiftrType.x12, color: lt.textDim),
                    children: [
                      const TextSpan(text: 'Already have an account? '),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text(
                            'Log in',
                            style: TextStyle(
                              fontSize: LiftrType.x12,
                              color: LiftrColors.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x32),
            ],
          ),
        ),
      ),
    );
  }
}
