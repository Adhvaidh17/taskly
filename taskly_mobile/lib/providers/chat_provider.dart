import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../services/chat_cache_service.dart';
import '../core/ai/quick_task_detector.dart';
import '../local_chat/local_ai_task_service.dart';
import '../local_chat/local_chat_database.dart';
import '../local_chat/local_chat_runtime.dart';
import '../local_chat/local_chat_transport.dart';
import '../services/chat_migration_coordinator_v63.dart';
import '../core/files/attachment_policy.dart';
import '../core/supabase/taskly_supabase.dart';
import '../models/channel.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/local_media_service.dart';

class ChatProvider extends ChangeNotifier {
  final ChatCacheService _cache = ChatCacheService();
  ChatProvider(this.backend, this.media);

  final TasklySupabase backend;
  final LocalMediaService media;
  final LocalChatRuntime _localRuntime = LocalChatRuntime.instance;
  LocalAiTaskService? _localAi;
  ChatMigrationCoordinatorV63? _migration;
  bool _migrationStarted = false;
  bool _cacheRecoveryStarted = false;
  List<ConversationItem> conversations = [];
  final Map<int, List<MessageItem>> messages = {};
  final Map<int, List<AppUser>> members = {};
  final Map<int, String> taskAnalysisErrors = {};
  final Set<int> taskAnalysisPendingIds = {};
  final Map<int, String> localAttachmentPaths = {};
  final Set<int> unavailableAttachmentIds = {};
  final Set<int> downloadingAttachmentIds = {};
  bool loadingConversations = false;
  bool loadingMessages = false;
  final Set<int> loadingOlderChannels = <int>{};
  final Map<int, bool> hasOlderMessages = <int, bool>{};
  bool sending = false;
  String? error;
  int? currentProfileId;
  StreamSubscription<int>? _messageSubscription;
  Timer? _reloadDebounce;
  final Set<int> _pendingRealtimeMessageIds = <int>{};
  bool _selfChatEnsured = false;
  ConversationItem? _selfConversation;


