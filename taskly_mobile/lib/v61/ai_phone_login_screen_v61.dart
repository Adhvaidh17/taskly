import 'package:flutter/material.dart';

import 'ai_gradient_shell_v61.dart';
import 'ai_page_scaffold_v61.dart';
import 'taskly_ai_theme_v61.dart';

/// WhatsApp-style primary account entry for Taskly:
/// 1) verify the account/phone with OTP;
/// 2) the post-login gate registers this device as the primary phone;
/// 3) if it is new, show Restore/Transfer before opening the app.
///
/// Authentication itself is delegated to the existing Supabase phone-auth code.
class AiPhoneLoginScreenV61 extends StatefulWidget {
  const AiPhoneLoginScreenV61({
    super.key,
    required this.onRequestOtp,
    required this.onVerifyOtp,
    this.initialCountryCode = '+91',
    this.onUseEmailInstead,
  });

  final Future<void> Function(String fullPhone) onRequestOtp;
  final Future<void> Function(String fullPhone, String otp) onVerifyOtp;
  final String initialCountryCode;
  final VoidCallback? onUseEmailInstead;

  @override
  State<AiPhoneLoginScreenV61> createState() => _AiPhoneLoginScreenV61State();
}

class _AiPhoneLoginScreenV61State extends State<AiPhoneLoginScreenV61> {
  late final TextEditingController _country;
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _country = TextEditingController(text: widget.initialCountryCode);
  }

  @override
  void dispose() {
    _country.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  String get _fullPhone {
    final code = _country.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    final number = _phone.text.trim().replaceAll(RegExp(r'\D'), '');
    return '$code$number';
  }

  Future<void> _sendOtp() async {
    if (_phone.text.trim().replaceAll(RegExp(r'\D'), '').length < 6) {
      setState(() => _error = 'Enter a valid mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRequestOtp(_fullPhone);
      if (mounted) setState(() => _otpSent = true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    if (code.length < 4) {
      setState(() => _error = 'Enter the verification code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onVerifyOtp(_fullPhone, code);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
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
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _TasklyIdentity(),
                    const SizedBox(height: 30),
                    AiRevealV61(
                      child: Text(
                        _otpSent ? 'Verify this phone.' : 'Your work starts in chat.',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontSize: 38,
                              height: 1.02,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _otpSent
                          ? 'Enter the code sent to $_fullPhone. After verification, Taskly will check whether this is a new primary phone and offer restore or transfer.'
                          : 'Sign in with your mobile number. Chats live on your phone; tasks and collaboration stay synced.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    AiGlassPanelV61(
                      padding: const EdgeInsets.all(18),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: _otpSent ? _otpForm(context) : _phoneForm(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        AiFeatureChipV61(
                          icon: Icons.smart_toy_outlined,
                          label: 'AI task understanding',
                        ),
                        AiFeatureChipV61(
                          icon: Icons.phone_android_rounded,
                          label: 'Local chat history',
                        ),
                        AiFeatureChipV61(
                          icon: Icons.cloud_done_outlined,
                          label: 'Encrypted backup',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'When you move to another primary phone, Taskly asks whether to restore your encrypted Google Drive backup, transfer from your old phone, or continue without old chats. Your tasks still appear because task data is account-synced.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
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

  Widget _phoneForm(BuildContext context) {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Continue with phone', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 15),
        Row(
          children: [
            SizedBox(
              width: 92,
              child: TextField(
                controller: _country,
                keyboardType: TextInputType.phone,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Code'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                enabled: !_busy,
                autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _sendOtp(),
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        AiGradientButtonV61(
          label: _busy ? 'Sending code…' : 'Send verification code',
          icon: _busy ? null : Icons.arrow_forward_rounded,
          onPressed: _busy ? null : _sendOtp,
        ),
        if (widget.onUseEmailInstead != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : widget.onUseEmailInstead,
            child: const Text('Use email instead'),
          ),
        ],
      ],
    );
  }

  Widget _otpForm(BuildContext context) {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Verification code', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 15),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          enabled: !_busy,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _verify(),
          decoration: const InputDecoration(
            labelText: 'OTP',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        AiGradientButtonV61(
          label: _busy ? 'Verifying…' : 'Verify & continue',
          icon: _busy ? null : Icons.verified_user_outlined,
          onPressed: _busy ? null : _verify,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _otpSent = false;
                        _otp.clear();
                        _error = null;
                      }),
              child: const Text('Change number'),
            ),
            TextButton(
              onPressed: _busy ? null : _sendOtp,
              child: const Text('Resend code'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TasklyIdentity extends StatelessWidget {
  const _TasklyIdentity();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: TasklyAiGradient.action,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: TasklyAiThemeV61.violet.withValues(alpha: .24),
                blurRadius: 24,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
        const SizedBox(width: 11),
        const Text(
          'Taskly',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.7),
        ),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .11),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'AI',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
