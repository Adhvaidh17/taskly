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
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AiUniverseShellV62(
        intensity: .30,
        showStars: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 9, 5),
                child: Row(
                  children: [
                    const TasklyIntelligenceOrbV62(size: 34, compact: true),
                    const SizedBox(width: 10),
                    Text('Chats', style: Theme.of(context).textTheme.headlineSmall),
                    const Spacer(),
                    IconButton(onPressed: widget.onSearch, icon: const Icon(Icons.search_rounded)),
                    IconButton(onPressed: widget.onMore, icon: const Icon(Icons.more_horiz_rounded)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 8),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search chats',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              if (widget.onOpenAiInbox != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onOpenAiInbox,
                      borderRadius: BorderRadius.circular(18),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              TasklyAiThemeV62.violet.withValues(alpha: .14),
                              TasklyAiThemeV62.cyan.withValues(alpha: .08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: context.tasklyBorderV62),
                        ),
                        child: Row(
                          children: [
                            const TasklyIntelligenceOrbV62(size: 32, compact: true),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Taskly AI', style: TextStyle(fontWeight: FontWeight.w800)),
                                  SizedBox(height: 2),
                                  Text('Review task suggestions without interrupting chats', style: TextStyle(fontSize: 11.5)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: chats.isEmpty
                    ? Center(child: Text('No chats found', style: TextStyle(color: context.tasklyMutedV62)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 2, 8, 100),
                        itemCount: chats.length,
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
          boxShadow: [
            BoxShadow(
              color: TasklyAiThemeV62.violet.withValues(alpha: .28),
              blurRadius: 24,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          heroTag: 'new-chat-v62',
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          onPressed: widget.onNewChat,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New chat', style: TextStyle(fontWeight: FontWeight.w800)),
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
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      leading: CircleAvatar(
        radius: 25,
        foregroundImage: (chat.avatarUrl ?? '').trim().isNotEmpty ? NetworkImage(chat.avatarUrl!) : null,
        child: Text(chat.title.isEmpty ? '?' : chat.title.characters.first.toUpperCase()),
      ),
      title: Row(
        children: [
          Expanded(child: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (chat.isPinned) ...[
            const SizedBox(width: 5),
            Icon(Icons.push_pin_outlined, size: 14, color: context.tasklyMutedV62),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          if (chat.isMuted) ...[
            Icon(Icons.volume_off_outlined, size: 14, color: context.tasklyMutedV62),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(chat.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (chat.aiTaskCount > 0) ...[
            const SizedBox(width: 6),
            Icon(Icons.auto_awesome_rounded, size: 13, color: scheme.primary),
            const SizedBox(width: 2),
            Text('${chat.aiTaskCount}', style: TextStyle(fontSize: 10.5, color: scheme.primary, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(chat.timeLabel, style: TextStyle(fontSize: 10.5, color: context.tasklyMutedV62)),
          const SizedBox(height: 5),
          if (chat.unreadCount > 0)
            Container(
              constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                gradient: TasklyAiThemeV62.auroraHorizontal,
                borderRadius: BorderRadius.circular(99),
              ),
              alignment: Alignment.center,
              child: Text(
                chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
