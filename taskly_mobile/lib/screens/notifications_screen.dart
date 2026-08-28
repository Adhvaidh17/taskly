import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/notification.dart';
import '../providers/chat_provider.dart';
import '../providers/notification_provider.dart';
import 'chat_room_screen.dart';
import 'task_detail_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(onPressed: provider.unreadCount == 0 ? null : provider.markAllRead, child: const Text('Read all')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.load,
        child: provider.loading && provider.items.isEmpty
            ? ListView(children: [const SizedBox(height: 240), const Center(child: CircularProgressIndicator())])
            : provider.items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 180),
                      Icon(Icons.notifications_none, size: 56, color: context.taskly.textFaint),
                      const SizedBox(height: 12),
                      Center(child: Text('No notifications yet', style: TextStyle(color: context.taskly.textMuted))),
                    ],
                  )
                : ListView.separated(
                    itemCount: provider.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => _NotificationTile(item: provider.items[index]),
                  ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final TasklyNotification item;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<NotificationProvider>();
    return ListTile(
      tileColor: item.isRead ? null : Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
      leading: CircleAvatar(
        child: Icon(_notificationIcon(item.type)),
      ),
      title: Text(item.title, style: TextStyle(fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w800)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((item.body ?? '').isNotEmpty) Text(item.body!, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(DateFormat('dd MMM, h:mm a').format(item.createdAt), style: TextStyle(fontSize: 11, color: context.taskly.textFaint)),
        ],
      ),
      trailing: item.isRead ? null : const CircleAvatar(radius: 4),
      onTap: () async {
        unawaited(provider.markRead(item));
        if (!context.mounted) return;
        if (item.taskId != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: item.taskId!)),
          );
        } else if (item.channelId != null) {
          final chat = context.read<ChatProvider>();
          if (chat.conversations.isEmpty) await chat.loadConversations();
          final matches = chat.conversations.where((c) => c.channelId == item.channelId);
          if (matches.isNotEmpty && context.mounted) {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: matches.first)));
          }
        }
      },
    );
  }
}

IconData _notificationIcon(String type) {
  if (type == 'message') return Icons.chat_bubble_outline_rounded;
  if (type == 'task_assigned') return Icons.assignment_ind_outlined;
  if (type == 'task_status') return Icons.task_alt_rounded;
  if (type == 'task_reassigned') return Icons.swap_horiz_rounded;
  if (type == 'task_updated') return Icons.edit_note_rounded;
  if (type == 'task_comment') return Icons.mode_comment_outlined;
  if (type == 'task_subtask') return Icons.checklist_rounded;
  if (type == 'task_attachment') return Icons.attach_file_rounded;
  return Icons.notifications_none_rounded;
}
