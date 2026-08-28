import 'package:flutter/material.dart';

import '../../backup/backup_key_service.dart';
import '../../backup/chat_backup_service.dart';
import '../../backup/google_drive_backup_service.dart';
import '../../backup/local_transfer_service.dart';
import '../../local_chat/local_chat_runtime.dart';
import '../../widgets/v60/ai_gradient_background.dart';
import 'transfer_chats_screen.dart';

class RestoreOrTransferScreen extends StatefulWidget {
  const RestoreOrTransferScreen({
    super.key,
    required this.authUserId,
    required this.backup,
    required this.drive,
    required this.keys,
    required this.transfer,
    required this.onContinue,
  });

  final String authUserId;
  final ChatBackupService backup;
  final GoogleDriveBackupService drive;
  final BackupKeyService keys;
  final LocalTransferService transfer;
  final Future<void> Function() onContinue;

  @override
  State<RestoreOrTransferScreen> createState() =>
      _RestoreOrTransferScreenState();
}

class _RestoreOrTransferScreenState extends State<RestoreOrTransferScreen> {
  bool _checking = true;
  bool _working = false;
  DriveBackupMetadata? _cloud;
  Object? _checkError;

  @override
  void initState() {
    super.initState();
    _checkCloud();
  }

  Future<void> _checkCloud() async {
    try {
      final result = await widget.drive.findBackup(interactive: false);
      if (!mounted) return;
      setState(() {
        _cloud = result;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkError = error;
        _checking = false;
      });
    }
  }

  Future<void> _restoreDrive() async {
    final interactiveBackup =
        await widget.drive.findBackup(interactive: true);
    if (interactiveBackup == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Taskly backup found in this account.')),
      );
      return;
    }

    final key = await _askRecoveryKey();
    if (key == null) return;

    setState(() => _working = true);
    try {
      await widget.backup.restoreFromDrive(recoveryKey: key);
      await widget.keys.setRecoveryKey(widget.authUserId, key);
      await widget.onContinue();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not restore the backup. Check the Google account and '
            '64-digit key. $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _askRecoveryKey() async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            16,
            22,
            22 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your 64-digit backup key',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'This key unlocks the end-to-end encrypted backup. '
                'Taskly does not have a copy of it.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 79,
                decoration: const InputDecoration(
                  hintText: '64-digit key',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              AiGradientButton(
                label: 'Restore backup',
                icon: Icons.restore_rounded,
                onPressed: () {
                  final key =
                      controller.text.replaceAll(RegExp(r'\s+'), '');
                  if (!RegExp(r'^\d{64}$').hasMatch(key)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter all 64 digits.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, key);
                },
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _transferOldPhone() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransferChatsReceiveScreen(
          transfer: widget.transfer,
          onRestored: () async {
            if (!mounted) return;
            Navigator.of(context).pop();
            await widget.onContinue();
          },
        ),
      ),
    );
  }

  Future<void> _skip() async {
    await LocalChatRuntime.instance.skipRestoreGate();
    await widget.onContinue();
  }

  String _backupLabel() {
    final cloud = _cloud;
    if (cloud == null) return 'Sign in to Google and look for your backup.';
    final date = cloud.modifiedAt.toLocal();
    final mb = cloud.sizeBytes / 1024 / 1024;
    return 'Backup found · '
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year} · '
        '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AiGradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF7C3CFF),
                            Color(0xFFD64EFF),
                            Color(0xFF4C6FFF),
                          ],
                        ),
                      ),
                      child: const Icon(
                        Icons.restore_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Restore your chats',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tasks are already synced to your Taskly account. '
                      'Your private chat history comes from your encrypted '
                      'backup or your old phone.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    _RestoreOption(
                      icon: Icons.cloud_rounded,
                      title: 'Restore from Google Drive',
                      subtitle: _checking
                          ? 'Looking for a backup…'
                          : _backupLabel(),
                      trailing: _checking
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: _working || _checking ? null : _restoreDrive,
                    ),
                    const SizedBox(height: 12),
                    _RestoreOption(
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'Transfer from old phone',
                      subtitle:
                          'Move chats directly over the same Wi-Fi network.',
                      onTap: _working ? null : _transferOldPhone,
                    ),
                    if (_checkError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Google backup was not checked silently. You can still '
                        'tap Restore from Google Drive to sign in.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 22),
                    TextButton(
                      onPressed: _working ? null : _skip,
                      child: const Text('Skip restore'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'If you skip, this phone starts with no old chat history. '
                      'Your Taskly tasks are unaffected.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestoreOption extends StatelessWidget {
  const _RestoreOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
