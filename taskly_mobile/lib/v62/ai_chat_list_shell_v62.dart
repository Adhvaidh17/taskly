import 'package:flutter/material.dart';

import 'taskly_ai_theme_v62.dart';

class AiChatListShellV62 extends StatelessWidget {
  const AiChatListShellV62({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: context.tasklyBackgroundV62),
      child: Stack(
        children: [
          Positioned(top: -120, right: -100, child: _Glow(size: 280, color: TasklyAiThemeV62.electricViolet)),
          Positioned(top: 260, left: -150, child: _Glow(size: 330, color: TasklyAiThemeV62.cyan)),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: context.isDarkV62 ? .15 : .12), color.withValues(alpha: 0)]),
          ),
        ),
      );
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
    this.isGroup = false,
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
  final bool isGroup;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TasklyGlassV62(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
                        if (isPinned) Icon(Icons.push_pin_rounded, size: 14, color: context.tasklyMutedV62),
                        if (timeLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(timeLabel, style: TextStyle(fontSize: 10.5, color: context.tasklyMutedV62)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (isGroup) ...[
                          Icon(Icons.people_alt_outlined, size: 13, color: context.tasklyMutedV62),
                          const SizedBox(width: 4),
                        ],
                        if (isMuted) ...[
                          Icon(Icons.volume_off_outlined, size: 13, color: context.tasklyMutedV62),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            preview.isEmpty ? (isGroup ? 'Group conversation' : 'Start a private conversation') : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: context.tasklyMutedV62),
                          ),
                        ),
                        if (aiTaskCount > 0) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.auto_awesome_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                        ],
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(gradient: TasklyAiThemeV62.auroraHorizontal, borderRadius: BorderRadius.circular(99)),
                            child: Text(unreadCount > 99 ? '99+' : '$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
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
