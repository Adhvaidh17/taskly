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

class _ChatsScreenState extends State<ChatsScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<ChatProvider>();
    final items = provider.conversations;

    return AiChatListShellV62(
      child: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Chats',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'New chat',
                      onPressed: () => _openNewChatHub(context),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                    IconButton(
                      tooltip: 'Chat options',
                      onPressed: () => _showChatOptions(context),
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Your chats will appear here.'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final chat = items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: AiChatListItemV62(
                        title: chat.name,
                        preview: chat.lastMessage ??
                            (chat.isGroup ? 'Group conversation' : 'Start a private conversation'),
                        timeLabel: _timeLabel(chat.lastMessageAt),
                        avatar: _Avatar(chat: chat),
                        unreadCount: chat.unreadCount,
                        isMuted: chat.isMuted,
                        onTap: () => _openConversation(context, chat),
                      ),
                    );
                  },
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
    return DateUtils.isSameDay(local, DateTime.now())
        ? DateFormat('h:mm a').format(local)
        : DateFormat('dd/MM').format(local);
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
    if (context.mounted) await context.read<ChatProvider>().loadConversations();
  }

  Future<void> _openConversation(BuildContext context, ConversationItem conversation) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: conversation)));
    if (context.mounted) await context.read<ChatProvider>().loadConversations();
  }

  Future<void> _showChatOptions(BuildContext context) async {
    final provider = context.read<ChatProvider>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: provider.conversations.map((item) => ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: Text(item.name),
            subtitle: Text(item.isMuted ? 'Muted' : 'Notifications on'),
            onTap: () => Navigator.pop(sheet),
          )).toList(),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.chat});
  final ConversationItem chat;

  @override
  Widget build(BuildContext context) {
    final image = chat.avatarUrl;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
        ),
      ),
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
