import 'dart:async';
import 'dart:typed_data';

import '../core/supabase/taskly_supabase.dart';
import '../local_chat/legacy_chat_migration_service.dart';
import '../local_chat/local_attachment_store.dart';
import '../local_chat/local_chat_database.dart';

/// Local-first migration coordinator.
///
/// It is deliberately retryable: offline devices keep their local state and
/// retry when the app gets connectivity again. The server transcript is never
/// purged by this client. Purging is a separate server-side operation after
/// every required device has acknowledged a verified local copy.
class ChatMigrationCoordinatorV63 {
  ChatMigrationCoordinatorV63({required this.backend});

  final TasklySupabase backend;
  final _db = LocalChatDatabase.instance;
  Timer? _retryTimer;
  bool _running = false;

  Future<void> start() async {
    await runOnce();
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(runOnce()),
    );
  }

  Future<void> runOnce() async {
    if (_running || backend.client.auth.currentUser == null) return;
    _running = true;
    try {
      await _db.openForUser(backend.client.auth.currentUser!.id);
      final attachments = LocalAttachmentStore(backend.client.auth.currentUser!.id);
      final migration = LegacyChatMigrationService(
        database: _db,
        fetchConversations: () async => backend.conversations(),
        fetchMessages: (channelId, beforeId, limit) => backend.messages(
          channelId,
          beforeId: beforeId,
          limit: limit,
        ),
        fetchAttachment: (bucket, path) async {
          if (bucket == null || path == null || bucket.isEmpty || path.isEmpty) {
            return null;
          }
          try {
            return await backend.downloadMessageAttachment(bucket: bucket, path: path);
          } catch (_) {
            return null;
          }
        },
        writeAttachment: ({
          required int channelId,
          required String originalName,
          required List<int> bytes,
        }) => attachments.writeIncoming(
          channelId: channelId,
          originalName: originalName,
          bytes: Uint8List.fromList(bytes),
        ),
      );
      final report = await migration.run();
      if (report.failedAttachments == 0) {
        final count = await _db.messageCount();
        await backend.client.rpc('taskly_ack_chat_local_migration_v63', params: {
          'p_message_count': count,
        });
      }
    } catch (_) {
      // Offline/auth/network failures are expected. The timer retries later.
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
