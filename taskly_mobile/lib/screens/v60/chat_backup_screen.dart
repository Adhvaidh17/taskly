import 'package:flutter/material.dart';

import '../../backup/backup_key_service.dart';
import '../../backup/chat_backup_service.dart';
import '../../backup/google_drive_backup_service.dart';
import '../../local_chat/local_chat_database.dart';

class ChatBackupScreen extends StatefulWidget {
  const ChatBackupScreen({
    super.key,
    required this.authUserId,
    required this.backup,
    required this.drive,
    required this.keys,
    required this.database,
  });

  final String authUserId;
  final ChatBackupService backup;
  final GoogleDriveBackupService drive;
  final BackupKeyService keys;
  final LocalChatDatabase database;

  @override
  State<ChatBackupScreen> createState() => _ChatBackupScreenState();
}

class _ChatBackupScreenState extends State<ChatBackupScreen> {
  bool _loading = true;
  bool _backingUp = false;
  bool _includeVideos = false;
  String _frequency = 'weekly';
  String? _lastBackupAt;
  DriveBackupMetadata? _driveBackup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final include = await widget.database.getSetting('backup_include_videos');
    final frequency = await widget.database.getSetting('backup_frequency');
    final lastAt = await widget.database.getSetting('backup_last_at');

    DriveBackupMetadata? cloud;
    try {
      cloud = await widget.drive.findBackup(interactive: false);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _includeVideos = include == '1';
      _frequency = frequency ?? 'weekly';
      _lastBackupAt = lastAt;
      _driveBackup = cloud;
      _loading = false;
    });
  }

  Future<void> _runBackup() async {
    setState(() => _backingUp = true);
    try {
      final result = await widget.backup.backUpNow(
        includeVideos: _includeVideos,
      );
      if (!mounted) return;
      setState(() {
        _lastBackupAt = result.createdAt.toIso8601String();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encrypted chat backup completed.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _showRecoveryKey() async {
    final key = await widget.keys.ensureRecoveryKey(widget.authUserId);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '64-digit backup key',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep this somewhere safe. Taskly cannot restore this '
                'end-to-end encrypted backup without it.',
              ),
              const SizedBox(height: 18),
              SelectableText(
                widget.keys.grouped(key),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateLabel(String? iso) {
    if (iso == null) return 'Never';
    final value = DateTime.tryParse(iso)?.toLocal();
    if (value == null) return 'Never';
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}  '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat backup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_done_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Google Drive backup',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.drive.currentAccount?.email ??
                                        'Connect your Google account',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _InfoRow(
                          label: 'Last backup',
                          value: _dateLabel(
                            _driveBackup?.modifiedAt.toIso8601String() ??
                                _lastBackupAt,
                          ),
                        ),
                        _InfoRow(
                          label: 'Backup size',
                          value: _driveBackup == null
                              ? '—'
                              : _size(_driveBackup!.sizeBytes),
                        ),
                        if (_driveBackup?.messageCount != null)
                          _InfoRow(
                            label: 'Messages',
                            value: '${_driveBackup!.messageCount}',
                          ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _backingUp ? null : _runBackup,
                          icon: _backingUp
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.backup_rounded),
                          label: Text(
                            _backingUp ? 'Backing up…' : 'Back up now',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.schedule_rounded),
                        title: const Text('Automatic backup'),
                        trailing: DropdownButton<String>(
                          value: _frequency,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(
                              value: 'never',
                              child: Text('Never'),
                            ),
                            DropdownMenuItem(
                              value: 'daily',
                              child: Text('Daily'),
                            ),
                            DropdownMenuItem(
                              value: 'weekly',
                              child: Text('Weekly'),
                            ),
                            DropdownMenuItem(
                              value: 'monthly',
                              child: Text('Monthly'),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _frequency = value);
                            await widget.database.putSetting(
                              'backup_frequency',
                              value,
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.video_library_rounded),
                        title: const Text('Include videos'),
                        subtitle: const Text(
                          'Videos can make the backup much larger.',
                        ),
                        value: _includeVideos,
                        onChanged: (value) async {
                          setState(() => _includeVideos = value);
                          await widget.database.putSetting(
                            'backup_include_videos',
                            value ? '1' : '0',
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_rounded),
                    title: const Text('End-to-end encrypted backup'),
                    subtitle: const Text(
                      'Your backup is encrypted before it leaves this phone.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _showRecoveryKey,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 14, 12, 0),
                  child: Text(
                    'Taskly stores chat history on your devices. Google Drive '
                    'holds only your encrypted backup; Taskly does not use '
                    'Supabase as permanent chat history.',
                    style: TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
