import 'dart:ui';

import 'package:flutter/material.dart';

import 'ai_gradient_shell_v61.dart';
import 'taskly_ai_theme_v61.dart';

/// Shared visual shell for the rest of Taskly so the AI feel is not limited to
/// Login/Onboarding. Wrap Chats, Tasks, Profile/Settings and detail pages with
/// this rather than designing every screen independently.
class AiPageScaffoldV61 extends StatelessWidget {
  const AiPageScaffoldV61({
    super.key,
    required this.body,
    this.title,
    this.leading,
    this.actions = const [],
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.safeArea = true,
  });

  final Widget body;
  final String? title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (title != null || leading != null || actions.isNotEmpty)
          _AiTopBarV61(
            title: title,
            leading: leading,
            actions: actions,
          ),
        Expanded(child: body),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: AiGradientShellV61(
        child: safeArea ? SafeArea(child: content) : content,
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

class AiGlassPanelV61 extends StatelessWidget {
  const AiGlassPanelV61({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            blurRadius: 34,
            offset: const Offset(0, 14),
            color: Colors.black.withValues(alpha: dark ? .16 : .06),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: dark ? .42 : .60),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface.withValues(alpha: dark ? .80 : .86),
                  scheme.surfaceContainerLow.withValues(alpha: dark ? .66 : .76),
                ],
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class AiSectionTitleV61 extends StatelessWidget {
  const AiSectionTitleV61({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

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
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class AiFeatureChipV61 extends StatelessWidget {
  const AiFeatureChipV61({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            TasklyAiThemeV61.violet.withValues(alpha: .13),
            TasklyAiThemeV61.cyan.withValues(alpha: .10),
          ],
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class AiRevealV61 extends StatefulWidget {
  const AiRevealV61({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, .04),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<AiRevealV61> createState() => _AiRevealV61State();
}

class _AiRevealV61State extends State<AiRevealV61>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _position = Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(curve);
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _position, child: widget.child),
    );
  }
}

class _AiTopBarV61 extends StatelessWidget {
  const _AiTopBarV61({
    required this.title,
    required this.leading,
    required this.actions,
  });

  final String? title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          if (leading != null) leading!,
          if (leading != null) const SizedBox(width: 6),
          Expanded(
            child: Text(
              title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
