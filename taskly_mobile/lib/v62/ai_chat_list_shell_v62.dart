import 'package:flutter/material.dart';

import 'taskly_ai_theme_v62.dart';

class AiChatListShellV62 extends StatelessWidget {
  const AiChatListShellV62({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.isDarkV62 ? TasklyAiThemeV62.ink : TasklyAiThemeV62.snow,
      ),
      child: child,
    );
  }
}

class AiChatListItemV62 extends StatelessWidget {
  const AiChatListItemV62({
    super.key,
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.avatar,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.aiTaskCount = 0,
    this.onTap,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final Widget avatar;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final int aiTaskCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          decoration: BoxDecoration(
            color: context.tasklyGlassV62,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.tasklyBorderV62),
          ),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (isPinned)
                          Icon(Icons.push_pin_outlined, size: 14, color: context.tasklyMutedV62),
                        const SizedBox(width: 7),
                        Text(
                          timeLabel,
                          style: TextStyle(fontSize: 10.5, color: context.tasklyMutedV62),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (isMuted) ...[
                          Icon(Icons.volume_off_outlined, size: 13, color: context.tasklyMutedV62),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: context.tasklyMutedV62),
                          ),
                        ),
                        if (aiTaskCount > 0) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.auto_awesome_rounded, size: 13, color: Theme.of(context).colorScheme.primary),
                        ],
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: const BoxDecoration(
                              gradient: TasklyAiThemeV62.auroraHorizontal,
                              borderRadius: BorderRadius.all(Radius.circular(99)),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ],
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
