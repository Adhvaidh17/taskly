import 'package:flutter/material.dart';

import 'taskly_ai_theme_v61.dart';

class AiNavDestinationV61 {
  const AiNavDestinationV61({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badge;
}

/// Compact AI-styled bottom navigation for the main Taskly shell.
class AiBottomNavigationV61 extends StatelessWidget {
  const AiBottomNavigationV61({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<AiNavDestinationV61> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: dark ? .94 : .96),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .22 : .08),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: List.generate(destinations.length, (index) {
            final item = destinations[index];
            final selected = index == selectedIndex;
            return Expanded(
              child: InkWell(
                onTap: () => onDestinationSelected(index),
                borderRadius: BorderRadius.circular(19),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(19),
                    gradient: selected
                        ? LinearGradient(
                            colors: [
                              TasklyAiThemeV61.violet.withValues(alpha: .16),
                              TasklyAiThemeV61.cyan.withValues(alpha: .10),
                            ],
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BadgeIcon(
                        icon: selected ? item.selectedIcon : item.icon,
                        badge: item.badge,
                        selected: selected,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class AiChatComposerSurfaceV61 extends StatelessWidget {
  const AiChatComposerSurfaceV61({
    super.key,
    required this.child,
    this.aiActive = false,
  });

  final Widget child;
  final bool aiActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 230),
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: aiActive
            ? TasklyAiGradient.action
            : LinearGradient(
                colors: [
                  scheme.outlineVariant.withValues(alpha: .55),
                  scheme.outlineVariant.withValues(alpha: .18),
                ],
              ),
        boxShadow: aiActive
            ? [
                BoxShadow(
                  color: TasklyAiThemeV61.violet.withValues(alpha: .14),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      ),
    );
  }
}

class AiTaskSuggestionBadgeV61 extends StatelessWidget {
  const AiTaskSuggestionBadgeV61({
    super.key,
    this.label = 'Taskly AI',
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            TasklyAiThemeV61.violet.withValues(alpha: .14),
            TasklyAiThemeV61.cyan.withValues(alpha: .10),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 13, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.icon, required this.badge, required this.selected});

  final IconData icon;
  final int? badge;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 22, color: selected ? scheme.primary : scheme.onSurfaceVariant),
        if ((badge ?? 0) > 0)
          Positioned(
            right: -9,
            top: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: scheme.error,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: scheme.surface, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                (badge ?? 0) > 99 ? '99+' : '${badge ?? 0}',
                style: TextStyle(
                  color: scheme.onError,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
