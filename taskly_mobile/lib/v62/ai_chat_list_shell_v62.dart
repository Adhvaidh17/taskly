import 'dart:ui';

import 'package:flutter/material.dart';

import 'ai_universe_shell_v62.dart';
import 'taskly_ai_theme_v62.dart';

class ChatPreviewV62 {
  const ChatPreviewV62({
    required this.id,
    required this.title,
    required this.preview,
    required this.timeLabel,
    this.avatarUrl,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.aiTaskCount = 0,
  });
  final String id;
  final String title;
  final String preview;
  final String timeLabel;
  final String? avatarUrl;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final int aiTaskCount;
}

class AiChatListShellV62 extends StatefulWidget {
  const AiChatListShellV62({
    super.key,
    required this.chats,
    required this.onOpenChat,
    required this.onNewChat,
    this.onSearch,
    this.onMore,
    this.onOpenAiInbox,
  });
  final List<ChatPreviewV62> chats;
  final ValueChanged<ChatPreviewV62> onOpenChat;
  final VoidCallback onNewChat;
  final VoidCallback? onSearch;
  final VoidCallback? onMore;
  final VoidCallback? onOpenAiInbox;

  @override
  State<AiChatListShellV62> createState() => _AiChatListShellV62State();
}

class _AiChatListShellV62State extends State<AiChatListShellV62> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final chats = widget.chats.where((chat) {
      if (q.isEmpty) return true;
      return chat.title.toLowerCase().contains(q) || chat.preview.toLowerCase().contains(q);
    }).toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AiUniverseShellV62(
        intensity: .38,
        showStars: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
                child: Row(
                  children: [
                    const TasklyIntelligenceOrbV62(size: 40, compact: true),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chats', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                          Text('Your conversations, tasks and ideas', style: TextStyle(fontSize: 11.5, color: context.tasklyMutedV62)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: widget.onSearch, icon: const Icon(Icons.search_rounded)),
                    IconButton(onPressed: widget.onMore, icon: const Icon(Icons.more_horiz_rounded)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 9),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'Search people, groups or messages',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: q.isEmpty
                            ? const Icon(Icons.auto_awesome_rounded, size: 18)
                            : IconButton(onPressed: () => setState(() => _query = ''), icon: const Icon(Icons.close_rounded)),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.onOpenAiInbox != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 1, 16, 8),
                  child: _AiInboxCard(onTap: widget.onOpenAiInbox!),
                ),
              Expanded(
                child: chats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const TasklyIntelligenceOrbV62(size: 62),
                            const SizedBox(height: 14),
                            Text(q.isEmpty ? 'No conversations yet' : 'No chats match that search', style: TextStyle(color: context.tasklyMutedV62, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 5),
                            Text(q.isEmpty ? 'Start a focused conversation with Taskly.' : 'Try a name, group or message.', style: TextStyle(color: context.tasklyMutedV62, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 112),
                        itemCount: chats.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) => _ChatTileV62(
                          chat: chats[index],
                          onTap: () => widget.onOpenChat(chats[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          gradient: TasklyAiThemeV62.auroraHorizontal,
          borderRadius: BorderRadius.circular(99),
          boxShadow: [BoxShadow(color: TasklyAiThemeV62.violet.withValues(alpha: .30), blurRadius: 28, offset: const Offset(0, 10))],
        ),
        child: FloatingActionButton.extended(
          heroTag: 'new-chat-v62',
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          onPressed: widget.onNewChat,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New chat', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}

class _AiInboxCard extends StatelessWidget {
  const _AiInboxCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [TasklyAiThemeV62.violet.withValues(alpha: .17), TasklyAiThemeV62.cyan.withValues(alpha: .09)]),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.tasklyBorderV62),
          ),
          child: const Row(
            children: [
              TasklyIntelligenceOrbV62(size: 34, compact: true),
              SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Taskly AI', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 2), Text('Review task suggestions without interrupting chats', style: TextStyle(fontSize: 11.5))])),
              Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatTileV62 extends StatelessWidget {
  const _ChatTileV62({required this.chat, required this.onTap});
  final ChatPreviewV62 chat;
  final VoidCallback onTap;

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
              _Avatar(chat: chat),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w850))),
                      if (chat.isPinned) Icon(Icons.push_pin_outlined, size: 14, color: context.tasklyMutedV62),
                      const SizedBox(width: 7),
                      Text(chat.timeLabel, style: TextStyle(fontSize: 10.5, color: context.tasklyMutedV62)),
                    ]),
                    const SizedBox(height: 5),
                    Row(children: [
                      if (chat.isMuted) ...[Icon(Icons.volume_off_outlined, size: 13, color: context.tasklyMutedV62), const SizedBox(width: 4)],
                      Expanded(child: Text(chat.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: context.tasklyMutedV62))),
                      if (chat.aiTaskCount > 0) ...[const SizedBox(width: 6), Icon(Icons.auto_awesome_rounded, size: 13, color: Theme.of(context).colorScheme.primary)],
                      if (chat.unreadCount > 0) ...[
                        const SizedBox(width: 7),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(gradient: TasklyAiThemeV62.auroraHorizontal, borderRadius: BorderRadius.circular(99)), child: Text(chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
                      ],
                    ]),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.chat});
  final ChatPreviewV62 chat;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(1.5),
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: TasklyAiThemeV62.auroraHorizontal),
      child: CircleAvatar(
        foregroundImage: (chat.avatarUrl ?? '').trim().isNotEmpty ? NetworkImage(chat.avatarUrl!) : null,
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: Text(chat.title.isEmpty ? '?' : chat.title.characters.first.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}
