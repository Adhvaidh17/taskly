import 'package:flutter/material.dart';

import 'ai_universe_shell_v62.dart';

/// Drop-in scaffold for existing Taskly screens so Chats, Tasks, Dashboard,
/// Settings and detail pages share one visual language without rewriting their
/// business logic.
class AiPageScaffoldV62 extends StatelessWidget {
  const AiPageScaffoldV62({
    super.key,
    required this.body,
    this.title,
    this.leading,
    this.actions = const [],
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.intensity = .24,
    this.showStars = false,
  });

  final Widget body;
  final String? title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final double intensity;
  final bool showStars;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: AiUniverseShellV62(
        intensity: intensity,
        showStars: showStars,
        child: SafeArea(
          child: Column(
            children: [
              if (title != null || leading != null || actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
                  child: Row(
                    children: [
                      if (leading != null) leading!,
                      if (leading != null) const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
