import 'package:flutter/material.dart';

import 'ai_universe_shell_v62.dart';
import 'taskly_ai_theme_v62.dart';

class NewChatContactV62 {
  const NewChatContactV62({
    required this.id,
    required this.name,
    this.subtitle,
    this.avatarUrl,
    this.isOnTaskly = true,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? avatarUrl;
  final bool isOnTaskly;
}

/// Optional compact launcher inspired by the first supplied reference.
/// It opens from the New Chat button and keeps group actions out of Profile.
Future<void> showTasklyNewChatSheetV62({
  required BuildContext context,
  required VoidCallback onNewChat,
  required VoidCallback onCreateGroup,
  required VoidCallback onJoinGroup,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: false,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LauncherRowV62(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'New chat',
            subtitle: 'Message a Taskly contact',
            onTap: () {
              Navigator.pop(sheetContext);
              onNewChat();
            },
          ),
          _LauncherRowV62(
            icon: Icons.group_add_outlined,
            title: 'Create group',
            subtitle: 'Start a private Taskly group',
            onTap: () {
              Navigator.pop(sheetContext);
              onCreateGroup();
            },
          ),
          _LauncherRowV62(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Join group',
            subtitle: 'Use an invite code or QR',
            onTap: () {
              Navigator.pop(sheetContext);
              onJoinGroup();
            },
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Full New Chat screen. It intentionally contains no group list.
class NewChatHubV62 extends StatefulWidget {
  const NewChatHubV62({
    super.key,
    required this.contacts,
    required this.onOpenContact,
    required this.onCreateGroup,
    required this.onJoinGroup,
    this.onInviteContact,
  });

  final List<NewChatContactV62> contacts;
  final ValueChanged<NewChatContactV62> onOpenContact;
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;
  final ValueChanged<NewChatContactV62>? onInviteContact;

  @override
  State<NewChatHubV62> createState() => _NewChatHubV62State();
}

class _NewChatHubV62State extends State<NewChatHubV62> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final contacts = widget.contacts.where((contact) {
      if (q.isEmpty) return true;
      return contact.name.toLowerCase().contains(q) ||
          (contact.subtitle ?? '').toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      body: AiUniverseShellV62(
        intensity: .38,
        showStars: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 12, 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text('New chat', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'Create group',
                      onPressed: widget.onCreateGroup,
                      icon: const Icon(Icons.group_add_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    TextField(
                      autofocus: false,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search people',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PrimaryActionV62(
                      icon: Icons.group_add_outlined,
                      title: 'Create group',
                      subtitle: 'Choose people and start a group',
                      onTap: widget.onCreateGroup,
                    ),
                    const SizedBox(height: 8),
                    _PrimaryActionV62(
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'Join group',
                      subtitle: 'Scan a QR or enter an invite code',
                      onTap: widget.onJoinGroup,
                    ),
                    const SizedBox(height: 22),
                    Text('People', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    if (contacts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 46),
                        child: Column(
                          children: [
                            Icon(Icons.search_off_rounded, size: 32, color: context.tasklyMutedV62),
                            const SizedBox(height: 10),
                            Text('No matching people', style: TextStyle(color: context.tasklyMutedV62)),
                          ],
                        ),
                      )
                    else
                      ...contacts.map((contact) => _ContactTileV62(
                            contact: contact,
                            onOpen: () => widget.onOpenContact(contact),
                            onInvite: widget.onInviteContact == null
                                ? null
                                : () => widget.onInviteContact!(contact),
                          )),
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

class _PrimaryActionV62 extends StatelessWidget {
  const _PrimaryActionV62({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: context.tasklyGlassV62,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      TasklyAiThemeV62.violet.withValues(alpha: .17),
                      TasklyAiThemeV62.cyan.withValues(alpha: .09),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, size: 21, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.tasklyMutedV62),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTileV62 extends StatelessWidget {
  const _ContactTileV62({required this.contact, required this.onOpen, this.onInvite});

  final NewChatContactV62 contact;
  final VoidCallback onOpen;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      leading: CircleAvatar(
        radius: 23,
        foregroundImage: (contact.avatarUrl ?? '').trim().isNotEmpty
            ? NetworkImage(contact.avatarUrl!)
            : null,
        child: Text(
          contact.name.isEmpty ? '?' : contact.name.characters.first.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(contact.name),
      subtitle: Text(
        contact.isOnTaskly
            ? ((contact.subtitle ?? '').trim().isEmpty ? 'On Taskly' : contact.subtitle!)
            : 'Invite to Taskly',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: contact.isOnTaskly
          ? const Icon(Icons.chevron_right_rounded)
          : TextButton(onPressed: onInvite, child: const Text('Invite')),
      onTap: contact.isOnTaskly ? onOpen : onInvite,
    );
  }
}

class _LauncherRowV62 extends StatelessWidget {
  const _LauncherRowV62({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 21),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
