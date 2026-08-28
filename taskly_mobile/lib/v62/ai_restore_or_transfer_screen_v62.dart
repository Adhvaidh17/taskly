import 'package:flutter/material.dart';

import 'ai_universe_shell_v62.dart';
import 'taskly_ai_theme_v62.dart';

/// Setup-only screen shown after a verified login becomes the new primary phone.
/// It is intentionally not reachable as a normal in-app login path.
class AiRestoreOrTransferScreenV62 extends StatefulWidget {
  const AiRestoreOrTransferScreenV62({
    super.key,
    required this.onTransferFromOldPhone,
    required this.onRestoreGoogleDrive,
    required this.onStartWithoutHistory,
    this.backupFound = false,
    this.lastBackupLabel,
    this.backupSizeLabel,
    this.googleAccountLabel,
    this.oldPhoneAvailable = true,
  });

  final Future<void> Function() onTransferFromOldPhone;
  final Future<void> Function() onRestoreGoogleDrive;
  final Future<void> Function() onStartWithoutHistory;
  final bool backupFound;
  final String? lastBackupLabel;
  final String? backupSizeLabel;
  final String? googleAccountLabel;
  final bool oldPhoneAvailable;

  @override
  State<AiRestoreOrTransferScreenV62> createState() =>
      _AiRestoreOrTransferScreenV62State();
}

class _AiRestoreOrTransferScreenV62State
    extends State<AiRestoreOrTransferScreenV62> {
  String? _working;

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_working != null) return;
    setState(() => _working = id);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AiUniverseShellV62(
        intensity: .8,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: Hero(
                        tag: 'taskly-intelligence-orb',
                        child: TasklyIntelligenceOrbV62(size: 92),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Bring your chats\nto this phone',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 35),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Your tasks are already synced. Chat history is private and must be transferred from your old phone or restored from your encrypted backup.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: context.tasklyMutedV62,
                          ),
                    ),
                    const SizedBox(height: 24),
                    if (widget.oldPhoneAvailable)
                      _MoveOptionV62(
                        icon: Icons.qr_code_2_rounded,
                        title: 'Transfer from old phone',
                        subtitle: 'Direct device-to-device transfer',
                        badge: 'Recommended',
                        loading: _working == 'transfer',
                        onTap: _working == null
                            ? () => _run('transfer', widget.onTransferFromOldPhone)
                            : null,
                      ),
                    if (widget.oldPhoneAvailable) const SizedBox(height: 12),
                    _MoveOptionV62(
                      icon: Icons.cloud_done_outlined,
                      title: widget.backupFound
                          ? 'Restore from Google Drive'
                          : 'Check Google Drive backup',
                      subtitle: _backupSubtitle(),
                      loading: _working == 'drive',
                      onTap: _working == null
                          ? () => _run('drive', widget.onRestoreGoogleDrive)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _MoveOptionV62(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Start without old chats',
                      subtitle: 'Continue with synced tasks and an empty local chat history',
                      loading: _working == 'skip',
                      onTap: _working == null
                          ? () => _confirmSkip(context)
                          : null,
                    ),
                    const SizedBox(height: 18),
                    AiGlassCardV62(
                      padding: const EdgeInsets.all(15),
                      radius: 20,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Taskly does not use its database as your permanent chat-history store. Google Drive backup is user-controlled and encrypted before upload.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
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

  String _backupSubtitle() {
    final pieces = <String>[];
    if ((widget.googleAccountLabel ?? '').trim().isNotEmpty) {
      pieces.add(widget.googleAccountLabel!.trim());
    }
    if ((widget.lastBackupLabel ?? '').trim().isNotEmpty) {
      pieces.add('Last backup ${widget.lastBackupLabel!.trim()}');
    }
    if ((widget.backupSizeLabel ?? '').trim().isNotEmpty) {
      pieces.add(widget.backupSizeLabel!.trim());
    }
    if (pieces.isEmpty) return 'Use your encrypted Taskly backup';
    return pieces.join(' · ');
  }

  Future<void> _confirmSkip(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue without restoring?'),
        content: const Text(
          'Old messages and media will not appear on this phone. Your synced tasks, account and group membership will still be available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run('skip', widget.onStartWithoutHistory);
    }
  }
}

class _MoveOptionV62 extends StatelessWidget {
  const _MoveOptionV62({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.loading,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AiGlassCardV62(
      padding: EdgeInsets.zero,
      radius: 23,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(23),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 15, 13, 15),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        TasklyAiThemeV62.violet.withValues(alpha: .20),
                        TasklyAiThemeV62.cyan.withValues(alpha: .11),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: scheme.primary),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: .11),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: context.tasklyMutedV62),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
