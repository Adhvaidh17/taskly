import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/notifications/push_notification_service.dart';
import '../core/theme/app_theme.dart';
import '../providers/chat_provider.dart';
import '../providers/task_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          _SettingsSection(
            title: 'Appearance',
            children: [
              Consumer<ThemeProvider>(
                builder: (context, theme, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.settings_suggest_outlined),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {theme.mode},
                    onSelectionChanged: (value) => theme.setMode(value.first),
                  ),
                ),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Chats',
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Chat backup'),
                subtitle: const Text(
                  'Chats stay on this device. Google Drive backup and device switching are coming soon.',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Chat backup'),
                    content: const Text(
                      'Taskly currently keeps chat history and attachments on this phone. Encrypted Google Drive backup and WhatsApp-style device switching are prepared in the code but are not enabled yet. Tasks continue to sync securely.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Notifications',
            children: [
              Consumer<PushNotificationService>(
                builder: (context, push, _) => ListTile(
                  leading: Icon(
                    push.firebaseReady
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    color: push.firebaseReady
                        ? context.taskly.success
                        : context.taskly.warning,
                  ),
                  title: Text(
                    push.firebaseReady
                        ? 'Phone notifications ready'
                        : 'Phone notifications unavailable',
                  ),
                  subtitle: Text(
                    push.firebaseReady
                        ? 'Direct chats, groups and task activity can notify this device.'
                        : 'Firebase is not configured for this build.',
                  ),
                  trailing: push.firebaseReady
                      ? IconButton(
                          tooltip: 'Refresh registration',
                          onPressed: push.refreshRegistration,
                          icon: const Icon(Icons.refresh_rounded),
                        )
                      : null,
                ),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Storage and data',
            children: [
              const ListTile(
                leading: Icon(Icons.folder_outlined),
                title: Text('Local media'),
                subtitle: Text(
                  "Chat messages, cache and attachments are stored in Taskly's local encrypted storage on this device.",
                ),
              ),
              ListTile(
                leading: Icon(Icons.delete_sweep_outlined, color: context.taskly.danger),
                title: Text('Clear local Taskly data', style: TextStyle(color: context.taskly.danger)),
                subtitle: const Text('Deletes chat history, cache and media from this device. Synced tasks are not deleted.'),
                onTap: () => _clearLocalData(context),
              ),
            ],
          ),
          const _SettingsSection(
            title: 'Help',
            children: [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('About Taskly'),
                subtitle: Text('Taskly mobile · launch build'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _clearLocalData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear local data?'),
        content: const Text(
          'Chat messages, attachments and local chat cache will be permanently removed from this device. Synced tasks remain available in your Taskly account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<ChatProvider>().clearLocalData();
    if (!context.mounted) return;
    context.read<TaskProvider>().clearLocalAttachmentState();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local Taskly data cleared')),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );
  }
}
