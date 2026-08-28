import 'package:flutter/material.dart';

/// Drop this into Profile/Settings. It intentionally contains NO group list and
/// NO Create Group action. Group creation/joining lives in New Chat in v6.1.
class ProfilePrivacySectionV61 extends StatelessWidget {
  const ProfilePrivacySectionV61({
    super.key,
    required this.onOpenChatBackup,
    this.onOpenPrivacy,
    this.onOpenAppearance,
  });

  final VoidCallback onOpenChatBackup;
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenAppearance;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: const Text('Chat backup'),
            subtitle: const Text('Encrypted Google Drive backup & transfer'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenChatBackup,
          ),
          if (onOpenPrivacy != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onOpenPrivacy,
            ),
          ],
          if (onOpenAppearance != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Appearance'),
              subtitle: const Text('AI light / dark experience'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onOpenAppearance,
            ),
          ],
        ],
      ),
    );
  }
}
