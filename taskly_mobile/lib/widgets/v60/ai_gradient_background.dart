import 'package:flutter/material.dart';

import '../../core/theme/taskly_ai_theme.dart';

class AiGradientBackground extends StatefulWidget {
  const AiGradientBackground({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  State<AiGradientBackground> createState() => _AiGradientBackgroundState();
}

class _AiGradientBackgroundState extends State<AiGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: dark
                ? TasklyAiColors.darkCanvas
                : TasklyAiColors.lightCanvas,
            gradient: RadialGradient(
              center: Alignment(-0.8 + t * 1.2, -1.1 + t * 0.3),
              radius: 1.45,
              colors: [
                TasklyAiColors.violet.withValues(
                  alpha: dark ? 0.28 : 0.12,
                ),
                TasklyAiColors.electric.withValues(
                  alpha: dark ? 0.12 : 0.05,
                ),
                Colors.transparent,
              ],
              stops: const [0, 0.43, 1],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -90 + t * 30,
                bottom: -120,
                child: _GlowOrb(
                  size: 320,
                  color: TasklyAiColors.magenta.withValues(
                    alpha: dark ? 0.12 : 0.055,
                  ),
                ),
              ),
              Padding(
                padding: widget.padding,
                child: child,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 90,
              spreadRadius: 30,
            ),
          ],
        ),
      ),
    );
  }
}

class AiGradientButton extends StatelessWidget {
  const AiGradientButton({
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
      opacity: onPressed == null ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: TasklyAiColors.aiGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: TasklyAiColors.violet.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 15,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 19),
                    const SizedBox(width: 9),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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
