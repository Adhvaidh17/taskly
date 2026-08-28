import 'package:flutter/material.dart';

import 'ai_universe_shell_v62.dart';
import 'taskly_ai_theme_v62.dart';

class AiOnboardingScreenV62 extends StatefulWidget {
  const AiOnboardingScreenV62({super.key, required this.onComplete});

  final Future<void> Function() onComplete;

  @override
  State<AiOnboardingScreenV62> createState() => _AiOnboardingScreenV62State();
}

class _AiOnboardingScreenV62State extends State<AiOnboardingScreenV62> {
  final _controller = PageController();
  int _index = 0;
  bool _busy = false;

  static const _pages = <_OnboardingDataV62>[
    _OnboardingDataV62(
      eyebrow: 'CHAT NATURALLY',
      title: 'Say it normally.',
      body: 'No commands. No forms. English, Tanglish, Hinglish and everyday phrasing stay conversational.',
      type: _OnboardingVisualV62.chat,
    ),
    _OnboardingDataV62(
      eyebrow: 'TASKLY AI',
      title: 'The work appears quietly.',
      body: 'Taskly understands the request, owner and timing without filling the chat with AI status messages.',
      type: _OnboardingVisualV62.ai,
    ),
    _OnboardingDataV62(
      eyebrow: 'PRIVATE BY DESIGN',
      title: 'Chats stay with you.',
      body: 'Messages and chat media live on your device. Only confirmed tasks and required collaboration data sync.',
      type: _OnboardingVisualV62.private,
    ),
    _OnboardingDataV62(
      eyebrow: 'MOVE PHONES',
      title: 'Restore only when you choose.',
      body: 'Use encrypted Google Drive backup or direct old-phone transfer when you make another phone primary.',
      type: _OnboardingVisualV62.backup,
    ),
  ];

  Future<void> _next() async {
    if (_index < _pages.length - 1) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AiUniverseShellV62(
        intensity: .78,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    const TasklyIntelligenceOrbV62(size: 31, compact: true),
                    const SizedBox(width: 9),
                    const Text(
                      'Taskly',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.6),
                    ),
                    const Spacer(),
                    if (_index < _pages.length - 1)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _controller.animateToPage(
                                  _pages.length - 1,
                                  duration: const Duration(milliseconds: 390),
                                  curve: Curves.easeOutCubic,
                                ),
                        child: const Text('Skip'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) => _OnboardingPageV62(
                    data: _pages[index],
                    active: index == _index,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          width: i == _index ? 26 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            gradient: i == _index ? TasklyAiThemeV62.auroraHorizontal : null,
                            color: i == _index ? null : context.tasklyBorderV62,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AiGradientButtonV62(
                      label: _index == _pages.length - 1 ? 'Start Taskly' : 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      loading: _busy,
                      onPressed: _busy ? null : _next,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageV62 extends StatelessWidget {
  const _OnboardingPageV62({required this.data, required this.active});

  final _OnboardingDataV62 data;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Center(
              child: AnimatedScale(
                scale: active ? 1 : .96,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                child: _OnboardingVisualCardV62(type: data.type),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            data.eyebrow,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(data.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
            data.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.tasklyMutedV62,
                ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingVisualCardV62 extends StatelessWidget {
  const _OnboardingVisualCardV62({required this.type});
  final _OnboardingVisualV62 type;

  @override
  Widget build(BuildContext context) {
    return AiGlassCardV62(
      padding: const EdgeInsets.all(18),
      radius: 30,
      child: AspectRatio(
        aspectRatio: 1.12,
        child: switch (type) {
          _OnboardingVisualV62.chat => const _ChatDemoV62(),
          _OnboardingVisualV62.ai => const _AiDemoV62(),
          _OnboardingVisualV62.private => const _PrivateDemoV62(),
          _OnboardingVisualV62.backup => const _BackupDemoV62(),
        },
      ),
    );
  }
}

class _ChatDemoV62 extends StatelessWidget {
  const _ChatDemoV62();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _bubble(context, 'Arun, revised quote tomorrow before 11?', false),
        const SizedBox(height: 10),
        _bubble(context, 'Sure. I’ll send it by 10:30.', true),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.tasklyBorderV62),
                ),
                alignment: Alignment.centerLeft,
                child: Text('Message…', style: TextStyle(color: context.tasklyMutedV62)),
              ),
            ),
            const SizedBox(width: 9),
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: TasklyAiThemeV62.auroraHorizontal),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bubble(BuildContext context, String text, bool mine) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 235),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: mine ? TasklyAiThemeV62.auroraHorizontal : null,
          color: mine ? null : Theme.of(context).colorScheme.surface.withValues(alpha: .76),
          borderRadius: BorderRadius.circular(18),
          border: mine ? null : Border.all(color: context.tasklyBorderV62),
        ),
        child: Text(
          text,
          style: TextStyle(color: mine ? Colors.white : Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}

class _AiDemoV62 extends StatelessWidget {
  const _AiDemoV62();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const TasklyIntelligenceOrbV62(size: 78),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .70),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.tasklyBorderV62),
          ),
          child: Column(
            children: [
              _row(context, Icons.task_alt_rounded, 'Revised quote'),
              const SizedBox(height: 9),
              _row(context, Icons.person_outline_rounded, 'Arun'),
              const SizedBox(height: 9),
              _row(context, Icons.schedule_rounded, 'Tomorrow · 11:00 AM'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String label) => Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      );
}

class _PrivateDemoV62 extends StatelessWidget {
  const _PrivateDemoV62();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                TasklyAiThemeV62.violet.withValues(alpha: .24),
                TasklyAiThemeV62.cyan.withValues(alpha: .14),
              ],
            ),
          ),
          child: Icon(Icons.phone_android_rounded, size: 45, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 18),
        const Text('Messages + media', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('stored on this device', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: context.tasklyBorderV62),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_done_outlined, size: 16),
              SizedBox(width: 7),
              Text('Tasks sync', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackupDemoV62 extends StatelessWidget {
  const _BackupDemoV62();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _backupRow(context, Icons.qr_code_2_rounded, 'Old phone transfer', 'Direct & encrypted'),
        const SizedBox(height: 10),
        _backupRow(context, Icons.cloud_done_outlined, 'Google Drive', 'Encrypted backup'),
        const SizedBox(height: 10),
        _backupRow(context, Icons.arrow_forward_rounded, 'Skip restore', 'Start with empty chat history'),
      ],
    );
  }

  Widget _backupRow(BuildContext context, IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.tasklyBorderV62),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _OnboardingVisualV62 { chat, ai, private, backup }

class _OnboardingDataV62 {
  const _OnboardingDataV62({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.type,
  });

  final String eyebrow;
  final String title;
  final String body;
  final _OnboardingVisualV62 type;
}
