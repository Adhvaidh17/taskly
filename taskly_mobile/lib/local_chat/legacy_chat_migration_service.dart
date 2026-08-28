import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'local_chat_database.dart';

typedef LegacyConversationFetcher =
    Future<List<Map<String, dynamic>>> Function();
typedef LegacyMessagePageFetcher =
    Future<List<Map<String, dynamic>>> Function(
  int channelId,
  int? beforeId,
  int limit,
);
typedef LegacyAttachmentFetcher = Future<Uint8List?> Function(String? bucket, String? path);
typedef LegacyAttachmentWriter = Future<String> Function({
  required int channelId,
  required String originalName,
  required List<int> bytes,
});

class _AttachmentMigration {
  const _AttachmentMigration(this.path, this.failed);
  final String? path;
  final bool failed;
}

class LegacyChatMigrationReport {
  const LegacyChatMigrationReport({
    required this.conversations,
    required this.messages,
    required this.alreadyCompleted,
    required this.failedAttachments,
  });

  final int conversations;
  final int messages;
  final bool alreadyCompleted;
  final int failedAttachments;
}

class LegacyChatMigrationService {
  LegacyChatMigrationService({
    required this.database,
    required this.fetchConversations,
    required this.fetchMessages,
    this.fetchAttachment,
    this.writeAttachment,
  });

  final LocalChatDatabase database;
  final LegacyConversationFetcher fetchConversations;
  final LegacyMessagePageFetcher fetchMessages;
  final LegacyAttachmentFetcher? fetchAttachment;
  final LegacyAttachmentWriter? writeAttachment;

  static const _uuid = Uuid();

  Future<LegacyChatMigrationReport> run() async {
    if (await database.migrationState('legacy_chat_v60') == 'complete') {
      return const LegacyChatMigrationReport(
        conversations: 0,
        messages: 0,
        alreadyCompleted: true,
        failedAttachments: 0,
      );
    }

    final conversations = await fetchConversations();
    var migratedMessages = 0;
    var failedAttachments = 0;

    for (final conversation in conversations) {
      final channelId = _int(conversation['channel_id'] ?? conversation['id']);
      final workspaceId = _int(conversation['workspace_id']);
      if (channelId == null || workspaceId == null) continue;

      await database.upsertConversation(
        channelId: channelId,
        workspaceId: workspaceId,
        title: conversation['title'] as String? ??
            conversation['name'] as String? ??
            '',
        kind: conversation['kind'] as String? ?? 'direct',
        avatarUrl: conversation['avatar_url'] as String?,
      );

      int? before;
      while (true) {
        final page = await fetchMessages(channelId, before, 200);
        if (page.isEmpty) break;

        for (final row in page) {
          final legacyId = _int(row['id']);
          final migratedAttachment = await _migrateAttachment(channelId, row);
          if (migratedAttachment.failed) failedAttachments++;
          final sender = row['sender'] is Map
              ? Map<String, dynamic>.from(row['sender'] as Map)
              : <String, dynamic>{};

          await database.insertMessage(
            clientMessageId: row['client_message_id'] as String? ??
                'legacy-${legacyId ?? _uuid.v4()}',
            legacyServerId: legacyId,
            workspaceId: workspaceId,
            channelId: channelId,
            senderProfileId: _int(
              sender['id'] ?? row['sender_profile_id'],
            ),
            senderName: sender['name'] as String? ??
                row['sender_name'] as String? ??
                '',
            senderEmail: sender['email'] as String?,
            senderPhone: sender['phone'] as String?,
            senderAvatarUrl: sender['avatar_url'] as String?,
            body: row['body'] as String? ?? '',
            type: row['type'] as String? ?? 'text',
            createdAt: DateTime.tryParse(
                  row['created_at'] as String? ?? '',
                ) ??
                DateTime.now().toUtc(),
            editedAt: DateTime.tryParse(
              row['edited_at'] as String? ?? '',
            ),
            attachmentPath: migratedAttachment.path,
            attachmentName: row['attachment_name'] as String?,
            attachmentMimeType: row['attachment_mime_type'] as String?,
            attachmentSizeBytes: _int(row['attachment_size_bytes']),
            pinned: row['is_pinned'] == true,
            deliveryState: 'migrated',
            metadata: const {
              'migrated_from_legacy_server': true,
            },
          );
          migratedMessages++;
        }

        final ids = page.map((e) => _int(e['id'])).whereType<int>().toList();
        if (ids.isEmpty || page.length < 200) break;
        before = ids.reduce((a, b) => a < b ? a : b);
      }
    }

    await database.cleanupMissingAttachments();
    if (failedAttachments == 0) {
      await database.putMigrationState('legacy_chat_v60', 'complete');
    }
    await database.putMigrationState(
      'legacy_chat_v60_count',
      jsonEncode({
        'conversations': conversations.length,
        'messages': migratedMessages,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'failed_attachments': failedAttachments,
      }),
    );

    return LegacyChatMigrationReport(
      conversations: conversations.length,
      messages: migratedMessages,
      alreadyCompleted: false,
      failedAttachments: failedAttachments,
    );
  }

  Future<_AttachmentMigration> _migrateAttachment(
    int channelId,
    Map<String, dynamic> row,
  ) async {
    final local = (row['local_attachment_path'] as String?) ??
        (row['attachment_local_path'] as String?);
    if (local != null && local.isNotEmpty && await File(local).exists()) {
      return _AttachmentMigration(local, false);
    }
    final bucket = row['attachment_bucket'] as String?;
    final path = row['attachment_path'] as String?;
    if ((bucket == null || bucket.isEmpty) && (path == null || path.isEmpty)) {
      return _AttachmentMigration(null, false);
    }
    if (fetchAttachment == null || writeAttachment == null) {
      return _AttachmentMigration(null, true);
    }
    final bytes = await fetchAttachment!(bucket, path);
    if (bytes == null || bytes.isEmpty) return _AttachmentMigration(null, true);
    final name = (row['attachment_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return _AttachmentMigration(null, true);
    try {
      final localPath = await writeAttachment!(
        channelId: channelId,
        originalName: name,
        bytes: bytes,
      );
      return _AttachmentMigration(localPath, false);
    } catch (_) {
      return _AttachmentMigration(null, true);
    }
  }

  int? _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}
