import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/country_phone_field.dart';
import '../v62/ai_universe_shell_v62.dart';
import '../v62/taskly_ai_theme_v62.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _registerPhone = TextEditingController();
  final _registerEmail = TextEditingController();
  final _loginEmail = TextEditingController();
  final _loginPhone = TextEditingController();
  final _password = TextEditingController();

  bool _register = false;
  bool _loginWithPhone = false;
  bool _obscure = true;
  String _registerCountryIso = AppConfig.defaultCountryIso;
  String _loginCountryIso = AppConfig.defaultCountryIso;

  @override
  void dispose() {
    _name.dispose();
    _registerPhone.dispose();
    _registerEmail.dispose();
    _loginEmail.dispose();
    _loginPhone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = _register
        ? await auth.register(
            name: _name.text,
            phone: _registerPhone.text,
            countryIso: _registerCountryIso,
            email: _registerEmail.text,
            password: _password.text,
          )
        : _loginWithPhone
            ? await auth.loginWithPhone(
                phone: _loginPhone.text,
                countryIso: _loginCountryIso,
                password: _password.text,
              )
            : await auth.loginWithEmail(
                email: _loginEmail.text,
                password: _password.text,
              );

    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Unable to continue')),
      );
    } else if (_register && !auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created. Confirm your email, then sign in.'),
        ),
      );
      setState(() => _register = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AiUniverseShellV62(
        intensity: 0.75,
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TasklyIntelligenceOrbV62(size: 88),
                    const SizedBox(height: 12),
                    const _Logo(),
                    const SizedBox(height: 28),
                    Text(
                      _register ? 'Create your Taskly account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _register
                          ? 'Select your country and enter a mandatory mobile number.'
                          : 'Sign in using email or your verified mobile number.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.taskly.textMuted),
                    ),
                    const SizedBox(height: 22),
                    if (!_register) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.mail_outline),
                            label: Text('Email'),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.phone_outlined),
                            label: Text('Mobile'),
                          ),
                        ],
                        selected: {_loginWithPhone},
                        onSelectionChanged: auth.busy
                            ? null
                            : (values) => setState(
                                  () => _loginWithPhone = values.first,
                                ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      child: Column(
                        children: [
                          if (_register) ...[
                            TextFormField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) =>
                                  (value ?? '').trim().length < 2
                                      ? 'Enter your name'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            CountryPhoneField(
                              controller: _registerPhone,
                              initialCountryIso: _registerCountryIso,
                              onCountryChanged: (value) =>
                                  _registerCountryIso = value,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _registerEmail,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: (value) =>
                                  !(value ?? '').trim().contains('@')
                                      ? 'Enter a valid email'
                                      : null,
                            ),
                          ] else if (_loginWithPhone)
                            CountryPhoneField(
                              controller: _loginPhone,
                              initialCountryIso: _loginCountryIso,
                              onCountryChanged: (value) =>
                                  _loginCountryIso = value,
                            )
                          else
                            TextFormField(
                              controller: _loginEmail,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: (value) =>
                                  !(value ?? '').trim().contains('@')
                                      ? 'Enter a valid email'
                                      : null,
                            ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => (value ?? '').length < 6
                                ? 'Use at least 6 characters'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: auth.busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: auth.busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () => setState(() => _register = !_register),
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : 'New to Taskly? Create account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [TasklyAiThemeV62.electricViolet, TasklyAiThemeV62.indigo, TasklyAiThemeV62.cyan],
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: const Text(
            'T',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'Taskly',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}
