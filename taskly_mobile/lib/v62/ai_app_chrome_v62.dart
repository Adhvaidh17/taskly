import 'dart:ui';

import 'package:flutter/material.dart';

import 'taskly_ai_theme_v62.dart';

class AiNavItemV62 {
  const AiNavItemV62({required this.icon, required this.selectedIcon, required this.label, this.badge});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badge;
}

class AiBottomNavigationV62 extends StatelessWidget {
  const AiBottomNavigationV62({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.aiActionIndex,
  });

  final List<AiNavItemV62> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int? aiActionIndex;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              color: context.tasklyGlassV62,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: context.tasklyBorderV62),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: context.isDarkV62 ? .20 : .07),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: List.generate(items.length, (index) {
                final item = items[index];
                final selected = selectedIndex == index;
                final isAi = aiActionIndex == index;
                return Expanded(
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(19),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isAi)
                            Container(
                              width: 37,
                              height: 37,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: TasklyAiThemeV62.auroraHorizontal,
                                boxShadow: [
                                  BoxShadow(
                                    color: TasklyAiThemeV62.violet.withValues(alpha: .25),
                                    blurRadius: 18,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.auto_awesome_rounded, size: 19, color: Colors.white),
                            )
                          else
                            _NavIconV62(item: item, selected: selected),
                          const SizedBox(height: 3),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: selected || isAi ? FontWeight.w800 : FontWeight.w600,
                              color: selected || isAi
                                  ? Theme.of(context).colorScheme.primary
                                  : context.tasklyMutedV62,
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
        ),
      ),
    );
  }
}

class _NavIconV62 extends StatelessWidget {
  const _NavIconV62({required this.item, required this.selected});
  final AiNavItemV62 item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (selected)
            Container(
              width: 34,
              height: 30,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          Icon(
            selected ? item.selectedIcon : item.icon,
            size: 21,
            color: selected ? Theme.of(context).colorScheme.primary : context.tasklyMutedV62,
          ),
          if ((item.badge ?? 0) > 0)
            Positioned(
              right: -3,
              top: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(99),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.badge! > 99 ? '99+' : '${item.badge}',
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AiChatComposerSurfaceV62 extends StatelessWidget {
  const AiChatComposerSurfaceV62({super.key, required this.child, this.aiThinking = false});
  final Widget child;
  final bool aiThinking;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 230),
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      padding: const EdgeInsets.all(1.4),
      decoration: BoxDecoration(
        gradient: aiThinking
            ? TasklyAiThemeV62.auroraHorizontal
            : LinearGradient(colors: [context.tasklyBorderV62, context.tasklyBorderV62]),
        borderRadius: BorderRadius.circular(25),
        boxShadow: aiThinking
            ? [BoxShadow(color: TasklyAiThemeV62.violet.withValues(alpha: .17), blurRadius: 22)]
            : null,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(24),
        ),
        child: child,
      ),
    );
  }
}
