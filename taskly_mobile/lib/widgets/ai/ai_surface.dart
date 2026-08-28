import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AiSurface extends StatelessWidget {
  const AiSurface({
    super.key,
    required this.child,
    this.safeArea = false,
    this.showGrid = false,
    this.topGlow = true,
  });

  final Widget child;
  final bool safeArea;
  final bool showGrid;
  final bool topGlow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final content = Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [
                      Color(0xFF070710),
                      Color(0xFF0B0A17),
                      Color(0xFF0A0C14),
                    ]
                  : const [
                      Color(0xFFF8F7FF),
                      Color(0xFFF4F3FB),
                      Color(0xFFFBFBFE),
                    ],
            ),
          ),
        ),
        if (topGlow)
          const Positioned(
            left: -80,
            right: -80,
            top: -190,
            height: 430,
            child: IgnorePointer(child: _TopAura()),
          ),
        Positioned(
          right: -130,
          top: 180,
          width: 330,
          height: 330,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: dark
                      ? const [Color(0x3A9B5CFF), Color(0x00000000)]
                      : const [Color(0x239C6BFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: -140,
          bottom: -120,
          width: 340,
          height: 340,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: dark
                      ? const [Color(0x2A4E8DFF), Color(0x00000000)]
                      : const [Color(0x174E8DFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
        ),
        if (showGrid)
          IgnorePointer(
            child: CustomPaint(painter: _GridPainter(dark: dark)),
          ),
        safeArea ? SafeArea(child: child) : child,
      ],
    );
    return content;
  }
}

class _TopAura extends StatelessWidget {
  const _TopAura();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(0, .25),
          radius: .65,
          colors: dark
              ? const [
                  Color(0xCC7A2BFF),
                  Color(0x88783DFF),
                  Color(0x3F235DFF),
                  Color(0x00000000),
                ]
              : const [
                  Color(0x8FA778FF),
                  Color(0x55CDA3FF),
                  Color(0x283A78FF),
                  Color(0x00FFFFFF),
                ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (dark ? Colors.white : const Color(0xFF5D4BD8))
          .withValues(alpha: dark ? .035 : .028)
      ..strokeWidth = .7;
    const gap = 34.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class AiGlassCard extends StatelessWidget {
  const AiGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = 22,
    this.onTap,
    this.gradient,
    this.borderColor,
    this.blur = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = borderColor ??
        (dark
            ? Colors.white.withValues(alpha: .10)
            : const Color(0xFF6D5CE7).withValues(alpha: .13));
    final fill = gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  Colors.white.withValues(alpha: .075),
                  const Color(0xFF6D42B8).withValues(alpha: .055),
                  Colors.white.withValues(alpha: .028),
                ]
              : [
                  Colors.white.withValues(alpha: .86),
                  const Color(0xFFF5F0FF).withValues(alpha: .72),
                  Colors.white.withValues(alpha: .72),
                ],
        );
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .19 : .045),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: onTap == null
          ? card
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTap,
                child: card,
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
    this.height = 52,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? .45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFD754F4), Color(0xFF7A39FF), Color(0xFF5C4BFF)],
          ),
          borderRadius: BorderRadius.circular(compact ? 16 : 18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8A45FF).withValues(alpha: .30),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(compact ? 16 : 18),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 15 : 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: compact ? 18 : 20),
                      const SizedBox(width: 8),
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
      ),
    );
  }
}

class AiSearchField extends StatelessWidget {
  const AiSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AiGlassCard(
      radius: 20,
      padding: EdgeInsets.zero,
      blur: 14,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: trailing,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintStyle: TextStyle(
            color: context.taskly.textFaint,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF17131F),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AiSectionTitle extends StatelessWidget {
  const AiSectionTitle({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.55,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.taskly.textMuted,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class AiOrb extends StatefulWidget {
  const AiOrb({super.key, this.size = 66});
  final double size;

  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * math.pi * 2;
        return Transform.rotate(
          angle: math.sin(t) * .035,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-.2, -.28),
                colors: [
                  Color(0xFFF7C8FF),
                  Color(0xFFD35DFF),
                  Color(0xFF7139FF),
                  Color(0xFF34206E),
                ],
                stops: [0, .24, .68, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9B45FF).withValues(alpha: .48),
                  blurRadius: 30,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Transform.rotate(
                angle: -math.sin(t) * .035,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: widget.size * .34,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AiIconDisc extends StatelessWidget {
  const AiIconDisc({
    super.key,
    required this.icon,
    this.size = 42,
    this.iconSize = 20,
    this.color,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: .30),
            accent.withValues(alpha: .09),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: .25)),
      ),
      child: Icon(icon, size: iconSize, color: accent),
    );
  }
}
