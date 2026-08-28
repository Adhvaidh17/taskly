import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../providers/chat_provider.dart';
import '../providers/workspace_provider.dart';
import '../v62/ai_chat_list_shell_v62.dart';
import '../v62/new_chat_hub_v62.dart';
import 'chat_room_screen.dart';
import 'contacts_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<ChatProvider>();
    final chats = provider.conversations
        .map(
          (conversation) => ChatPreviewV62(
            id: '${conversation.channelId}',
            title: conversation.name,
            preview: conversation.lastMessage ??
                (conversation.isSelfChat
                    ? 'Your private Taskly space'
                    : conversation.isGroup
                        ? 'Group conversation'
                        : 'Start a private conversation'),
            timeLabel: conversation.lastMessageAt == null
                ? ''
                : DateUtils.isSameDay(
                        conversation.lastMessageAt!, DateTime.now())
                    ? DateFormat('h:mm a')
                        .format(conversation.lastMessageAt!)
                    : DateFormat('dd/MM').format(conversation.lastMessageAt!),
            avatarUrl: conversation.avatarUrl,
            unreadCount: conversation.unreadCount,
            isMuted: conversation.isMuted,
          ),
        )
        .toList(growable: false);

    return AiChatListShellV62(
      chats: chats,
      onOpenChat: (chat) {
        final conversation = provider.conversations
            .where((item) => '${item.channelId}' == chat.id)
            .firstOrNull;
        if (conversation != null) _openConversation(context, conversation);
      },
      onNewChat: () => _openNewChatHub(context),
      onMore: () => _showChatOptions(context),
    );
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ContactsScreen()),
    );
    if (context.mounted) await context.read<ChatProvider>().loadConversations();
  }

  Future<void> _openConversation(
    BuildContext context,
    ConversationItem conversation,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: conversation)),
    );
    if (context.mounted) await context.read<ChatProvider>().loadConversations();
  }

  Future<void> _showChatOptions(BuildContext context) async {
    final provider = context.read<ChatProvider>();
    final conversation = provider.conversations.isEmpty
        ? null
        : await showModalBottomSheet<ConversationItem>(
            context: context,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: provider.conversations
                    .map(
                      (item) => ListTile(
                        leading: const Icon(Icons.tune_rounded),
                        title: Text(item.name),
                        subtitle: Text(item.isMuted ? 'Muted' : 'Notifications on'),
                        onTap: () => Navigator.pop(sheet, item),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
    if (conversation == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: conversation)),
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
    await context.read<WorkspaceProvider>().createGroup(name.text, description.text);
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
    await context.read<WorkspaceProvider>().joinGroup(code.text);
    if (context.mounted) await context.read<ChatProvider>().loadConversations();
  }
}
