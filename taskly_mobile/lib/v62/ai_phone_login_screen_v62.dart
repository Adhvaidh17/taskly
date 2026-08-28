import 'package:flutter/material.dart';

import 'ai_universe_shell_v62.dart';
import 'taskly_ai_theme_v62.dart';

/// Primary-phone login for Taskly v6.2.
///
/// This screen deliberately feels different from an ordinary SaaS login:
/// phone identity first, a concise explanation of Taskly's AI behavior, and a
/// clear privacy promise. After OTP verification, route through the primary
/// device gate and Restore/Transfer screen before opening Chats.
class AiPhoneLoginScreenV62 extends StatefulWidget {
  const AiPhoneLoginScreenV62({
    super.key,
    required this.onRequestOtp,
    required this.onVerifyOtp,
    this.initialCountryCode = '+91',
    this.onUseEmailInstead,
    this.onVerifyWithOldPhone,
  });

  final Future<void> Function(String fullPhone) onRequestOtp;
  final Future<void> Function(String fullPhone, String otp) onVerifyOtp;
  final String initialCountryCode;
  final VoidCallback? onUseEmailInstead;

  /// Optional WhatsApp-like route: if the old primary phone is available, the
  /// app can approve this new phone there instead of relying only on SMS.
  final VoidCallback? onVerifyWithOldPhone;

  @override
  State<AiPhoneLoginScreenV62> createState() => _AiPhoneLoginScreenV62State();
}

class _AiPhoneLoginScreenV62State extends State<AiPhoneLoginScreenV62> {
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
    var code = _country.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (code.isNotEmpty && !code.startsWith('+')) code = '+$code';
    final number = _phone.text.trim().replaceAll(RegExp(r'\D'), '');
    return '$code$number';
  }

  Future<void> _sendOtp() async {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
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
    final otp = _otp.text.trim().replaceAll(RegExp(r'\D'), '');
    if (otp.length < 4) {
      setState(() => _error = 'Enter the verification code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onVerifyOtp(_fullPhone, otp);
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
      body: AiUniverseShellV62(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _brandRow(context),
                        SizedBox(height: constraints.maxHeight > 760 ? 26 : 16),
                        Center(
                          child: Hero(
                            tag: 'taskly-intelligence-orb',
                            child: TasklyIntelligenceOrbV62(
                              size: constraints.maxHeight > 760 ? 124 : 94,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          _otpSent
                              ? 'Make this your\nTaskly phone.'
                              : 'Chat. Ask.\nWork appears.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _otpSent
                              ? 'Verify your number. If this is a new primary phone, Taskly will offer your encrypted backup or a direct transfer before Chats opens.'
                              : 'Taskly understands requests inside normal conversations and turns only the work into synced tasks. Your chat history stays on your devices.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.tasklyMutedV62,
                              ),
                        ),
                        const SizedBox(height: 24),
                        AiGlassCardV62(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _otpSent ? _otpForm(context) : _phoneForm(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 15, color: scheme.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Private chat history · encrypted backup · synced tasks',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 11.5,
                                      color: context.tasklyMutedV62,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _brandRow(BuildContext context) {
    return Row(
      children: [
        const TasklyIntelligenceOrbV62(size: 34, compact: true),
        const SizedBox(width: 10),
        const Text(
          'Taskly',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.7),
        ),
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                TasklyAiThemeV62.violet.withValues(alpha: .16),
                TasklyAiThemeV62.cyan.withValues(alpha: .10),
              ],
            ),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: context.tasklyBorderV62),
          ),
          child: Text(
            'AI',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Spacer(),
        Icon(Icons.shield_outlined, size: 19, color: context.tasklyMutedV62),
      ],
    );
  }

  Widget _phoneForm(BuildContext context) {
    return Column(
      key: const ValueKey('phone-form-v62'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Continue with your number', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(
          'One number identifies your primary Taskly account.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 94,
              child: TextField(
                controller: _country,
                keyboardType: TextInputType.phone,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
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
                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                ),
              ),
            ),
          ],
        ),
        _errorView(context),
        const SizedBox(height: 16),
        AiGradientButtonV62(
          label: 'Continue',
          loading: _busy,
          icon: Icons.arrow_forward_rounded,
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
      key: const ValueKey('otp-form-v62'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Verify $_fullPhone', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text('Enter the code sent to your phone.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          enabled: !_busy,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _verify(),
          decoration: const InputDecoration(
            labelText: 'Verification code',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        _errorView(context),
        const SizedBox(height: 16),
        AiGradientButtonV62(
          label: 'Verify & continue',
          loading: _busy,
          icon: Icons.verified_user_outlined,
          onPressed: _busy ? null : _verify,
        ),
        const SizedBox(height: 5),
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
              child: const Text('Resend'),
            ),
          ],
        ),
        if (widget.onVerifyWithOldPhone != null) ...[
          const Divider(height: 20),
          OutlinedButton.icon(
            onPressed: _busy ? null : widget.onVerifyWithOldPhone,
            icon: const Icon(Icons.phone_android_rounded),
            label: const Text('Verify using old phone'),
          ),
        ],
      ],
    );
  }

  Widget _errorView(BuildContext context) {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        _error!,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
    );
  }
}
