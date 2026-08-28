import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'taskly_ai_theme_v62.dart';

/// Shared background used by login, onboarding and other AI-heavy moments.
///
/// The supplied references use a large purple/blue halo, deep navy, glass and
/// tiny star/noise details. Taskly v6.2 translates that into an original
/// "intelligence field" rather than copying any supplied mascot/artwork.
class AiUniverseShellV62 extends StatefulWidget {
  const AiUniverseShellV62({
    super.key,
    required this.child,
    this.intensity = 1,
    this.animate = true,
    this.showStars = true,
  });

  final Widget child;
  final double intensity;
  final bool animate;
  final bool showStars;

  @override
  State<AiUniverseShellV62> createState() => _AiUniverseShellV62State();
}

class _AiUniverseShellV62State extends State<AiUniverseShellV62>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _disableMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
    if (widget.animate) _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_disableMotion == disabled) return;
    _disableMotion = disabled;
    if (disabled || !widget.animate) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AiUniverseShellV62 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate) return;
    if (widget.animate && !_disableMotion) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkV62;
    return ColoredBox(
      color: dark ? TasklyAiThemeV62.ink : TasklyAiThemeV62.snow,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _UniversePainterV62(
                  phase: _disableMotion ? 0 : _controller.value * math.pi * 2,
                  dark: dark,
                  intensity: widget.intensity.clamp(0, 1.4),
                  showStars: widget.showStars,
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

class _UniversePainterV62 extends CustomPainter {
  _UniversePainterV62({
    required this.phase,
    required this.dark,
    required this.intensity,
    required this.showStars,
  });

  final double phase;
  final bool dark;
  final double intensity;
  final bool showStars;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xFF060811), Color(0xFF0B1020), Color(0xFF07131D)]
            : const [Color(0xFFF9FAFF), Color(0xFFF3F5FF), Color(0xFFF5FBFF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    void glow({
      required Offset center,
      required double radius,
      required Color color,
      required double opacity,
    }) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity * intensity),
            color.withValues(alpha: opacity * .35 * intensity),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .42, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    final wobbleX = math.sin(phase) * size.width * .035;
    final wobbleY = math.cos(phase * .8) * size.height * .025;

    // Large top halo, inspired by the references' planetary/aurora geometry.
    glow(
      center: Offset(size.width * .56 + wobbleX, -size.height * .02 + wobbleY),
      radius: size.width * .78,
      color: TasklyAiThemeV62.violet,
      opacity: dark ? .52 : .22,
    );
    glow(
      center: Offset(size.width * .86 - wobbleX * .7, size.height * .16),
      radius: size.width * .58,
      color: TasklyAiThemeV62.indigo,
      opacity: dark ? .34 : .17,
    );
    glow(
      center: Offset(size.width * .24, size.height * .84 - wobbleY),
      radius: size.width * .55,
      color: TasklyAiThemeV62.pink,
      opacity: dark ? .20 : .10,
    );
    glow(
      center: Offset(size.width * .85, size.height * .88),
      radius: size.width * .44,
      color: TasklyAiThemeV62.cyan,
      opacity: dark ? .14 : .10,
    );

    // Thin curved orbital lines add an AI/space feel without using an image.
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (dark ? Colors.white : TasklyAiThemeV62.indigo)
          .withValues(alpha: dark ? .065 : .045);
    final orbitalRect = Rect.fromCenter(
      center: Offset(size.width * .55, size.height * .06),
      width: size.width * 1.35,
      height: size.width * .82,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(
        orbitalRect.inflate(i * 42),
        math.pi * .08,
        math.pi * .92,
        false,
        orbit,
      );
    }

    if (showStars && dark) {
      final star = Paint()..color = Colors.white.withValues(alpha: .30);
      const seeds = <Offset>[
        Offset(.08, .10), Offset(.18, .27), Offset(.30, .08), Offset(.42, .22),
        Offset(.71, .09), Offset(.84, .26), Offset(.94, .13), Offset(.12, .52),
        Offset(.26, .68), Offset(.79, .57), Offset(.91, .74), Offset(.63, .44),
        Offset(.38, .83), Offset(.72, .88), Offset(.16, .91), Offset(.54, .69),
      ];
      for (var i = 0; i < seeds.length; i++) {
        final p = seeds[i];
        final twinkle = .55 + .45 * math.sin(phase * (i.isEven ? .7 : 1.1) + i);
        star.color = Colors.white.withValues(alpha: .10 + .22 * twinkle);
        canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height),
          i % 5 == 0 ? 1.5 : .8,
          star,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UniversePainterV62 oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.dark != dark ||
      oldDelegate.intensity != intensity ||
      oldDelegate.showStars != showStars;
}

class AiGlassCardV62 extends StatelessWidget {
  const AiGlassCardV62({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.radius = 26,
    this.blur = 22,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double blur;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkV62;
    final radiusValue = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radiusValue,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .22 : .07),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radiusValue,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint ?? context.tasklyGlassV62,
              borderRadius: radiusValue,
              border: Border.all(color: context.tasklyBorderV62),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class AiGradientButtonV62 extends StatelessWidget {
  const AiGradientButtonV62({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : .58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: TasklyAiThemeV62.auroraHorizontal,
          borderRadius: BorderRadius.circular(19),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: TasklyAiThemeV62.violet.withValues(alpha: .27),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(19),
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading) ...[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 19, color: Colors.white),
                    const SizedBox(width: 9),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.1,
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

/// Original Taskly AI identity mark: an animated-looking neural orb built only
/// from Flutter primitives, so no external reference image is copied.
class TasklyIntelligenceOrbV62 extends StatelessWidget {
  const TasklyIntelligenceOrbV62({
    super.key,
    this.size = 116,
    this.compact = false,
  });

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkV62;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-.25, -.30),
                radius: .9,
                colors: [
                  Color(0xFFE7CAFF),
                  Color(0xFF9C55FF),
                  Color(0xFF5A52FF),
                  Color(0xFF2636C7),
                ],
                stops: [0, .27, .61, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: TasklyAiThemeV62.violet.withValues(alpha: dark ? .55 : .32),
                  blurRadius: size * .46,
                  spreadRadius: size * .03,
                ),
              ],
            ),
          ),
          Container(
            width: size * .72,
            height: size * .72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: .30)),
            ),
          ),
          CustomPaint(
            size: Size.square(size * .62),
            painter: _NeuralMarkPainterV62(compact: compact),
          ),
        ],
      ),
    );
  }
}

class _NeuralMarkPainterV62 extends CustomPainter {
  _NeuralMarkPainterV62({required this.compact});
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .78)
      ..strokeWidth = compact ? 1.2 : 1.7
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = Colors.white;
    final points = <Offset>[
      Offset(size.width * .50, size.height * .15),
      Offset(size.width * .23, size.height * .38),
      Offset(size.width * .76, size.height * .35),
      Offset(size.width * .33, size.height * .72),
      Offset(size.width * .70, size.height * .74),
      Offset(size.width * .50, size.height * .50),
    ];
    for (final pair in const <(int, int)>[(0, 5), (1, 5), (2, 5), (3, 5), (4, 5), (1, 3), (2, 4)]) {
      canvas.drawLine(points[pair.$1], points[pair.$2], line);
    }
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], compact ? 2.0 : 2.8, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralMarkPainterV62 oldDelegate) =>
      oldDelegate.compact != compact;
}
