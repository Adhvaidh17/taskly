import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import '../providers/chat_provider.dart';
import 'chat_room_screen.dart';

class ContactInfoScreen extends StatelessWidget {
  const ContactInfoScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Contact info')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundImage: user.avatarUrl?.isNotEmpty == true
                  ? NetworkImage(user.avatarUrl!)
                  : null,
              child: user.avatarUrl?.isNotEmpty == true
                  ? null
                  : Text(user.initials, style: theme.textTheme.headlineMedium),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            user.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          if (user.about?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              user.about!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: user.id <= 0
                ? null
                : () async {
                    final conversation =
                        await context.read<ChatProvider>().startDirectChat(user);
                    if (!context.mounted) return;
                    await Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(conversation: conversation),
                      ),
                    );
                  },
            icon: const Icon(Icons.chat_bubble_rounded),
            label: const Text('Message'),
          ),
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                if (user.phone?.trim().isNotEmpty == true)
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(user.phone!),
                    subtitle: const Text('Mobile'),
                    onTap: () => launchUrl(Uri.parse('tel:${user.phone}')),
                  ),
                if (user.email.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.mail_outline_rounded),
                    title: Text(user.email),
                    subtitle: const Text('Email'),
                    onTap: () => launchUrl(Uri.parse('mailto:${user.email}')),
                  ),
                if (user.role?.trim().isNotEmpty == true)
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(user.role!),
                    subtitle: const Text('Group role'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
