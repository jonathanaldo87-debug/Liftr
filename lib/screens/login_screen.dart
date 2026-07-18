import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'sign_up_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _isLoading = false;
  bool _isGuestLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Creates an anonymous Supabase account, so the app has a real user id to
  /// hang workouts off and RLS keeps working exactly as it does for a login.
  Future<void> _continueAsGuest() async {
    setState(() {
      _isGuestLoading = true;
      _errorMsg = null;
    });
    try {
      await AuthService.signInAsGuest();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => landingScreen()),
        );
      }
    } on AuthException catch (e) {
      // The most likely cause by far: anonymous sign-ins are switched off in the
      // Supabase dashboard (Authentication → Sign In / Providers).
      setState(() => _errorMsg = e.message);
    } catch (_) {
      setState(() => _errorMsg = 'Could not start a guest session.');
    } finally {
      if (mounted) setState(() => _isGuestLoading = false);
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (mounted) {
        // Not HomeScreen directly: a first-time user has to see onboarding,
        // and landingScreen() is the single place that decides which is which.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => landingScreen()),
        );
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
              // Logo centred
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
                      style: TextStyle(
                          fontSize: LiftrType.x12, color: lt.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LiftrSpacing.x36),

              // Headline
              Text('Welcome\nback.', style: tt.displayMedium),
              const SizedBox(height: LiftrSpacing.x6),
              Text(
                'Log in to continue your streak',
                style: TextStyle(fontSize: LiftrType.x13, color: lt.textMuted),
              ),
              const SizedBox(height: LiftrSpacing.x28),

              // Email
              const SectionLabel('Email'),
              const SizedBox(height: LiftrSpacing.x6),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style:
                    TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
                decoration: const InputDecoration(hintText: 'you@email.com'),
              ),
              const SizedBox(height: LiftrSpacing.x14),

              // Password
              const SectionLabel('Password'),
              const SizedBox(height: LiftrSpacing.x6),
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                style:
                    TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
                decoration: InputDecoration(
                  hintText: '••••••••••',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: lt.textMuted,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: Text(
                    'Forgot password?',
                    style:
                        TextStyle(fontSize: LiftrType.x12, color: lt.accentMid),
                  ),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x12),

              // Error message
              if (_errorMsg != null) ...[
                const SizedBox(height: LiftrSpacing.x4),
                Text(
                  _errorMsg!,
                  style: const TextStyle(
                      fontSize: LiftrType.x12, color: LiftrColors.danger),
                ),
                const SizedBox(height: LiftrSpacing.x8),
              ],

              // CTA
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: LiftrColors.accentText),
                      )
                    : const Text('Continue'),
              ),
              const SizedBox(height: LiftrSpacing.x20),

              // Divider
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: LiftrSpacing.x12),
                    child: Text('or',
                        style: TextStyle(
                            fontSize: LiftrType.x12, color: lt.textDim)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: LiftrSpacing.x20),

              // Google SSO
              _SocialButton(
                label: 'Continue with Google',
                icon: const _GoogleIcon(),
                onTap: () {},
              ),
              const SizedBox(height: LiftrSpacing.x10),
              _SocialButton(
                label: 'Continue with Apple',
                icon: Icon(Icons.apple, size: 18, color: lt.textSecondary),
                onTap: () {},
              ),
              const SizedBox(height: LiftrSpacing.x10),
              _SocialButton(
                label:
                    _isGuestLoading ? 'Setting you up…' : 'Continue as guest',
                icon: _isGuestLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: lt.textSecondary,
                        ),
                      )
                    : Icon(Icons.person_outline,
                        size: 18, color: lt.textSecondary),
                onTap: _isGuestLoading || _isLoading ? () {} : _continueAsGuest,
              ),
              const SizedBox(height: LiftrSpacing.x8),
              Center(
                child: Text(
                  // Said up front, not buried in settings: a guest account only
                  // exists on this device, and signing out ends it.
                  'No email needed. Your workouts stay on this device\n'
                  'until you add a login.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: LiftrType.x11, color: lt.textDim, height: 1.5),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x24),

              // Sign-up footer
              Center(
                child: RichText(
                  text: TextSpan(
                    style:
                        TextStyle(fontSize: LiftrType.x12, color: lt.textDim),
                    children: [
                      const TextSpan(text: "Don't have an account? "),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SignUpScreen())),
                          child: const Text(
                            'Sign up',
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

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  const _SocialButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lt = context.lt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: LiftrSpacing.x14),
        decoration: BoxDecoration(
          color: lt.card,
          border: Border.all(color: lt.border, width: LiftrBorders.hairline),
          borderRadius: BorderRadius.circular(LiftrRadii.button),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: LiftrSpacing.x8),
            Text(
              label,
              style:
                  TextStyle(fontSize: LiftrType.x13, color: lt.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    void arc(double startAngle, double sweepAngle, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r - 1.8),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }

    arc(-0.35, 1.57, const Color(0xFF4285F4));
    arc(1.22, 1.57, const Color(0xFF34A853));
    arc(2.79, 1.57, const Color(0xFFFBBC05));
    arc(-1.92, 1.57, const Color(0xFFEA4335));
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
