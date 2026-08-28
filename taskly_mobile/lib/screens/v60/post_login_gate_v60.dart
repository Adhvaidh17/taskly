import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../backup/backup_key_service.dart';
import '../../backup/chat_backup_service.dart';
import '../../backup/google_drive_backup_service.dart';
import '../../backup/local_transfer_service.dart';
import '../../local_chat/local_chat_runtime.dart';
import 'ai_onboarding_screen.dart';
import 'restore_or_transfer_screen.dart';

/// Wrap your normal signed-in Taskly shell with this widget.
///
/// It gives a WhatsApp-like order:
/// account verified -> restore/transfer if this is a new phone -> tutorial
/// -> normal app. Tasks can sync normally because they remain server data.
class TasklyPostLoginGateV60 extends StatefulWidget {
  const TasklyPostLoginGateV60({
    super.key,
    required this.client,
    required this.child,
  });

  final SupabaseClient client;
  final Widget child;

  @override
  State<TasklyPostLoginGateV60> createState() => _TasklyPostLoginGateV60State();
}

enum _GateStage { loading, restore, onboarding, ready }

class _TasklyPostLoginGateV60State extends State<TasklyPostLoginGateV60> {
  _GateStage _stage = _GateStage.loading;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final user = widget.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _stage = _GateStage.ready);
        return;
      }

      final runtime = LocalChatRuntime.instance;
      final needsRestore = await runtime.needsRestoreGate(widget.client);
      if (!mounted) return;
      if (needsRestore) {
        setState(() => _stage = _GateStage.restore);
        return;
      }

      await runtime.initialize(widget.client);
      final tutorial =
          await runtime.database.getSetting('ai_onboarding_v60_complete');
      if (!mounted) return;
      setState(() {
        _stage = tutorial == '1'
            ? _GateStage.ready
            : _GateStage.onboarding;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _stage = _GateStage.ready;
      });
    }
  }

  Future<void> _afterRestoreOrSkip() async {
    await LocalChatRuntime.instance.initialize(widget.client);
    final tutorial = await LocalChatRuntime.instance.database
        .getSetting('ai_onboarding_v60_complete');
    if (!mounted) return;
    setState(() {
      _stage = tutorial == '1'
          ? _GateStage.ready
          : _GateStage.onboarding;
    });
  }

  Future<void> _finishOnboarding() async {
    await LocalChatRuntime.instance.database
        .putSetting('ai_onboarding_v60_complete', '1');
    if (mounted) setState(() => _stage = _GateStage.ready);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.client.auth.currentUser;
    if (user == null || _stage == _GateStage.ready) {
      return Stack(
        children: [
          widget.child,
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Private chat initialization warning: $_error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    if (_stage == _GateStage.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_stage == _GateStage.onboarding) {
      return AiOnboardingScreen(onComplete: _finishOnboarding);
    }

    final runtime = LocalChatRuntime.instance;
    final attachmentStore = runtime.attachments ??
        (throw StateError('Local attachment store is unavailable.'));
    final drive = GoogleDriveBackupService();
    final keys = BackupKeyService();
    final backup = ChatBackupService(
      authUserId: user.id,
      database: runtime.database,
      attachments: attachmentStore,
      keys: keys,
      drive: drive,
    );
    final transfer = LocalTransferService(
      authUserId: user.id,
      backup: backup,
      keys: keys,
    );

    return RestoreOrTransferScreen(
      authUserId: user.id,
      backup: backup,
      drive: drive,
      keys: keys,
      transfer: transfer,
      onContinue: _afterRestoreOrSkip,
    );
  }
}
