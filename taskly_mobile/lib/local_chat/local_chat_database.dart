import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../services/chat_cache_service.dart';

class LocalChatDatabase {
  LocalChatDatabase._();

  static final LocalChatDatabase instance = LocalChatDatabase._();

  Database? _db;
  String? _namespace;
  final ChatCacheService _chatCache = ChatCacheService();

  bool get isOpen => _db != null;
  String? get namespace => _namespace;

  Database get db {
    final value = _db;
    if (value == null) {
      throw StateError('LocalChatDatabase has not been opened.');
    }
    return value;
  }

  Future<void> openForUser(String authUserId) async {
    final safe = authUserId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (_db != null && _namespace == safe) return;

    await close();
    _namespace = safe;
    _chatCache.useNamespace(authUserId);

    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'taskly_local_chat', safe));
    await dir.create(recursive: true);
    final path = p.join(dir.path, 'taskly_chat.db');

    _db = await openDatabase(
      path,
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await database.execute('PRAGMA journal_mode = WAL');
        await database.execute('PRAGMA synchronous = NORMAL');
      },
      onOpen: (database) async {
        await database.execute('''
          CREATE TABLE IF NOT EXISTS local_outbox (
            client_message_id TEXT PRIMARY KEY,
            channel_id INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE local_conversations (
            channel_id INTEGER PRIMARY KEY,
            workspace_id INTEGER NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT 'direct',
            avatar_url TEXT,
            last_message TEXT,
            last_sender_name TEXT,
            last_message_at TEXT,
            unread_count INTEGER NOT NULL DEFAULT 0,
            muted INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0,
            wallpaper TEXT,
            disappearing_seconds INTEGER,
            chat_locked INTEGER NOT NULL DEFAULT 0,
            advanced_privacy INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE local_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_message_id TEXT NOT NULL UNIQUE,
            legacy_server_id INTEGER UNIQUE,
            workspace_id INTEGER NOT NULL,
            channel_id INTEGER NOT NULL,
            sender_profile_id INTEGER,
            sender_name TEXT NOT NULL DEFAULT '',
            sender_email TEXT,
            sender_phone TEXT,
            sender_avatar_url TEXT,
            body TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT 'text',
            created_at TEXT NOT NULL,
            edited_at TEXT,
            reply_to_client_id TEXT,
            forwarded_from_client_id TEXT,
            attachment_path TEXT,
            attachment_name TEXT,
            attachment_mime_type TEXT,
            attachment_size_bytes INTEGER,
            starred INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0,
            delivery_state TEXT NOT NULL DEFAULT 'sent',
            reactions_json TEXT NOT NULL DEFAULT '{}',
            metadata_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(channel_id) REFERENCES local_conversations(channel_id)
              ON DELETE CASCADE
          )
        ''');

        await database.execute(
          'CREATE INDEX local_messages_channel_time_idx '
          'ON local_messages(channel_id, created_at DESC)',
        );
        await database.execute(
          'CREATE INDEX local_messages_client_idx '
          'ON local_messages(client_message_id)',
        );
        await database.execute(
          'CREATE INDEX local_messages_attachment_idx '
          'ON local_messages(channel_id, attachment_mime_type)',
        );

        await database.execute('''
          CREATE TABLE local_task_suggestions (
            client_message_id TEXT PRIMARY KEY,
            channel_id INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            dismissed INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await database.execute('''
          CREATE TABLE local_settings (
            setting_key TEXT PRIMARY KEY,
            setting_value TEXT
          )
        ''');

        await database.execute('''
          CREATE TABLE migration_state (
            state_key TEXT PRIMARY KEY,
            state_value TEXT,
            updated_at TEXT NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE local_outbox (
            client_message_id TEXT PRIMARY KEY,
            channel_id INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<String> databasePath() async => db.path;

  Future<void> checkpoint() async {
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
  }

  Future<void> close() async {
    final current = _db;
    _db = null;
    if (current != null) await current.close();
  }

  Future<void> clearAllData() async {
    final currentPath = _db?.path;
    await close();
    if (currentPath != null) {
      final file = File(currentPath);
      if (await file.exists()) await file.delete();
      for (final suffix in ['-wal', '-shm']) {
        final extra = File('$currentPath$suffix');
        if (await extra.exists()) await extra.delete();
      }
    }
  }

  Future<bool> hasAnyMessages() async {
    final rows = await db.rawQuery('SELECT 1 FROM local_messages LIMIT 1');
    return rows.isNotEmpty;
  }

  Future<int> messageCount() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM local_messages');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> upsertConversation({
    required int channelId,
    required int workspaceId,
    required String title,
    String kind = 'direct',
    String? avatarUrl,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      '''
      INSERT INTO local_conversations(
        channel_id, workspace_id, title, kind, avatar_url, created_at, updated_at
      ) VALUES(?,?,?,?,?,?,?)
      ON CONFLICT(channel_id) DO UPDATE SET
        workspace_id=excluded.workspace_id,
        title=CASE WHEN excluded.title <> '' THEN excluded.title ELSE local_conversations.title END,
        kind=excluded.kind,
        avatar_url=COALESCE(excluded.avatar_url, local_conversations.avatar_url),
        updated_at=excluded.updated_at
      ''',
      [channelId, workspaceId, title, kind, avatarUrl, now, now],
    );
  }

  Future<void> touchConversation({
    required int channelId,
    required int workspaceId,
    required String preview,
    required String senderName,
    required DateTime at,
    String title = '',
    String kind = 'direct',
  }) async {
    await upsertConversation(
      channelId: channelId,
      workspaceId: workspaceId,
      title: title,
      kind: kind,
    );
    await db.update(
      'local_conversations',
      {
        'last_message': preview,
        'last_sender_name': senderName,
        'last_message_at': at.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
  }

  Future<List<Map<String, dynamic>>> conversations() {
    return db.query(
      'local_conversations',
      orderBy:
          'CASE WHEN last_message_at IS NULL THEN 1 ELSE 0 END, '
          'last_message_at DESC, updated_at DESC',
    );
  }

  Future<int> insertMessage({
    required String clientMessageId,
    int? legacyServerId,
    required int workspaceId,
    required int channelId,
    int? senderProfileId,
    required String senderName,
    String? senderEmail,
    String? senderPhone,
    String? senderAvatarUrl,
    required String body,
    String type = 'text',
    required DateTime createdAt,
    DateTime? editedAt,
    String? replyToClientId,
    String? forwardedFromClientId,
    String? attachmentPath,
    String? attachmentName,
    String? attachmentMimeType,
    int? attachmentSizeBytes,
    bool starred = false,
    bool pinned = false,
    String deliveryState = 'sent',
    Map<String, dynamic>? reactions,
    Map<String, dynamic>? metadata,
  }) async {
    await upsertConversation(
      channelId: channelId,
      workspaceId: workspaceId,
      title: '',
    );

    final values = <String, Object?>{
      'client_message_id': clientMessageId,
      'legacy_server_id': legacyServerId,
      'workspace_id': workspaceId,
      'channel_id': channelId,
      'sender_profile_id': senderProfileId,
      'sender_name': senderName,
      'sender_email': senderEmail,
      'sender_phone': senderPhone,
      'sender_avatar_url': senderAvatarUrl,
      'body': body,
      'type': type,
      'created_at': createdAt.toUtc().toIso8601String(),
      'edited_at': editedAt?.toUtc().toIso8601String(),
      'reply_to_client_id': replyToClientId,
      'forwarded_from_client_id': forwardedFromClientId,
      'attachment_path': attachmentPath,
      'attachment_name': attachmentName,
      'attachment_mime_type': attachmentMimeType,
      'attachment_size_bytes': attachmentSizeBytes,
      'starred': starred ? 1 : 0,
      'pinned': pinned ? 1 : 0,
      'delivery_state': deliveryState,
      'reactions_json': jsonEncode(reactions ?? const <String, dynamic>{}),
      'metadata_json': jsonEncode(metadata ?? const <String, dynamic>{}),
    };

    await db.insert(
      'local_messages',
      values,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final row = await db.query(
      'local_messages',
      columns: ['id'],
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
      limit: 1,
    );
    final id = (row.first['id'] as num).toInt();

    await touchConversation(
      channelId: channelId,
      workspaceId: workspaceId,
      preview: attachmentName != null && body.trim().isEmpty
          ? _previewForAttachment(attachmentMimeType, attachmentName)
          : body,
      senderName: senderName,
      at: createdAt,
    );
    return id;
  }

  Future<void> updateMessageText(
    String clientMessageId,
    String body, {
    DateTime? editedAt,
  }) async {
    await db.update(
      'local_messages',
      {
        'body': body,
        'edited_at': (editedAt ?? DateTime.now()).toUtc().toIso8601String(),
      },
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> setMessagePinned(String clientMessageId, bool pinned) async {
    await db.update(
      'local_messages',
      {'pinned': pinned ? 1 : 0},
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> setMessageStarred(String clientMessageId, bool starred) async {
    await db.update(
      'local_messages',
      {'starred': starred ? 1 : 0},
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> setMessageReactions(
    String clientMessageId,
    Map<String, dynamic> reactions,
  ) async {
    await db.update(
      'local_messages',
      {'reactions_json': jsonEncode(reactions)},
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<Map<String, dynamic>?> messageByLocalId(int localId) async {
    final rows = await db.query(
      'local_messages',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> messageByClientId(
    String clientMessageId,
  ) async {
    final rows = await db.query(
      'local_messages',
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> deleteMessage(String clientMessageId) async {
    await db.delete(
      'local_messages',
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> removeAttachment(String clientMessageId) async {
    final row = await messageByClientId(clientMessageId);
    if (row == null) return;

    final body = (row['body'] as String? ?? '').trim();
    final path = row['attachment_path'] as String?;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }

    if (body.isEmpty) {
      await deleteMessage(clientMessageId);
      return;
    }

    await db.update(
      'local_messages',
      {
        'attachment_path': null,
        'attachment_name': null,
        'attachment_mime_type': null,
        'attachment_size_bytes': null,
        'type': 'text',
      },
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<int> cleanupMissingAttachments() async {
    final rows = await db.query(
      'local_messages',
      columns: ['client_message_id', 'body', 'attachment_path'],
      where: 'attachment_path IS NOT NULL',
    );

    var changed = 0;
    for (final row in rows) {
      final path = row['attachment_path'] as String?;
      if (path == null || path.isEmpty || await File(path).exists()) continue;

      changed++;
      final clientId = row['client_message_id'] as String;
      final body = (row['body'] as String? ?? '').trim();
      if (body.isEmpty) {
        await deleteMessage(clientId);
      } else {
        await db.update(
          'local_messages',
          {
            'attachment_path': null,
            'attachment_name': null,
            'attachment_mime_type': null,
            'attachment_size_bytes': null,
            'type': 'text',
          },
          where: 'client_message_id = ?',
          whereArgs: [clientId],
        );
      }
    }
    return changed;
  }

  Future<List<Map<String, dynamic>>> messageRows(
    int channelId, {
    int limit = 80,
    int? beforeLocalId,
  }) async {
    // The .cache transcript is the hot path. SQLite remains the local index
    // and action/outbox store, but opening a chat must not wait for SQLite
    // reconstruction when the device already has its cached transcript.
    if (beforeLocalId == null) {
      final cached = await _chatCache.readMessages(channelId);
      if (cached.isNotEmpty) {
        final limited = cached.length <= limit
            ? cached
            : cached.sublist(cached.length - limit);
        return List<Map<String, dynamic>>.from(limited);
      }
    }

    final where = beforeLocalId == null
        ? 'channel_id = ?'
        : 'channel_id = ? AND id < ?';
    final args = beforeLocalId == null
        ? <Object?>[channelId]
        : <Object?>[channelId, beforeLocalId];

    final rows = await db.query(
      'local_messages',
      where: where,
      whereArgs: args,
      orderBy: 'id DESC',
      limit: limit,
    );

    final result = <Map<String, dynamic>>[];
    for (final row in rows.reversed) {
      final converted = _legacyCompatibleRow(row);
      final clientId = row['client_message_id']?.toString();
      if (clientId != null) {
        final suggestions = await db.query(
          'local_task_suggestions',
          where: 'client_message_id = ? AND dismissed = 0',
          whereArgs: [clientId],
          limit: 1,
        );
        if (suggestions.isNotEmpty) {
          try {
            final payload = jsonDecode(suggestions.first['payload_json'] as String);
            if (payload is Map) {
              converted['suggestion'] = {
                ...Map<String, dynamic>.from(payload),
                'id': -clientId.hashCode.abs(),
                'status': 'pending',
                'action_type': payload['action_type'] ?? 'create',
              };
            }
          } catch (_) {}
        }
      }
      result.add(converted);
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> mediaLinksDocs(
    int channelId, {
    String category = 'media',
    int limit = 100,
  }) {
    String where;
    switch (category) {
      case 'links':
        where =
            "channel_id = ? AND body LIKE '%http%' AND attachment_path IS NULL";
        break;
      case 'docs':
        where =
            "channel_id = ? AND attachment_path IS NOT NULL "
            "AND (attachment_mime_type IS NULL "
            "OR (attachment_mime_type NOT LIKE 'image/%' "
            "AND attachment_mime_type NOT LIKE 'video/%'))";
        break;
      default:
        where =
            "channel_id = ? AND attachment_path IS NOT NULL "
            "AND (attachment_mime_type LIKE 'image/%' "
            "OR attachment_mime_type LIKE 'video/%')";
    }

    return db.query(
      'local_messages',
      where: where,
      whereArgs: [channelId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> starredMessages(
    int channelId, {
    int limit = 100,
  }) {
    return db.query(
      'local_messages',
      where: 'channel_id = ? AND starred = 1',
      whereArgs: [channelId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> searchMessages(
    int channelId,
    String query, {
    int limit = 100,
  }) {
    return db.query(
      'local_messages',
      where: 'channel_id = ? AND body LIKE ?',
      whereArgs: [channelId, '%$query%'],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<void> clearChat(int channelId) async {
    final attachments = await db.query(
      'local_messages',
      columns: ['attachment_path'],
      where: 'channel_id = ? AND attachment_path IS NOT NULL',
      whereArgs: [channelId],
    );
    for (final row in attachments) {
      final path = row['attachment_path'] as String?;
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }

    await db.delete(
      'local_messages',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    await db.update(
      'local_conversations',
      {
        'last_message': null,
        'last_sender_name': null,
        'last_message_at': null,
        'unread_count': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    await _chatCache.clearChannel(channelId);
  }

  Future<void> deleteConversation(int channelId) async {
    await clearChat(channelId);
    await db.delete(
      'local_conversations',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
  }

  Future<void> setConversationPreference(
    int channelId, {
    bool? muted,
    bool? archived,
    String? wallpaper,
    int? disappearingSeconds,
    bool? chatLocked,
    bool? advancedPrivacy,
  }) async {
    final values = <String, Object?>{
      if (muted != null) 'muted': muted ? 1 : 0,
      if (archived != null) 'archived': archived ? 1 : 0,
      if (wallpaper != null) 'wallpaper': wallpaper,
      if (disappearingSeconds != null)
        'disappearing_seconds': disappearingSeconds,
      if (chatLocked != null) 'chat_locked': chatLocked ? 1 : 0,
      if (advancedPrivacy != null)
        'advanced_privacy': advancedPrivacy ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (values.length == 1) return;
    await db.update(
      'local_conversations',
      values,
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
  }

  Future<Map<String, dynamic>?> conversation(int channelId) async {
    final rows = await db.query(
      'local_conversations',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveTaskSuggestion(
    String clientMessageId,
    int channelId,
    Map<String, dynamic> payload,
  ) async {
    await db.insert(
      'local_task_suggestions',
      {
        'client_message_id': clientMessageId,
        'channel_id': channelId,
        'payload_json': jsonEncode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'dismissed': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> taskSuggestion(String clientMessageId) async {
    final rows = await db.query(
      'local_task_suggestions',
      where: 'client_message_id = ? AND dismissed = 0',
      whereArgs: [clientMessageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['payload_json'] as String)
        as Map<String, dynamic>;
  }

  Future<void> dismissTaskSuggestion(String clientMessageId) async {
    await db.update(
      'local_task_suggestions',
      {'dismissed': 1},
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> putSetting(String key, String? value) async {
    await db.insert(
      'local_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final rows = await db.query(
      'local_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value'] as String?;
  }

  Future<void> putMigrationState(String key, String value) async {
    await db.insert(
      'migration_state',
      {
        'state_key': key,
        'state_value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> migrationState(String key) async {
    final rows = await db.query(
      'migration_state',
      columns: ['state_value'],
      where: 'state_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['state_value'] as String?;
  }

  Future<void> resetForRestore() async {
    await db.transaction((txn) async {
      await txn.delete('local_task_suggestions');
      await txn.delete('local_messages');
      await txn.delete('local_conversations');
      await txn.delete('migration_state');
    });
  }

  Future<void> enqueueOutbox({
    required String clientMessageId,
    required int channelId,
    required String payloadJson,
  }) async {
    await db.insert(
      'local_outbox',
      {
        'client_message_id': clientMessageId,
        'channel_id': channelId,
        'payload_json': payloadJson,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> outbox() =>
      db.query('local_outbox', orderBy: 'created_at ASC');

  Future<void> removeOutbox(String clientMessageId) async {
    await db.delete(
      'local_outbox',
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Map<String, dynamic> _legacyCompatibleRow(Map<String, dynamic> row) {
    Map<String, dynamic> decodeMap(Object? raw) {
      if (raw is! String || raw.isEmpty) return <String, dynamic>{};
      final value = jsonDecode(raw);
      return value is Map<String, dynamic>
          ? value
          : <String, dynamic>{};
    }

    return <String, dynamic>{
      'id': row['id'],
      'client_message_id': row['client_message_id'],
      'workspace_id': row['workspace_id'],
      'channel_id': row['channel_id'],
      'body': row['body'],
      'type': row['type'],
      'created_at': row['created_at'],
      'edited_at': row['edited_at'],
      'is_pinned': (row['pinned'] as num? ?? 0).toInt() == 1,
      'is_starred': (row['starred'] as num? ?? 0).toInt() == 1,
      'attachment_path': row['attachment_path'],
      'attachment_name': row['attachment_name'],
      'attachment_mime_type': row['attachment_mime_type'],
      'attachment_size_bytes': row['attachment_size_bytes'],
      'delivery_state': row['delivery_state'],
      'reactions': decodeMap(row['reactions_json']),
      'metadata': decodeMap(row['metadata_json']),
      'sender': <String, dynamic>{
        'id': row['sender_profile_id'],
        'name': row['sender_name'],
        'email': row['sender_email'],
        'phone': row['sender_phone'],
        'avatar_url': row['sender_avatar_url'],
      },
      'reply_to': null,
      ..._decodeMetadata(row['metadata_json']),
    };
  }

  Map<String, dynamic> _decodeMetadata(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <String, dynamic>{};
    try {
      final value = jsonDecode(raw);
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    return const <String, dynamic>{};
  }

  String _previewForAttachment(String? mime, String name) {
    if (mime?.startsWith('image/') == true) return 'Photo';
    if (mime?.startsWith('video/') == true) return 'Video';
    if (mime?.startsWith('audio/') == true) return 'Audio';
    return name;
  }
}
