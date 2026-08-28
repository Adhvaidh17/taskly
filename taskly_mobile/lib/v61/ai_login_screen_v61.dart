import 'package:flutter/material.dart';

import 'ai_gradient_shell_v61.dart';
import 'taskly_ai_theme_v61.dart';

class AiLoginScreenV61 extends StatefulWidget {
  const AiLoginScreenV61({
    super.key,
    required this.onLogin,
    this.onCreateAccount,
    this.onForgotPassword,
  });

  final Future<void> Function(String email, String password) onLogin;
  final VoidCallback? onCreateAccount;
  final VoidCallback? onForgotPassword;

  @override
  State<AiLoginScreenV61> createState() => _AiLoginScreenV61State();
}

class _AiLoginScreenV61State extends State<AiLoginScreenV61> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onLogin(email, _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AiGradientShellV61(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AiMark(),
                    const SizedBox(height: 28),
                    Text(
                      'Chat naturally.\nTaskly catches the work.',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontSize: 37,
                            height: 1.04,
                          ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      'AI turns everyday requests into clear tasks without turning your conversations into forms.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.68),
                          ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Welcome back',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _busy ? null : _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                style: TextStyle(color: scheme.error, fontSize: 12.5),
                              ),
                            ],
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _busy ? null : widget.onForgotPassword,
                                child: const Text('Forgot password?'),
                              ),
                            ),
                            AiGradientButtonV61(
                              label: _busy ? 'Signing in…' : 'Continue to Taskly',
                              icon: _busy ? null : Icons.arrow_forward_rounded,
                              onPressed: _busy ? null : _submit,
                            ),
                            if (widget.onCreateAccount != null) ...[
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: _busy ? null : widget.onCreateAccount,
                                child: const Text('Create a Taskly account'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, size: 18, color: scheme.primary),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Your chat history stays on your phone. Restore it on a new primary phone from your encrypted Google Drive backup or transfer it from your old phone. Tasks remain synced to your Taskly account.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  height: 1.45,
                                  color: scheme.onSurface.withValues(alpha: 0.6),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiMark extends StatelessWidget {
  const _AiMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: TasklyAiGradient.action,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: TasklyAiThemeV61.violet.withValues(alpha: 0.28),
                blurRadius: 20,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 11),
        const Text(
          'Taskly',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            'AI',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
