import 'package:flutter/material.dart';

import 'ai_gradient_shell_v61.dart';
import 'taskly_ai_theme_v61.dart';

class AiOnboardingScreenV61 extends StatefulWidget {
  const AiOnboardingScreenV61({super.key, required this.onComplete});

  final Future<void> Function() onComplete;

  @override
  State<AiOnboardingScreenV61> createState() => _AiOnboardingScreenV61State();
}

class _AiOnboardingScreenV61State extends State<AiOnboardingScreenV61> {
  final PageController _controller = PageController();
  int _index = 0;
  bool _busy = false;

  static const _pages = [
    _OnboardData(
      icon: Icons.chat_bubble_rounded,
      eyebrow: '01 · CHAT',
      title: 'Talk like you already do.',
      body: 'No commands. No special grammar. English, Tanglish, Hinglish or everyday phrasing can stay conversational.',
      example: 'Arun, send the revised quote tomorrow before 11.',
    ),
    _OnboardData(
      icon: Icons.auto_awesome_rounded,
      eyebrow: '02 · AI',
      title: 'The work is understood quietly.',
      body: 'Taskly detects the request, owner and timing without covering the chat with “detecting” or “creating” messages.',
      example: 'Revised quote · Arun · Tomorrow 11:00 AM',
    ),
    _OnboardData(
      icon: Icons.task_alt_rounded,
      eyebrow: '03 · TASKS',
      title: 'Only the task needs the cloud.',
      body: 'Confirmed tasks and task details sync to your account. The conversation itself stays on your devices.',
      example: 'Task synced · Chat remains private on-device',
    ),
    _OnboardData(
      icon: Icons.cloud_done_outlined,
      eyebrow: '04 · BACKUP',
      title: 'Move phones without storing chats with Taskly.',
      body: 'Use an end-to-end encrypted Google Drive backup or transfer directly from your old phone. You can also skip restore and start clean.',
      example: 'Settings → Chats → Chat backup',
    ),
  ];

  Future<void> _next() async {
    if (_index < _pages.length - 1) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 340),
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AiGradientShellV61(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 0),
                child: Row(
                  children: [
                    const Text('Taskly', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_index < _pages.length - 1)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _controller.animateToPage(
                                  _pages.length - 1,
                                  duration: const Duration(milliseconds: 360),
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
                  itemBuilder: (context, index) => _OnboardPage(data: _pages[index]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 26 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? scheme.primary
                                : scheme.onSurface.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    AiGradientButtonV61(
                      label: _index == _pages.length - 1 ? 'Start using Taskly' : 'Continue',
                      icon: _index == _pages.length - 1 ? Icons.arrow_forward_rounded : null,
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

class _OnboardPage extends StatelessWidget {
  const _OnboardPage({required this.data});
  final _OnboardData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: TasklyAiGradient.action,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(data.icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 26),
          Text(
            data.eyebrow,
            style: TextStyle(
              color: scheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 9),
          Text(data.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 34)),
          const SizedBox(height: 14),
          Text(
            data.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.66),
                ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(data.example, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardData {
  const _OnboardData({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.example,
  });
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final String example;
}
