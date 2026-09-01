import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../local_chat/local_chat_database.dart';
import '../models/channel.dart';
import '../providers/chat_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/recovered_chat_cache_service.dart';
import '../v62/ai_chat_list_shell_v62.dart';
import '../v62/new_chat_hub_v62.dart';
import '../v62/taskly_ai_theme_v62.dart';
import 'chat_room_screen.dart';
import 'contacts_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with AutomaticKeepAliveClientMixin {
  final RecoveredChatCacheService _cache = RecoveredChatCacheService();
  List<ConversationItem> _cachedConversations = const [];
  final Map<int, _LatestLocalMessage> _latestLocalMessages = {};
  bool _cacheLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCachedConversations());
  }

  Future<void> _loadCachedConversations() async {
    if (!mounted) return;
    try {
      final cached = await _cache.readConversations();
      await _loadLatestLocalMessages();
      if (!mounted) return;
      setState(() {
        _cachedConversations = cached;
        _cacheLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _cacheLoaded = true);
    }
  }

  Future<void> _loadLatestLocalMessages() async {
    try {
      final db = LocalChatDatabase.instance;
      final rows = await db.db.rawQuery('''
        SELECT m.channel_id, m.body, m.sender_name, m.created_at,
               m.attachment_name, m.attachment_mime_type
        FROM local_messages m
        INNER JOIN (
          SELECT channel_id, MAX(created_at) AS latest_at
          FROM local_messages
          GROUP BY channel_id
        ) latest
          ON latest.channel_id = m.channel_id
         AND latest.latest_at = m.created_at
        ORDER BY m.created_at DESC, m.id DESC
      ''');
      _latestLocalMessages
        ..clear()
        ..addEntries(rows.map((row) {
          final channelId = (row['channel_id'] as num).toInt();
          return MapEntry(
            channelId,
            _LatestLocalMessage(
              body: row['body'] as String? ?? '',
              senderName: row['sender_name'] as String? ?? '',
              createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
              attachmentName: row['attachment_name'] as String?,
              attachmentMimeType: row['attachment_mime_type'] as String?,
            ),
          );
        }));
    } catch (_) {
      // Local chat may not be initialized yet. Provider/cache data remains usable.
    }
  }

  String _preview(_LatestLocalMessage latest) {
    if (latest.body.trim().isNotEmpty) return latest.body;
    final mime = latest.attachmentMimeType;
    if (mime?.startsWith('image/') == true) return 'Photo';
    if (mime?.startsWith('video/') == true) return 'Video';
    if (mime?.startsWith('audio/') == true) return 'Audio';
    return latest.attachmentName ?? '';
  }

  List<ConversationItem> _mergeItems(List<ConversationItem> serverOrLocal) {
    final byChannel = <int, ConversationItem>{};
    for (final item in _cachedConversations) {
      if (item.channelId > 0) byChannel[item.channelId] = item;
    }
    for (final item in serverOrLocal) {
      final cached = byChannel[item.channelId];
      if (cached == null) {
        byChannel[item.channelId] = item;
      } else {
        byChannel[item.channelId] = item.copyWith(
          lastMessage: item.lastMessage?.isNotEmpty == true ? item.lastMessage : cached.lastMessage,
          lastSenderName: item.lastSenderName?.isNotEmpty == true ? item.lastSenderName : cached.lastSenderName,
          lastMessageAt: item.lastMessageAt ?? cached.lastMessageAt,
          unreadCount: item.unreadCount > 0 ? item.unreadCount : cached.unreadCount,
          isMuted: item.isMuted || cached.isMuted,
          isArchived: item.isArchived || cached.isArchived,
        );
      }
    }

    final result = byChannel.values.map((item) {
      final latest = _latestLocalMessages[item.channelId];
      if (latest == null || latest.createdAt == null) return item;
      return item.copyWith(
        lastMessage: _preview(latest),
        lastSenderName: latest.senderName,
        lastMessageAt: latest.createdAt,
      );
    }).toList();

    // WhatsApp-style ordering: the conversation containing the newest
    // sent or received message is always first. Opening a chat never
    // changes this order; only an actual new message does.
    result.sort((a, b) {
      final at = a.lastMessageAt;
      final bt = b.lastMessageAt;
      if (at == null && bt == null) return a.name.compareTo(b.name);
      if (at == null) return 1;
      if (bt == null) return -1;
      final byTime = bt.compareTo(at);
      if (byTime != 0) return byTime;
      return a.name.compareTo(b.name);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<ChatProvider>();
    final items = _mergeItems(provider.conversations);

    return AiChatListShellV62(
      child: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Chats', style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    _GlassIconButton(icon: Icons.edit_rounded, onTap: () => _openNewChatHub(context), tooltip: 'New chat'),
                    const SizedBox(width: 8),
                    _GlassIconButton(icon: Icons.more_horiz_rounded, onTap: () => _showChatOptions(context), tooltip: 'Chat options'),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search chats',
                  ),
                  onChanged: (_) {},
                ),
              ),
            ),
            if (items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final chat = items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: AiChatListItemV62(
                        title: chat.name.isEmpty ? 'Conversation' : chat.name,
                        preview: chat.lastMessage ?? '',
                        timeLabel: _timeLabel(chat.lastMessageAt),
                        avatar: _Avatar(chat: chat),
                        unreadCount: chat.unreadCount,
                        isMuted: chat.isMuted,
                        isGroup: chat.isGroup,
                        onTap: () => _openConversation(context, chat),
                      ),
                    );
                  },
                ),
              )
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 20, 32, 100),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(shape: BoxShape.circle, gradient: TasklyAiThemeV62.aurora),
                          child: const Icon(Icons.forum_rounded, color: Colors.white, size: 32),
                        ),
                        const SizedBox(height: 18),
                        Text(_cacheLoaded ? 'Your chats will appear here.' : 'Loading your chats…', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Cached conversations stay available on this device.', textAlign: TextAlign.center, style: TextStyle(color: context.tasklyMutedV62)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return DateUtils.isSameDay(local, DateTime.now()) ? DateFormat('h:mm a').format(local) : DateFormat('dd/MM').format(local);
  }

  Future<void> _openNewChatHub(BuildContext context) async {
    await showTasklyNewChatSheetV62(
      context: context,
      onNewChat: () => _openContacts(context),
      onCreateGroup: () => _createGroup(context),
      onJoinGroup: () => _joinGroup(context),
    );
  }

  Future<void> _openContacts(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactsScreen()));
    if (context.mounted) {
      await context.read<ChatProvider>().loadConversations();
      await _loadCachedConversations();
    }
  }

  Future<void> _openConversation(BuildContext context, ConversationItem conversation) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: conversation)));
    if (context.mounted) {
      await context.read<ChatProvider>().loadConversations();
      await _loadCachedConversations();
    }
  }

  Future<void> _showChatOptions(BuildContext context) async {
    final provider = context.read<ChatProvider>();
    final items = _mergeItems(provider.conversations);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(28),
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: items.map((item) => ListTile(
                leading: _Avatar(chat: item, size: 40),
                title: Text(item.name),
                subtitle: Text(item.isMuted ? 'Muted' : item.isGroup ? 'Group' : 'Private chat'),
                onTap: () => Navigator.pop(sheet),
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createGroup(BuildContext context) async {
    final name = TextEditingController();
    final description = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Create a group'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Group name')),
          const SizedBox(height: 10),
          TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().length < 2 || !context.mounted) return;
    await context.read<WorkspaceProvider>().createGroup(name.text.trim(), description.text.trim());
    if (context.mounted) await context.read<ChatProvider>().loadConversations();
  }

  Future<void> _joinGroup(BuildContext context) async {
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Join a group'),
        content: TextField(controller: code, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Invite code')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Join')),
        ],
      ),
    );
    if (ok != true || code.text.trim().isEmpty || !context.mounted) return;
    await context.read<WorkspaceProvider>().joinGroup(code.text.trim());
    if (context.mounted) await context.read<ChatProvider>().loadConversations();
  }
}

class _LatestLocalMessage {
  const _LatestLocalMessage({
    required this.body,
    required this.senderName,
    required this.createdAt,
    required this.attachmentName,
    required this.attachmentMimeType,
  });

  final String body;
  final String senderName;
  final DateTime? createdAt;
  final String? attachmentName;
  final String? attachmentMimeType;
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: context.tasklyGlassV62,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(17), border: Border.all(color: context.tasklyBorderV62)),
              child: Icon(icon),
            ),
          ),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.chat, this.size = 54});
  final ConversationItem chat;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = chat.avatarUrl;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: TasklyAiThemeV62.aurora),
      padding: const EdgeInsets.all(2),
      child: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        backgroundImage: image == null || image.isEmpty ? null : NetworkImage(image),
        child: image == null || image.isEmpty
            ? Text(chat.name.trim().isEmpty ? '?' : chat.name.trim()[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))
            : null,
      ),
    );
  }
}
