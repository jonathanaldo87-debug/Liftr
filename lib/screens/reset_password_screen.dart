import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

enum _Step { email, code, password }

class ResetPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ResetPasswordScreen({super.key, this.initialEmail});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _Step _step = _Step.email;

  bool _obscurePass = true;
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, _Step? next) async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (next != null) setState(() => _step = next);
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMsg = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMsg = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendCode() {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@') || email.length < 3) {
      setState(() => _errorMsg = 'Enter the email you signed up with.');
      return Future.value();
    }

    return _run(() => AuthService.requestPasswordReset(email), _Step.code);
  }

  Future<void> _verifyCode() {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _errorMsg = 'Enter the 6-digit code from the email.');
      return Future.value();
    }

    return _run(
      () => AuthService.verifyRecoveryCode(
        email: _emailCtrl.text.trim(),
        code: code,
      ),
      _Step.password,
    );
  }

  Future<void> _savePassword() {
    final pass = _passCtrl.text;
    if (pass.length < 6) {
      setState(() => _errorMsg = 'Use at least 6 characters.');
      return Future.value();
    }
    if (pass != _confirmCtrl.text) {
      setState(() => _errorMsg = 'Passwords do not match.');
      return Future.value();
    }

    return _run(() async {
      await AuthService.setPassword(pass);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => landingScreen()),
        (_) => false,
      );
    }, null);
  }

  void _back() {
    setState(() {
      _errorMsg = null;
      _step = _step == _Step.password ? _Step.code : _Step.email;
    });
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
              const SizedBox(height: LiftrSpacing.x12),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.arrow_back,
                      size: 20, color: lt.textSecondary),
                  onPressed: _isLoading
                      ? null
                      : _step == _Step.email
                          ? () => Navigator.pop(context)
                          : _back,
                ),
              ),
              const SizedBox(height: LiftrSpacing.x24),
              Center(
                child: Column(
                  children: [
                    const LiftrLogoMark(size: 52),
                    const SizedBox(height: LiftrSpacing.x12),
                    Text('Liftr', style: tt.displaySmall),
                  ],
                ),
              ),
              const SizedBox(height: LiftrSpacing.x36),

              Text(_title, style: tt.displayMedium),
              const SizedBox(height: LiftrSpacing.x6),
              Text(
                _subtitle,
                style: TextStyle(
                    fontSize: LiftrType.x13, color: lt.textMuted, height: 1.5),
              ),
              const SizedBox(height: LiftrSpacing.x28),

              ..._fields(lt),

              if (_errorMsg != null) ...[
                const SizedBox(height: LiftrSpacing.x12),
                Text(
                  _errorMsg!,
                  style: const TextStyle(
                      fontSize: LiftrType.x12, color: LiftrColors.danger),
                ),
              ],
              const SizedBox(height: LiftrSpacing.x20),

              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: LiftrColors.accentText),
                      )
                    : Text(_buttonLabel),
              ),

              if (_step == _Step.code) ...[
                const SizedBox(height: LiftrSpacing.x12),
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _sendCode,
                    child: Text(
                      'Send it again',
                      style: TextStyle(
                          fontSize: LiftrType.x12, color: lt.accentMid),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: LiftrSpacing.x24),
              Center(
                child: Text(
                  'Guest accounts have no email and no password, so there is '
                  'nothing to reset — sign up to get one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: LiftrType.x11, color: lt.textDim, height: 1.5),
                ),
              ),
              const SizedBox(height: LiftrSpacing.x32),
            ],
          ),
        ),
      ),
    );
  }

  String get _title => switch (_step) {
        _Step.email => 'Forgot your\npassword?',
        _Step.code => 'Check your\nemail.',
        _Step.password => 'Set a new\npassword.',
      };

  String get _subtitle => switch (_step) {
        _Step.email =>
          'Enter your email and we will send you a code to set a new one.',
        _Step.code => 'If ${_emailCtrl.text.trim()} has an account, a 6-digit '
            'code is on its way. It expires shortly.',
        _Step.password => 'Almost done. Choose something you will remember.',
      };

  String get _buttonLabel => switch (_step) {
        _Step.email => 'Send code',
        _Step.code => 'Verify code',
        _Step.password => 'Save password',
      };

  Future<void> _submit() => switch (_step) {
        _Step.email => _sendCode(),
        _Step.code => _verifyCode(),
        _Step.password => _savePassword(),
      };

  List<Widget> _fields(LiftrTheme lt) => switch (_step) {
        _Step.email => [
            const SectionLabel('Email'),
            const SizedBox(height: LiftrSpacing.x6),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
              decoration: const InputDecoration(hintText: 'you@email.com'),
            ),
          ],
        _Step.code => [
            const SectionLabel('Code'),
            const SizedBox(height: LiftrSpacing.x6),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize: LiftrType.x22,
                color: lt.textPrimary,
                letterSpacing: 8,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                hintText: '••••••',
                counterText: '',
              ),
            ),
          ],
        _Step.password => [
            const SectionLabel('New password'),
            const SizedBox(height: LiftrSpacing.x6),
            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
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
            const SizedBox(height: LiftrSpacing.x14),
            const SectionLabel('Confirm password'),
            const SizedBox(height: LiftrSpacing.x6),
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscurePass,
              style: TextStyle(fontSize: LiftrType.x14, color: lt.textPrimary),
              decoration: const InputDecoration(hintText: '••••••••••'),
            ),
          ],
      };
}
