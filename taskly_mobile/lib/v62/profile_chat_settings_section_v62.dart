import 'package:flutter/material.dart';

import 'ai_universe_shell_v62.dart';

/// Profile/Settings section for Taskly v6.2.
/// There is intentionally no Create Group and no Groups List here.
class ProfileChatSettingsSectionV62 extends StatelessWidget {
  const ProfileChatSettingsSectionV62({
    super.key,
    required this.onOpenChatBackup,
    this.onOpenPrivacy,
    this.onOpenAppearance,
    this.onOpenLinkedDevices,
  });

  final VoidCallback onOpenChatBackup;
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenAppearance;
  final VoidCallback? onOpenLinkedDevices;

  @override
  Widget build(BuildContext context) {
    return AiGlassCardV62(
      padding: EdgeInsets.zero,
      radius: 22,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: const Text('Chat backup'),
            subtitle: const Text('Encrypted Google Drive backup & restore'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenChatBackup,
          ),
          if (onOpenLinkedDevices != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: const Text('Devices'),
              subtitle: const Text('Primary phone and linked sessions'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onOpenLinkedDevices,
            ),
          ],
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
              subtitle: const Text('AI light & dark experience'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onOpenAppearance,
            ),
          ],
        ],
      ),
    );
  }
}
