import 'package:flutter/material.dart';

import '../../widgets/v60/ai_gradient_background.dart';

class AiOnboardingScreen extends StatefulWidget {
  const AiOnboardingScreen({
    super.key,
    required this.onComplete,
  });

  final Future<void> Function() onComplete;

  @override
  State<AiOnboardingScreen> createState() => _AiOnboardingScreenState();
}

class _AiOnboardingScreenState extends State<AiOnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _working = false;

  static const _items = [
    (
      title: 'Talk normally',
      body:
          'Message people exactly as you would in any chat. No commands. No special grammar.',
      icon: Icons.chat_bubble_rounded,
      sample: 'Karthik, send the final quotation tomorrow before 11.',
    ),
    (
      title: 'Taskly understands intent',
      body:
          'Requests, owners and deadlines are recognised quietly. Nothing interrupts a normal conversation.',
      icon: Icons.auto_awesome_rounded,
      sample: 'Task detected  ·  Karthik  ·  Tomorrow 11:00 AM',
    ),
    (
      title: 'Work appears when it matters',
      body:
          'Confirm once. The task is organised and synced, while the actual chat stays private on your devices.',
      icon: Icons.check_circle_rounded,
      sample: 'Final quotation  ·  To do  ·  Tomorrow',
    ),
  ];

  Future<void> _next() async {
    if (_index < _items.length - 1) {
      await _pages.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    setState(() => _working = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AiGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                child: Row(
                  children: [
                    const Text(
                      'Taskly',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const Spacer(),
                    if (_index < _items.length - 1)
                      TextButton(
                        onPressed: _working ? null : () async {
                          setState(() => _index = _items.length - 1);
                          await _pages.animateToPage(
                            _items.length - 1,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                          );
                        },
                        child: const Text('Skip'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _items.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return _OnboardingPage(
                      title: item.title,
                      body: item.body,
                      icon: item.icon,
                      sample: item.sample,
                      index: index,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 24 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              color: i == _index
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.14),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    AiGradientButton(
                      label: _index == _items.length - 1
                          ? 'Start using Taskly'
                          : 'Continue',
                      icon: _index == _items.length - 1
                          ? Icons.arrow_forward_rounded
                          : null,
                      onPressed: _working ? null : _next,
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

class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({
    required this.title,
    required this.body,
    required this.icon,
    required this.sample,
    required this.index,
  });

  final String title;
  final String body;
  final IconData icon;
  final String sample;
  final int index;

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 40, 22, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final glow = 16 + _pulse.value * 18;
              return Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF7C3CFF),
                      Color(0xFFD64EFF),
                      Color(0xFF4C6FFF),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3CFF)
                          .withValues(alpha: dark ? 0.34 : 0.18),
                      blurRadius: glow,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(widget.icon, size: 46, color: Colors.white),
              );
            },
          ),
          const SizedBox(height: 40),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 31),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Text(
              widget.body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: 34),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: dark ? 0.75 : 0.9),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: widget.index == 1 ? 0.32 : 0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.index == 0
                        ? Icons.person_rounded
                        : widget.index == 1
                            ? Icons.auto_awesome_rounded
                            : Icons.task_alt_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.sample,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
