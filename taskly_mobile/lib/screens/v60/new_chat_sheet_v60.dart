import 'package:flutter/material.dart';

class NewChatSheetV60 extends StatelessWidget {
  const NewChatSheetV60({
    super.key,
    required this.contacts,
    required this.onCreateGroup,
    required this.onJoinGroup,
    this.onNewContact,
  });

  final Widget contacts;
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;
  final VoidCallback? onNewContact;

  static Future<T?> show<T>(
    BuildContext context, {
    required Widget contacts,
    required VoidCallback onCreateGroup,
    required VoidCallback onJoinGroup,
    VoidCallback? onNewContact,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NewChatSheetV60(
        contacts: contacts,
        onCreateGroup: onCreateGroup,
        onJoinGroup: onJoinGroup,
        onNewContact: onNewContact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 8),
            child: Row(
              children: [
                Text(
                  'New chat',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          _ActionRow(
            icon: Icons.group_add_rounded,
            title: 'Create group',
            subtitle: 'Start a new group conversation',
            onTap: onCreateGroup,
          ),
          _ActionRow(
            icon: Icons.vpn_key_rounded,
            title: 'Join group',
            subtitle: 'Use a Taskly group code or invite',
            onTap: onJoinGroup,
          ),
          if (onNewContact != null)
            _ActionRow(
              icon: Icons.person_add_alt_1_rounded,
              title: 'New contact',
              subtitle: 'Add a person before messaging',
              onTap: onNewContact!,
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Contacts',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          Expanded(child: contacts),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
