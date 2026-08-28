import 'package:flutter/material.dart';

import 'ai_gradient_shell_v61.dart';

class NewChatContactV61 {
  const NewChatContactV61({
    required this.id,
    required this.name,
    this.subtitle,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? avatarUrl;
}

/// New Chat intentionally has Create Group / Join Group at the top and NO group list.
class NewChatHubV61 extends StatefulWidget {
  const NewChatHubV61({
    super.key,
    required this.contacts,
    required this.onOpenContact,
    required this.onCreateGroup,
    required this.onJoinGroup,
  });

  final List<NewChatContactV61> contacts;
  final ValueChanged<NewChatContactV61> onOpenContact;
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;

  @override
  State<NewChatHubV61> createState() => _NewChatHubV61State();
}

class _NewChatHubV61State extends State<NewChatHubV61> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase().trim();
    final contacts = query.isEmpty
        ? widget.contacts
        : widget.contacts.where((contact) {
            return contact.name.toLowerCase().contains(query) ||
                (contact.subtitle ?? '').toLowerCase().contains(query);
          }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: AiGradientShellV61(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search people',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.group_add_rounded,
                    title: 'Create group',
                    subtitle: 'Start a new group',
                    onTap: widget.onCreateGroup,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Join group',
                    subtitle: 'Use code or QR',
                    onTap: widget.onJoinGroup,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text('People', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('No matching people.')),
              )
            else
              ...contacts.map(
                (contact) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: CircleAvatar(
                    foregroundImage: (contact.avatarUrl ?? '').isNotEmpty
                        ? NetworkImage(contact.avatarUrl!)
                        : null,
                    child: Text(contact.name.isEmpty ? '?' : contact.name.characters.first.toUpperCase()),
                  ),
                  title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: (contact.subtitle ?? '').isEmpty ? null : Text(contact.subtitle!),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => widget.onOpenContact(contact),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
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
      color: scheme.surface.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(height: 13),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
