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
  Database get db => _db ?? (throw StateError('LocalChatDatabase has not been opened.'));

  Future<void> openForUser(String authUserId) async {
    final safe = authUserId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (_db != null && _namespace == safe) return;
    await close();
    _namespace = safe;
    _chatCache.useNamespace(authUserId);
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'taskly_local_chat', safe));
    await dir.create(recursive: true);
    _db = await openDatabase(
      p.join(dir.path, 'taskly_chat.db'),
      version: 2,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await database.execute('PRAGMA journal_mode = WAL');
        await database.execute('PRAGMA synchronous = NORMAL');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute('ALTER TABLE local_conversations ADD COLUMN metadata_json TEXT NOT NULL DEFAULT \'{}\'');
        }
      },
      onOpen: (database) async {
        await database.execute('''CREATE TABLE IF NOT EXISTS local_outbox (
          client_message_id TEXT PRIMARY KEY, channel_id INTEGER NOT NULL,
          payload_json TEXT NOT NULL, created_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0)''');
      },
      onCreate: (database, version) async {
        await database.execute('''CREATE TABLE local_conversations (
          channel_id INTEGER PRIMARY KEY, workspace_id INTEGER NOT NULL,
          title TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL DEFAULT 'direct', avatar_url TEXT,
          last_message TEXT, last_sender_name TEXT, last_message_at TEXT,
          unread_count INTEGER NOT NULL DEFAULT 0, muted INTEGER NOT NULL DEFAULT 0,
          archived INTEGER NOT NULL DEFAULT 0, wallpaper TEXT, disappearing_seconds INTEGER,
          chat_locked INTEGER NOT NULL DEFAULT 0, advanced_privacy INTEGER NOT NULL DEFAULT 0,
          metadata_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
        await database.execute('''CREATE TABLE local_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT, client_message_id TEXT NOT NULL UNIQUE,
          legacy_server_id INTEGER UNIQUE, workspace_id INTEGER NOT NULL, channel_id INTEGER NOT NULL,
          sender_profile_id INTEGER, sender_name TEXT NOT NULL DEFAULT '', sender_email TEXT,
          sender_phone TEXT, sender_avatar_url TEXT, body TEXT NOT NULL DEFAULT '', type TEXT NOT NULL DEFAULT 'text',
          created_at TEXT NOT NULL, edited_at TEXT, reply_to_client_id TEXT, forwarded_from_client_id TEXT,
          attachment_path TEXT, attachment_name TEXT, attachment_mime_type TEXT, attachment_size_bytes INTEGER,
          starred INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0, delivery_state TEXT NOT NULL DEFAULT 'sent',
          reactions_json TEXT NOT NULL DEFAULT '{}', metadata_json TEXT NOT NULL DEFAULT '{}',
          FOREIGN KEY(channel_id) REFERENCES local_conversations(channel_id) ON DELETE CASCADE)''');
        await database.execute('CREATE INDEX local_messages_channel_time_idx ON local_messages(channel_id, created_at DESC)');
        await database.execute('CREATE INDEX local_messages_channel_id_idx ON local_messages(channel_id, id)');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _namespace = null;
  }

  Future<void> upsertConversation({
    required int channelId,
    required int workspaceId,
    required String title,
    String kind = 'direct',
    String? avatarUrl,
    Map<String, dynamic>? metadata,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final metadataJson = jsonEncode(metadata ?? const <String, dynamic>{});
    await db.rawInsert('''
      INSERT INTO local_conversations(channel_id, workspace_id, title, kind, avatar_url, metadata_json, created_at, updated_at)
      VALUES(?,?,?,?,?,?,?,?)
      ON CONFLICT(channel_id) DO UPDATE SET
        workspace_id=excluded.workspace_id,
        title=CASE WHEN excluded.title <> '' THEN excluded.title ELSE local_conversations.title END,
        kind=CASE WHEN excluded.kind <> '' THEN excluded.kind ELSE local_conversations.kind END,
        avatar_url=COALESCE(excluded.avatar_url, local_conversations.avatar_url),
        metadata_json=CASE WHEN excluded.metadata_json <> '{}' THEN excluded.metadata_json ELSE local_conversations.metadata_json END,
        updated_at=excluded.updated_at
    ''', [channelId, workspaceId, title, kind, avatarUrl, metadataJson, now, now]);
  }

  Future<void> touchConversation({
    required int channelId,
    required int workspaceId,
    required String preview,
    required String senderName,
    required DateTime at,
    String title = '',
    String kind = 'direct',
    Map<String, dynamic>? metadata,
  }) async {
    await upsertConversation(channelId: channelId, workspaceId: workspaceId, title: title, kind: kind, metadata: metadata);
    await db.update('local_conversations', {
      'last_message': preview,
      'last_sender_name': senderName,
      'last_message_at': at.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'channel_id = ?', whereArgs: [channelId]);
  }

  Future<List<Map<String, dynamic>>> conversations() => db.query('local_conversations', orderBy: 'CASE WHEN last_message_at IS NULL THEN 1 ELSE 0 END, last_message_at DESC, updated_at DESC');

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
    return db.rawInsert('''INSERT OR IGNORE INTO local_messages(
      client_message_id, legacy_server_id, workspace_id, channel_id, sender_profile_id,
      sender_name, sender_email, sender_phone, sender_avatar_url, body, type, created_at, edited_at,
      reply_to_client_id, forwarded_from_client_id, attachment_path, attachment_name,
      attachment_mime_type, attachment_size_bytes, starred, pinned, delivery_state, reactions_json, metadata_json)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', [
      clientMessageId, legacyServerId, workspaceId, channelId, senderProfileId, senderName,
      senderEmail, senderPhone, senderAvatarUrl, body, type, createdAt.toUtc().toIso8601String(),
      editedAt?.toUtc().toIso8601String(), replyToClientId, forwardedFromClientId, attachmentPath,
      attachmentName, attachmentMimeType, attachmentSizeBytes, starred ? 1 : 0, pinned ? 1 : 0,
      deliveryState, jsonEncode(reactions ?? const <String, dynamic>{}), jsonEncode(metadata ?? const <String, dynamic>{}),
    ]);
  }

  Future<List<Map<String, dynamic>>> messageRows(int channelId, {int limit = 200, int? beforeLocalId}) async {
    final rows = await db.query('local_messages', where: beforeLocalId == null ? 'channel_id = ?' : 'channel_id = ? AND id < ?', whereArgs: beforeLocalId == null ? [channelId] : [channelId, beforeLocalId], orderBy: 'created_at DESC, id DESC', limit: '$limit');
    return rows.reversed.toList();
  }

  Future<void> putMigrationState(String key, String value) async {
    await db.execute('CREATE TABLE IF NOT EXISTS local_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.insert('local_meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