  Future<void> _restoreLegacyCacheToLocal() async {
    final userId = backend.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      _cache.useNamespace(userId);
      final bundle = await _cache.readLegacyRecoveryBundle();

      for (final row in bundle.conversations) {
        final channelId = int.tryParse('${row['channel_id'] ?? ''}');
        final workspaceId = int.tryParse('${row['workspace_id'] ?? ''}');
        if (channelId == null || workspaceId == null || channelId <= 0) continue;
        await _localDb.upsertConversation(
          channelId: channelId,
          workspaceId: workspaceId,
          title: '${row['name'] ?? row['title'] ?? ''}',
          kind: '${row['kind'] ?? 'direct'}',
          avatarUrl: row['avatar_url'] as String?,
        );
        await _localDb.db.update(
          'local_conversations',
          {
            'last_message': row['last_message'],
            'last_sender_name': row['last_sender_name'],
            'last_message_at': row['last_message_at'],
            'unread_count': (row['unread_count'] as num?)?.toInt() ?? 0,
            'muted': row['is_muted'] == true ? 1 : 0,
            'archived': row['is_archived'] == true ? 1 : 0,
          },
          where: 'channel_id = ?',
          whereArgs: [channelId],
        );
      }

      var imported = 0;
      for (final entry in bundle.messages.entries) {
        final channelId = entry.key;
        for (final row in entry.value) {
          // Deleted legacy rows are not resurrected.
          if (row['deleted_at'] != null) continue;
          final legacyId = int.tryParse('${row['id'] ?? ''}');
          if (legacyId == null || legacyId <= 0) continue;
          final sender = row['sender'] is Map
              ? Map<String, dynamic>.from(row['sender'] as Map)
              : <String, dynamic>{};
          String? localAttachment = row['local_attachment_path'] as String?;
          if (localAttachment == null || localAttachment.isEmpty ||
              !await File(localAttachment).exists()) {
            final name = '${row['attachment_name'] ?? ''}'.trim();
            if (name.isNotEmpty) {
              localAttachment = await _cache.findExistingMedia(name);
            }
          }
          final hasAttachment = '${row['attachment_name'] ?? ''}'.trim().isNotEmpty;
          final body = '${row['body'] ?? ''}';
          if (hasAttachment && (localAttachment == null || localAttachment.isEmpty)) {
            if (body.trim().isEmpty) continue;
          }

          await _localDb.insertMessage(
            clientMessageId:
                '${row['client_message_id'] ?? 'legacy-$legacyId'}',
            legacyServerId: legacyId,
            workspaceId: int.tryParse('${row['workspace_id'] ?? 0}') ?? 0,
            channelId: channelId,
            senderProfileId: int.tryParse(
              '${sender['id'] ?? row['sender_profile_id'] ?? ''}',
            ),
            senderName: '${sender['name'] ?? row['sender_name'] ?? ''}',
            senderEmail: sender['email'] as String?,
            senderPhone: sender['phone'] as String?,
            senderAvatarUrl: sender['avatar_url'] as String?,
            body: body,
            type: hasAttachment && (localAttachment == null || localAttachment.isEmpty)
                ? 'text'
                : '${row['type'] ?? 'text'}',
            createdAt: DateTime.tryParse('${row['created_at'] ?? ''}') ??
                DateTime.now().toUtc(),
            editedAt: DateTime.tryParse('${row['edited_at'] ?? ''}'),
            attachmentPath: localAttachment,
            attachmentName: localAttachment == null ? null : row['attachment_name'] as String?,
            attachmentMimeType: localAttachment == null ? null : row['attachment_mime_type'] as String?,
            attachmentSizeBytes: localAttachment == null
                ? null
                : int.tryParse('${row['attachment_size_bytes'] ?? ''}'),
            pinned: row['is_pinned'] == true,
            deliveryState: 'recovered',
            metadata: {
              'recovered_from_cache_v43': true,
              'legacy_deleted_at': row['deleted_at'],
            },
          );
          imported++;
        }
        final rows = await _localDb.messageRows(channelId, limit: 5000);
        await _cache.writeMessages(channelId, rows);
      }
      if (imported > 0) {
        await _localDb.putMigrationState(
          'cache_recovery_v43',
          'complete:$imported:${DateTime.now().toUtc().toIso8601String()}',
        );
      }
    } catch (error) {
      debugPrint('TASKLY_CACHE_RECOVERY_ERROR $error');
      _cacheRecoveryStarted = false;
    }
  }

  Future<void> _ensureLocal() async {
    await _localRuntime.initialize(backend.client);
    final userId = backend.client.auth.currentUser?.id;
    if (userId == null) return;
    _localAi ??= LocalAiTaskService(
      client: backend.client,
      database: _localRuntime.database,
    );
    if (!_cacheRecoveryStarted) {
      _cacheRecoveryStarted = true;
      await _restoreLegacyCacheToLocal();
    }
    _migration ??= ChatMigrationCoordinatorV63(backend: backend);
    if (!_migrationStarted) {
      _migrationStarted = true;
      unawaited(_migration!.start());
    } else {
      unawaited(_migration!.runOnce());
    }
  }

  LocalChatDatabase get _localDb => _localRuntime.database;
  LocalChatTransport? get _localTransport => _localRuntime.transport;

  Future<void> loadConversations() async {
    await _ensureLocal();
    if (conversations.isEmpty) {
      final localRows = await _localDb.conversations();
      if (localRows.isNotEmpty) {
        conversations = localRows.map((row) => ConversationItem.fromJson({
          'channel_id': row['channel_id'],
          'workspace_id': row['workspace_id'],
          'kind': row['kind'],
          'name': row['title'],
          'avatar_url': row['avatar_url'],
          'last_message': row['last_message'],
          'last_sender_name': row['last_sender_name'],
          'last_message_at': row['last_message_at'],
          'unread_count': row['unread_count'],
          'is_muted': (row['muted'] as num? ?? 0).toInt() == 1,
          'is_archived': (row['archived'] as num? ?? 0).toInt() == 1,
        })).toList();
        notifyListeners();
      }
    }
    loadingConversations = conversations.isEmpty;
    error = null;
    notifyListeners();
    try {
      currentProfileId ??= await backend.profileId();
      if (!_selfChatEnsured || _selfConversation == null) {
        try {
          _selfConversation = ConversationItem.fromJson(
            await backend.ensureSelfChat(),
          );
          _selfChatEnsured = true;
        } catch (_) {
          // Keep normal conversations available while migrations settle.
        }
      }

      final serverLoaded = (await backend.conversations())
          .map(ConversationItem.fromJson)
          .toList();
      final loaded = serverLoaded.isNotEmpty
          ? serverLoaded
          : (await _localDb.conversations()).map((row) => ConversationItem.fromJson({
              'channel_id': row['channel_id'],
              'workspace_id': row['workspace_id'],
              'kind': row['kind'],
              'name': row['title'],
              'avatar_url': row['avatar_url'],
              'last_message': row['last_message'],
              'last_sender_name': row['last_sender_name'],
              'last_message_at': row['last_message_at'],
              'unread_count': row['unread_count'],
              'is_muted': (row['muted'] as num? ?? 0).toInt() == 1,
              'is_archived': (row['archived'] as num? ?? 0).toInt() == 1,
            })).toList();
      ConversationItem? selfChat;
      for (final item in loaded) {
        if (item.isSelfChat) {
          selfChat = item;
          break;
        }
      }
      final resolvedSelfChat = selfChat ?? _selfConversation;
      if (resolvedSelfChat != null) {
        _selfConversation = resolvedSelfChat;
        loaded.removeWhere(
          (item) => item.channelId == resolvedSelfChat.channelId,
        );
        loaded.insert(0, resolvedSelfChat);
        _selfChatEnsured = true;
      }
      final localRows = await _localDb.conversations();
      final localByChannel = <int, Map<String, dynamic>>{
        for (final row in localRows) (row['channel_id'] as num).toInt(): row,
      };
      conversations = loaded.map((item) {
        final local = localByChannel[item.channelId];
        return item.copyWith(
          lastMessage: local?['last_message'] as String?,
          lastSenderName: local?['last_sender_name'] as String?,
          lastMessageAt: local == null ? null : DateTime.tryParse('${local['last_message_at'] ?? ''}')?.toLocal(),
          unreadCount: local == null ? 0 : (local['unread_count'] as num? ?? 0).toInt(),
          isMuted: local == null ? item.isMuted : (local['muted'] as num? ?? 0).toInt() == 1,
          isArchived: local == null ? item.isArchived : (local['archived'] as num? ?? 0).toInt() == 1,
        );
      }).toList();
      unawaited(_cache.writeConversations(conversations));
    } catch (exception) {
      error = '$exception';
    } finally {
      loadingConversations = false;
      notifyListeners();
    }
  }

  Future<void> openConversation(ConversationItem conversation) async {
    await _ensureLocal();
    error = null;
    currentProfileId ??= await backend.profileId();
    final profileId = currentProfileId!;
    final rows = await _localDb.messageRows(conversation.channelId, limit: 200);
    final hasLocal = rows.isNotEmpty;
    messages[conversation.channelId] = rows
        .map((row) => MessageItem.fromJson(row, currentProfileId: profileId))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    unawaited(_cache.writeMessages(conversation.channelId, rows));
    hasOlderMessages[conversation.channelId] = rows.length >= 200;
    loadingMessages = !hasLocal;
    notifyListeners();

    await _messageSubscription?.cancel();
    _messageSubscription = _localTransport?.channelChanged.listen((channelId) async {
      if (channelId != conversation.channelId) return;
      final fresh = await _localDb.messageRows(channelId, limit: 200);
      messages[channelId] = fresh
          .map((row) => MessageItem.fromJson(row, currentProfileId: profileId))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();
    });

    try {
      await _localTransport?.pullNow();
      await _localTransport?.flushOutbox();
      await _loadMembers(conversation.channelId);
    } catch (exception) {
      debugPrint('TASKLY_LOCAL_CHAT_SYNC $exception');
    } finally {
      loadingMessages = false;
      notifyListeners();
    }
  }

  Future<void> _loadMembers(int channelId) async {
    members[channelId] = (await backend.conversationMembers(channelId))
        .map(AppUser.fromJson)
        .toList();
  }

  Future<void> refreshMembers(int channelId) async {
    currentProfileId ??= await backend.profileId();
    await _loadMembers(channelId);
    notifyListeners();
  }

  Future<void> _reloadMessages(int channelId) async {
    await _ensureLocal();
    final profileId = currentProfileId ?? await backend.profileId();
    final rows = await _localDb.messageRows(channelId, limit: 200);
    messages[channelId] = rows
        .map((json) => MessageItem.fromJson(json, currentProfileId: profileId))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    hasOlderMessages[channelId] = rows.length >= 200;
    loadingMessages = false;
    notifyListeners();
  }

  Future<int> loadOlderMessages(int channelId) async {
    if (loadingOlderChannels.contains(channelId) || hasOlderMessages[channelId] == false) return 0;
    final current = messages[channelId] ?? const <MessageItem>[];
    if (current.isEmpty) return 0;
    final beforeLocalId = current.map((m) => m.id).where((id) => id > 0).fold<int?>(null, (a,b) => a == null || b < a ? b : a);
    if (beforeLocalId == null) return 0;
    loadingOlderChannels.add(channelId);
    notifyListeners();
    try {
      final profileId = currentProfileId ?? await backend.profileId();
      final rows = await _localDb.messageRows(channelId, limit: 200, beforeLocalId: beforeLocalId);
      final older = rows.map((row) => MessageItem.fromJson(row, currentProfileId: profileId)).toList();
      final known = current.map((m) => m.id).toSet();
      final fresh = older.where((m) => !known.contains(m.id)).toList();
      if (fresh.isNotEmpty) {
        messages[channelId] = [...fresh, ...current]..sort((a,b) => a.createdAt.compareTo(b.createdAt));
      }
      hasOlderMessages[channelId] = rows.length >= 200;
      return fresh.length;
    } finally {
      loadingOlderChannels.remove(channelId);
      notifyListeners();
    }
  }

  Future<void> _reloadMessage(int channelId, int messageId) async {
    final rows = await _localDb.messageRows(channelId, limit: 200);
    final row = rows.where((r) => '${r['id']}' == '$messageId').firstOrNull;
    if (row == null) return;
    final profileId = currentProfileId ?? await backend.profileId();
    _upsertMessage(channelId, MessageItem.fromJson(row, currentProfileId: profileId));
    notifyListeners();
  }

  void _upsertMessage(
    int channelId,
    MessageItem item, {
    int? replaceMessageId,
  }) {
    final current = messages.putIfAbsent(channelId, () => <MessageItem>[]);
    var targetIndex = replaceMessageId == null
        ? current.indexWhere((message) => message.id == item.id)
        : current.indexWhere((message) => message.id == replaceMessageId);
    if (targetIndex < 0) {
      targetIndex = current.indexWhere((message) => message.id == item.id);
    }
    if (targetIndex >= 0) {
      current[targetIndex] = item;
    } else {
      current.add(item);
      targetIndex = current.length - 1;
    }
    for (var index = current.length - 1; index >= 0; index--) {
      if (index != targetIndex && current[index].id == item.id) {
        current.removeAt(index);
        if (index < targetIndex) targetIndex--;
      }
    }
    current.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> _syncLocalMediaForChannel(int channelId) async {
    final current = messages[channelId] ?? const <MessageItem>[];
    for (final message in current) {
      final path = message.attachmentPath;
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        localAttachmentPaths[message.id] = path;
        unavailableAttachmentIds.remove(message.id);
      }
    }
  }

  Future<String?> ensureMessageLocal(MessageItem message) async {
    final path = localAttachmentPaths[message.id] ?? message.attachmentPath;
    if (path != null && path.isNotEmpty && await File(path).exists()) {
      localAttachmentPaths[message.id] = path;
      return path;
    }
    return null;
  }

  Future<void> openMessageAttachment(MessageItem message) async {
    final path = await ensureMessageLocal(message);
    if (path == null) throw const FileSystemException('This file is not available on this device.');
    await media.openFile(path, mimeType: message.attachmentMimeType ?? 'application/octet-stream');
  }

  Future<void> refreshLocalMedia(int channelId, int messageId) async {
    final current = messages[channelId] ?? const <MessageItem>[];
    final message = current.where((m) => m.id == messageId).firstOrNull;
    if (message == null) return;
    final path = message.attachmentPath;
    if (path != null && path.isNotEmpty && await File(path).exists()) {
      localAttachmentPaths[messageId] = path;
      unavailableAttachmentIds.remove(messageId);
    } else {
      localAttachmentPaths.remove(messageId);
      unavailableAttachmentIds.remove(messageId);
    }
    notifyListeners();
  }

  Future<void> send({
    required ConversationItem conversation,
    required String body,
    List<int> mentionedProfileIds = const [],
    int? replyToMessageId,
  }) async {
    final cleanBody = body.trim();
    if (cleanBody.isEmpty) return;
    await _ensureLocal();
    final transport = _localTransport;
    if (transport == null) throw StateError('Local chat storage is unavailable.');
    final profileId = currentProfileId ?? await backend.profileId();
    currentProfileId = profileId;
    final current = messages.putIfAbsent(conversation.channelId, () => []);
    final reply = replyToMessageId == null ? null : current.where((m) => m.id == replyToMessageId).firstOrNull;
    final row = await transport.sendText(
      workspaceId: conversation.workspaceId,
      channelId: conversation.channelId,
      body: cleanBody,
      replyToClientId: reply?.id.toString(),
    );
    final item = MessageItem.fromJson(row, currentProfileId: profileId);
    _upsertMessage(conversation.channelId, item);
    unawaited(_cache.upsertMessage(conversation.channelId, row));
    notifyListeners();
    unawaited(_analyseAndApplyLocal(conversation, item));
    _touchConversation(conversation.channelId, body: cleanBody, senderName: item.sender.name, at: item.createdAt);
  }

  Future<void> _analyseAndApplyLocal(ConversationItem conversation, MessageItem item) async {
    final ai = _localAi;
    if (ai == null) return;
    try {
      final local = await _localDb.messageByLocalId(item.id);
      final clientMessageId = local?['client_message_id']?.toString();
      if (clientMessageId == null || clientMessageId.isEmpty) return;
      final result = await ai.analyse(
        clientMessageId: clientMessageId,
        workspaceId: conversation.workspaceId,
        channelId: conversation.channelId,
        text: item.body,
        timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      );
      if (result == null) return;
      final suggestion = TaskSuggestionItem.fromJson(result);
      _replaceMessageSuggestion(conversation.channelId, item.id, suggestion);
      notifyListeners();
    } catch (_) {
      // AI is optional and must never interrupt chat.
    }
  }

  Future<void> _analyseAndApply(ConversationItem conversation, int messageId) async {
    final current = messages[conversation.channelId] ?? const <MessageItem>[];
    final item = current.where((m) => m.id == messageId).firstOrNull;
    if (item != null) await _analyseAndApplyLocal(conversation, item);
  }

  Future<void> retryTaskAnalysis(ConversationItem conversation, int messageId) async {
    final current = messages[conversation.channelId] ?? const <MessageItem>[];
    final item = current.where((m) => m.id == messageId).firstOrNull;
    if (item != null) await _analyseAndApplyLocal(conversation, item);
  }

  void _replaceMessageSuggestion(
    int channelId,
    int messageId,
    TaskSuggestionItem suggestion,
  ) {
    final current = messages[channelId];
    if (current == null) return;
    final index = current.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    current[index] = current[index].withSuggestion(suggestion);
  }

  Future<void> sendAttachment({
    required ConversationItem conversation,
    required String filePath,
    int? replyToMessageId,
  }) async {
    await _ensureLocal();
    final transport = _localTransport;
    if (transport == null) throw StateError('Local chat storage is unavailable.');
    final prepared = await media.prepareOutgoing(filePath);
    final current = messages.putIfAbsent(conversation.channelId, () => []);
    final reply = replyToMessageId == null ? null : current.where((m) => m.id == replyToMessageId).firstOrNull;
    final row = await transport.sendAttachment(
      workspaceId: conversation.workspaceId,
      channelId: conversation.channelId,
      sourcePath: prepared.path,
      body: prepared.name,
      mimeType: prepared.mimeType,
      replyToClientId: reply?.id.toString(),
    );
    final item = MessageItem.fromJson(row, currentProfileId: currentProfileId ?? await backend.profileId());
    _upsertMessage(conversation.channelId, item);
    localAttachmentPaths[item.id] = item.attachmentPath ?? prepared.path;
    unawaited(_cache.upsertMessage(conversation.channelId, row));
    notifyListeners();
  }

  Future<void> sendContact({
    required ConversationItem conversation,
    required AppUser contact,
    int? replyToMessageId,
  }) async {
    await _ensureLocal();
    final transport = _localTransport;
    if (transport == null) throw StateError('Local chat storage is unavailable.');
    final current = messages.putIfAbsent(conversation.channelId, () => []);
    final reply = replyToMessageId == null ? null : current.where((m) => m.id == replyToMessageId).firstOrNull;
    final row = await transport.sendStructuredMessage(
      workspaceId: conversation.workspaceId,
      channelId: conversation.channelId,
      body: contact.name,
      type: 'contact',
      replyToClientId: reply?.id.toString(),
      metadata: {
        'shared_contact_profile_id': contact.id,
        'shared_contact_name': contact.name,
        'shared_contact_phone': contact.phone,
        'shared_contact_email': contact.email,
      },
    );
    final item = MessageItem.fromJson(row, currentProfileId: currentProfileId ?? await backend.profileId());
    _upsertMessage(conversation.channelId, item);
    unawaited(_cache.upsertMessage(conversation.channelId, row));
    notifyListeners();
  }

  Future<void> forwardMessage({
    required MessageItem message,
    required List<ConversationItem> targets,
  }) async {
    await _ensureLocal();
    final transport = _localTransport;
    if (transport == null) throw StateError('Local chat storage is unavailable.');
    for (final target in targets) {
      final sourcePath = localAttachmentPaths[message.id] ?? message.attachmentPath;
      final row = await transport.sendStructuredMessage(
        workspaceId: target.workspaceId,
        channelId: target.channelId,
        body: message.body,
        type: message.type,
        attachmentPath: sourcePath,
        attachmentName: message.attachmentName,
        attachmentMimeType: message.attachmentMimeType,
        metadata: {
          'forwarded_from_local_id': message.id,
          'shared_contact_profile_id': message.sharedContactProfileId,
          'shared_contact_name': message.sharedContactName,
          'shared_contact_phone': message.sharedContactPhone,
          'shared_contact_email': message.sharedContactEmail,
        },
      );
      final item = MessageItem.fromJson(row, currentProfileId: currentProfileId ?? await backend.profileId());
      _upsertMessage(target.channelId, item);
      unawaited(_cache.upsertMessage(target.channelId, row));
    }
    notifyListeners();
  }

  Future<void> updateSuggestion(int channelId, int suggestionId, Map<String, dynamic> values) async {
    final rows = await _localDb.db.query(
      'local_task_suggestions',
      where: 'channel_id = ? AND dismissed = 0',
      whereArgs: [channelId],
    );
    for (final row in rows) {
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(row['payload_json'] as String));
        payload.addAll(values);
        if (values.containsKey('assignee_id')) payload['assignee_profile_id'] = values['assignee_id'];
        if (values.containsKey('deadline')) payload['deadline_iso'] = values['deadline'];
        await _localDb.db.update(
          'local_task_suggestions',
          {'payload_json': jsonEncode(payload)},
          where: 'client_message_id = ?',
          whereArgs: [row['client_message_id']],
        );
      } catch (_) {}
    }
    await _reloadMessages(channelId);
  }

  Future<void> confirmSuggestion(int channelId, int suggestionId) async {
    final rows = await _localDb.db.query(
      'local_task_suggestions',
      where: 'channel_id = ? AND dismissed = 0',
      whereArgs: [channelId],
    );
    Map<String, dynamic>? payload;
    String? clientId;
    for (final row in rows) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(row['payload_json'] as String));
        if (-('${row['client_message_id']}').hashCode.abs() == suggestionId) {
          payload = decoded;
          clientId = row['client_message_id'] as String;
          break;
        }
      } catch (_) {}
    }
    if (payload == null) return;
    final values = <String, dynamic>{
      'channel_id': channelId,
      'title': '${payload['title'] ?? 'New task'}',
      'description': payload['description'],
      'priority': payload['priority'] ?? 'medium',
      'deadline': payload['deadline_iso']?.toString().isNotEmpty == true ? payload['deadline_iso'] : null,
      'assignee_id': ((payload['assignee_profile_id'] as num?)?.toInt() ?? 0) > 0
          ? (payload['assignee_profile_id'] as num).toInt()
          : null,
      'source_type': 'message',
    }..removeWhere((key, value) => value == null || (value is String && value.isEmpty));
    await backend.createTask(values);
    if (clientId != null) await _localDb.dismissTaskSuggestion(clientId);
    await _reloadMessages(channelId);
  }

  Future<void> dismissSuggestion(int channelId, int suggestionId) async {
    final rows = await _localDb.db.query('local_task_suggestions', where: 'channel_id = ?', whereArgs: [channelId]);
    for (final row in rows) {
      await _localDb.dismissTaskSuggestion(row['client_message_id'] as String);
    }
    await _reloadMessages(channelId);
  }

  Future<ConversationItem> startDirectChat(AppUser user) async {
    final result = await backend.getOrCreateDirectChat(user.id);
    final conversation = ConversationItem.fromJson({
      ...result,
      'name': '${result['name'] ?? user.name}',
      'kind': 'direct',
    });
    unawaited(loadConversations());
    return conversation;
  }

  Future<String> _clientIdForLocalId(int channelId, int localId) async {
    final row = await _localDb.messageByLocalId(localId);
    if (row == null) throw StateError('Message no longer exists on this device.');
    return row['client_message_id'] as String;
  }

  Future<void> editMessage(int channelId, int messageId, String body) async {
    final transport = _localTransport;
    if (transport == null) return;
    await transport.editMessage(channelId: channelId, clientMessageId: await _clientIdForLocalId(channelId, messageId), body: body.trim());
    await _reloadMessages(channelId);
  }

  Future<void> deleteMessage(int channelId, int messageId) async {
    final transport = _localTransport;
    if (transport == null) return;
    await transport.deleteForEveryone(channelId: channelId, clientMessageId: await _clientIdForLocalId(channelId, messageId));
    messages[channelId]?.removeWhere((m) => m.id == messageId);
    localAttachmentPaths.remove(messageId);
    unavailableAttachmentIds.remove(messageId);
    notifyListeners();
  }

  Future<void> react(int channelId, int messageId, String emoji) async {
    final transport = _localTransport;
    if (transport == null) return;
    final clientId = await _clientIdForLocalId(channelId, messageId);
    final current = messages[channelId]?.where((m) => m.id == messageId).firstOrNull;
    final mine = current?.reactions.any((r) => r.mine && r.emoji == emoji) == true;
    await transport.setReaction(
      channelId: channelId,
      clientMessageId: clientId,
      emoji: emoji,
      reactorProfileId: currentProfileId ?? await backend.profileId(),
      enabled: !mine,
    );
    await _reloadMessages(channelId);
  }

  Future<void> pin(int channelId, int messageId, bool pinned) async {
    final transport = _localTransport;
    if (transport == null) return;
    await transport.setPinned(channelId: channelId, clientMessageId: await _clientIdForLocalId(channelId, messageId), pinned: pinned);
    await _reloadMessages(channelId);
  }

  void _touchConversation(
    int channelId, {
    required String body,
    required String senderName,
    required DateTime at,
  }) {
    final index =
        conversations.indexWhere((item) => item.channelId == channelId);
    if (index < 0) return;
    conversations[index] = conversations[index].copyWith(
      lastMessage: body,
      lastSenderName: senderName,
      lastMessageAt: at,
      unreadCount: 0,
    );
    notifyListeners();
  }

  Future<void> setConversationPreferences(
    ConversationItem conversation, {
    bool? muted,
    bool? archived,
  }) async {
    await _ensureLocal();
    await _localDb.setConversationPreference(
      conversation.channelId,
      muted: muted,
      archived: archived,
    );
    await loadConversations();
  }

  Future<void> clearLocalData() async {
    await media.clearAllLocalMedia();
    await _localRuntime.database.clearAllData();
    localAttachmentPaths.clear();
    unavailableAttachmentIds.clear();
    downloadingAttachmentIds.clear();
    messages.clear();
    conversations.clear();
    notifyListeners();
    unawaited(loadConversations());
  }

  Future<void> clearChat(ConversationItem conversation) async {
    await _ensureLocal();
    await _localDb.clearChat(conversation.channelId);
    messages[conversation.channelId] = [];
    localAttachmentPaths.removeWhere((key, _) => messages[conversation.channelId]?.any((m) => m.id == key) != true);
    notifyListeners();
    await loadConversations();
  }

  Future<void> deleteChat(ConversationItem conversation) async {
    await _ensureLocal();
    await _localDb.deleteConversation(conversation.channelId);
    messages.remove(conversation.channelId);
    await loadConversations();
  }

  Future<Map<String, dynamic>> loadGroupAdminState(int workspaceId) {
    return backend.groupAdminState(workspaceId);
  }

  Future<Map<String, dynamic>> updateGroup({
    required int workspaceId,
    String? name,
    String? description,
    bool? onlyAdminsCanSend,
    bool? onlyAdminsCanEdit,
    bool? approveNewMembers,
  }) async {
    final result = await backend.updateGroup(
      workspaceId: workspaceId,
      name: name,
      description: description,
      onlyAdminsCanSend: onlyAdminsCanSend,
      onlyAdminsCanEdit: onlyAdminsCanEdit,
      approveNewMembers: approveNewMembers,
    );
    await loadConversations();
    return result;
  }

  Future<String> resetGroupJoinCode(int workspaceId) async {
    final code = await backend.resetGroupJoinCode(workspaceId);
    await loadConversations();
    return code;
  }

  Future<void> setGroupMemberRole({
    required int workspaceId,
    required int channelId,
    required int profileId,
    required String role,
  }) async {
    await backend.setGroupMemberRole(
      workspaceId: workspaceId,
      profileId: profileId,
      role: role,
    );
    await _loadMembers(channelId);
    notifyListeners();
  }

  Future<void> removeGroupMember({
    required int workspaceId,
    required int channelId,
    required int profileId,
  }) async {
    await backend.removeGroupMember(
      workspaceId: workspaceId,
      profileId: profileId,
    );
    await _loadMembers(channelId);
    await loadConversations();
  }

  Future<void> addGroupMemberByIdentifier({
    required int workspaceId,
    required int channelId,
    required String identifier,
  }) async {
    await backend.addGroupMemberByIdentifier(
      workspaceId: workspaceId,
      identifier: identifier,
    );
    await _loadMembers(channelId);
    await loadConversations();
  }

  Future<void> addGroupMemberByProfileId({
    required int workspaceId,
    required int channelId,
    required int profileId,
  }) async {
    await backend.addGroupMemberByProfileId(
      workspaceId: workspaceId,
      profileId: profileId,
    );
    await _loadMembers(channelId);
    await loadConversations();
  }

  Future<void> reviewJoinRequest({
    required int requestId,
    required bool approve,
  }) async {
    await backend.reviewJoinRequest(requestId, approve);
  }

  Future<void> leaveGroup(int workspaceId) async {
    await backend.leaveGroup(workspaceId);
    await loadConversations();
  }

  Future<void> deleteGroup(int workspaceId) async {
    await backend.deleteGroup(workspaceId);
    await loadConversations();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _messageSubscription?.cancel();
    unawaited(_migration?.dispose());
    unawaited(_localRuntime.disposeTransportOnly());
    super.dispose();
  }
}
