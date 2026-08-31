import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

class ChatCacheService {
  static const MethodChannel _channel = MethodChannel('taskly/media');
  String _namespace = 'anonymous';

  void useNamespace(String value) {
    final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    _namespace = safe.isEmpty ? 'anonymous' : safe;
  }

  Future<Directory?> _root() async {
    try {
      final path = await _channel.invokeMethod<String>('cacheRoot');
      if (path == null || path.trim().isEmpty) return null;
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (error) {
      debugPrint('TASKLY_CACHE_ROOT_ERROR $error');
      return null;
    }
  }

  Future<File?> _file(String name) async {
    final root = await _root();
    if (root == null) return null;
    return File('${root.path}${Platform.pathSeparator}${_namespace}_$name');
  }

  Future<List<Map<String, dynamic>>> readMessages(int channelId) async {
    final file = await _file('channel_${channelId}_messages_v43.json');
    if (file == null || !await file.exists()) return const [];
    return _readList(file);
  }

  Future<void> writeMessages(int channelId, List<Map<String, dynamic>> rows) async {
    final normalized = rows.map((row) => Map<String, dynamic>.from(row)).toList()
      ..sort((a, b) => _createdAt(a).compareTo(_createdAt(b)));
    await _writeJson('channel_${channelId}_messages_v43.json', normalized);
  }

  Future<void> upsertMessage(int channelId, Map<String, dynamic> row) async {
    final current = await readMessages(channelId);
    final id = '${row['id'] ?? row['client_message_id'] ?? ''}';
    final index = current.indexWhere((item) => '${item['id'] ?? item['client_message_id'] ?? ''}' == id);
    if (index >= 0) {
      current[index] = Map<String, dynamic>.from(row);
    } else {
      current.add(Map<String, dynamic>.from(row));
    }
    await writeMessages(channelId, current);
  }

  Future<void> removeMessage(int channelId, int messageId) async {
    final current = await readMessages(channelId);
    current.removeWhere((item) => _asInt(item['id']) == messageId);
    await writeMessages(channelId, current);
  }

  Future<List<ConversationItem>> readConversations() async {
    final file = await _file('conversations_v43.json');
    if (file == null || !await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => ConversationItem.fromJson(Map<String, dynamic>.from(row)))
          .where((item) => item.channelId > 0)
          .toList(growable: false);
    } catch (error) {
      debugPrint('TASKLY_CACHE_READ_CONVERSATIONS_ERROR $error');
      return const [];
    }
  }

  Future<void> writeConversations(List<ConversationItem> items) async {
    await _writeJson('conversations_v43.json', items.map(_conversationJson).toList());
  }

  Future<({
    List<Map<String, dynamic>> conversations,
    Map<int, List<Map<String, dynamic>>> messages,
  })> readLegacyRecoveryBundle() async {
    final root = await _root();
    if (root == null || !await root.exists()) {
      return (conversations: <Map<String, dynamic>>[], messages: <int, List<Map<String, dynamic>>>{});
    }

    final allFiles = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.json')) allFiles.add(entity);
    }

    final requestedPrefix = '${_namespace}_';
    var prefix = requestedPrefix;
    final requested = allFiles.where((file) => _fileName(file).startsWith(requestedPrefix)).toList();

    // If the authenticated namespace is not present, use the newest local
    // Taskly conversation snapshot on the device. This keeps recovery working
    // after reinstall/session migration without requiring server chat history.
    if (requested.isEmpty) {
      String? newest;
      DateTime? newestTime;
      for (final file in allFiles) {
        final name = _fileName(file);
        final match = RegExp(r'^(.+)_conversations_v43\.json$').firstMatch(name);
        if (match == null) continue;
        final modified = await file.lastModified();
        if (newestTime == null || modified.isAfter(newestTime)) {
          newest = match.group(1);
          newestTime = modified;
        }
      }
      if (newest != null) prefix = '${newest}_';
    }

    final conversations = <Map<String, dynamic>>[];
    final messages = <int, List<Map<String, dynamic>>>{};

    for (final entity in allFiles) {
      final name = _fileName(entity);
      if (!name.startsWith(prefix) || !name.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! List) continue;
        if (name == '${prefix}conversations_v43.json') {
          conversations.addAll(decoded.whereType<Map>().map(Map<String, dynamic>.from));
          continue;
        }
        final match = RegExp('^${RegExp.escape(prefix)}channel_(\\d+)_messages_v43\\.json\$').firstMatch(name);
        final channelId = match == null ? null : int.tryParse(match.group(1)!);
        if (channelId == null || channelId <= 0) continue;
        messages[channelId] = decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
      } catch (error) {
        debugPrint('TASKLY_CACHE_RECOVERY_READ_ERROR file=$name $error');
      }
    }

    return (conversations: conversations, messages: messages);
  }

  Future<Map<String, dynamic>> readRecoveryFiles() async {
    final bundle = await readLegacyRecoveryBundle();
    return {
      'conversations': bundle.conversations,
      'messages': {for (final entry in bundle.messages.entries) '${entry.key}': entry.value},
    };
  }

  Future<String?> findExistingMedia(String fileName) async {
    final root = await _root();
    if (root == null) return null;
    final tasklyRoot = root.parent;
    final mediaRoot = Directory('${tasklyRoot.path}${Platform.pathSeparator}Media');
    if (!await mediaRoot.exists()) return null;
    final wanted = fileName.trim();
    if (wanted.isEmpty) return null;
    await for (final entity in mediaRoot.list(recursive: true, followLinks: false)) {
      if (entity is File && _fileName(entity) == wanted) return entity.path;
    }
    return null;
  }

  Future<void> clearChannel(int channelId) async {
    final file = await _file('channel_${channelId}_messages_v43.json');
    if (file != null && await file.exists()) await file.delete();
  }

  Future<void> _writeJson(String name, Object value) async {
    final file = await _file(name);
    if (file == null) return;
    try {
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(value), flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (error) {
      debugPrint('TASKLY_CACHE_WRITE_ERROR file=$name $error');
    }
  }

  Future<List<Map<String, dynamic>>> _readList(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList(growable: true);
    } catch (error) {
      debugPrint('TASKLY_CACHE_READ_ERROR $error');
      return const [];
    }
  }

  Map<String, dynamic> _conversationJson(ConversationItem item) => {
        'channel_id': item.channelId,
        'workspace_id': item.workspaceId,
        'kind': item.kind,
        'name': item.name,
        'description': item.description,
        'avatar_url': item.avatarUrl,
        'join_code': item.joinCode,
        'member_count': item.memberCount,
        'last_message': item.lastMessage,
        'last_sender_name': item.lastSenderName,
        'last_message_at': item.lastMessageAt?.toUtc().toIso8601String(),
        'unread_count': item.unreadCount,
        'is_muted': item.isMuted,
        'is_archived': item.isArchived,
        'current_role': item.currentRole,
        'only_admins_can_send': item.onlyAdminsCanSend,
        'only_admins_can_edit': item.onlyAdminsCanEdit,
        'approve_new_members': item.approveNewMembers,
        'pending_join_requests': item.pendingJoinRequests,
        'is_self_chat': item.isSelfChat,
      };

  String _fileName(File file) => file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last;
  int _asInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  String _createdAt(Map<String, dynamic> row) => '${row['created_at'] ?? ''}';
}
