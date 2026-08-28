import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'taskly_ai_theme_v61.dart';

/// Subtle animated AI atmosphere. It intentionally avoids busy/heavy motion.
class AiGradientShellV61 extends StatefulWidget {
  const AiGradientShellV61({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;
  final bool animate;

  @override
  State<AiGradientShellV61> createState() => _AiGradientShellV61State();
}

class _AiGradientShellV61State extends State<AiGradientShellV61>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.animate) _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduce) return;
    _reduceMotion = reduce;
    if (_reduceMotion || !widget.animate) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AiGradientShellV61 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    widget.animate && !_reduceMotion
        ? _controller.repeat()
        : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF080A10), Color(0xFF0B0E18), Color(0xFF071315)]
              : const [Color(0xFFF9F9FF), Color(0xFFF4F7FF), Color(0xFFF4FFFE)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _GlowPainter(
                  phase: _reduceMotion ? 0 : _controller.value * math.pi * 2,
                  dark: dark,
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.phase, required this.dark});

  final double phase;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    final opacity = dark ? 0.14 : 0.18;

    void glow(Offset center, double radius, Color color) {
      p.shader = RadialGradient(
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, p);
    }

    glow(
      Offset(
        size.width * (0.12 + 0.03 * math.sin(phase)),
        size.height * (0.17 + 0.025 * math.cos(phase)),
      ),
      size.shortestSide * 0.75,
      TasklyAiThemeV61.violet,
    );
    glow(
      Offset(
        size.width * (0.88 + 0.025 * math.cos(phase * 0.8)),
        size.height * (0.38 + 0.035 * math.sin(phase * 0.7)),
      ),
      size.shortestSide * 0.66,
      TasklyAiThemeV61.cyan,
    );
    glow(
      Offset(size.width * 0.54, size.height * 0.9),
      size.shortestSide * 0.52,
      TasklyAiThemeV61.magenta,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.dark != dark;
  }
}

class AiGradientButtonV61 extends StatelessWidget {
  const AiGradientButtonV61({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: TasklyAiGradient.action,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: TasklyAiThemeV61.violet.withValues(alpha: 0.2),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 9),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
