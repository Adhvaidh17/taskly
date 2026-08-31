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
    final clientId = '${row['client_message_id'] ?? ''}';
    final serverId = _asInt(row['id']);
    final index = current.indexWhere((item) {
      final sameClient = clientId.isNotEmpty && '${item['client_message_id'] ?? ''}' == clientId;
      final sameServer = serverId > 0 && _asInt(item['id']) == serverId;
      return sameClient || sameServer;
    });
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
    final root = await _root();
    if (root == null || !await root.exists()) return const [];
    File? selected;
    final exact = File('${root.path}${Platform.pathSeparator}${_namespace}_conversations_v43.json');
    if (await exact.exists()) {
      selected = exact;
    } else {
      selected = await _newestConversationFile(root);
    }
    if (selected == null || !await selected.exists()) return const [];
    try {
      final decoded = jsonDecode(await selected.readAsString());
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
    String? namespace,
    List<Map<String, dynamic>> conversations,
    Map<int, List<Map<String, dynamic>>> messages,
  })> readRecoveryBundle() async {
    final root = await _root();
    if (root == null || !await root.exists()) {
      return (namespace: null, conversations: <Map<String, dynamic>>[], messages: <int, List<Map<String, dynamic>>>{});
    }
    final files = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.json')) files.add(entity);
    }
    final namespaces = <String>{};
    for (final file in files) {
      final match = RegExp(r'^(.+)_conversations_v43\.json$').firstMatch(_fileName(file));
      if (match != null) namespaces.add(match.group(1)!);
    }
    if (namespaces.isEmpty) {
      return (namespace: null, conversations: <Map<String, dynamic>>[], messages: <int, List<Map<String, dynamic>>>{});
    }
    var selectedNamespace = _namespace;
    if (!namespaces.contains(selectedNamespace)) {
      final newest = await _newestConversationFile(root);
      final match = newest == null ? null : RegExp(r'^(.+)_conversations_v43\.json$').firstMatch(_fileName(newest));
      selectedNamespace = match?.group(1) ?? selectedNamespace;
    }
    final prefix = '${selectedNamespace}_';
    final conversations = <Map<String, dynamic>>[];
    final messages = <int, List<Map<String, dynamic>>>{};
    for (final file in files) {
      final name = _fileName(file);
      if (!name.startsWith(prefix) || !name.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
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
    return (namespace: selectedNamespace, conversations: conversations, messages: messages);
  }

  Future<({
    String? namespace,
    List<Map<String, dynamic>> conversations,
    Map<int, List<Map<String, dynamic>>> messages,
  })> readRecoveryBundleForProfile(int profileId) async {
    final root = await _root();
    if (root == null || !await root.exists()) {
      return (namespace: null, conversations: <Map<String, dynamic>>[], messages: <int, List<Map<String, dynamic>>>{});
    }
    final files = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.json')) files.add(entity);
    }
    final namespaces = <String>{};
    for (final file in files) {
      final match = RegExp(r'^(.+)_conversations_v43\.json$').firstMatch(_fileName(file));
      if (match != null) namespaces.add(match.group(1)!);
    }
    if (namespaces.contains(_namespace)) {
      namespaces.remove(_namespace);
      namespaces.add(_namespace);
    }
    for (final namespace in namespaces) {
      final prefix = '${namespace}_';
      final conversations = <Map<String, dynamic>>[];
      final messages = <int, List<Map<String, dynamic>>>{};
      var profileMatch = false;
      for (final file in files) {
        final name = _fileName(file);
        if (!name.startsWith(prefix) || !name.endsWith('.json')) continue;
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is! List) continue;
          if (name == '${prefix}conversations_v43.json') {
            conversations.addAll(decoded.whereType<Map>().map(Map<String, dynamic>.from));
            continue;
          }
          final match = RegExp('^${RegExp.escape(prefix)}channel_(\\d+)_messages_v43\\.json\$').firstMatch(name);
          final channelId = match == null ? null : int.tryParse(match.group(1)!);
          if (channelId == null || channelId <= 0) continue;
          final rows = decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
          messages[channelId] = rows;
          if (rows.any((row) {
            final sender = row['sender'];
            final senderId = sender is Map ? sender['id'] : row['sender_profile_id'];
            return _asInt(senderId) == profileId;
          })) profileMatch = true;
        } catch (error) {
          debugPrint('TASKLY_CACHE_RECOVERY_READ_ERROR file=$name $error');
        }
      }
      if (profileMatch) return (namespace: namespace, conversations: conversations, messages: messages);
    }
    return (namespace: null, conversations: <Map<String, dynamic>>[], messages: <int, List<Map<String, dynamic>>>{});
  }

  Future<({
    List<Map<String, dynamic>> conversations,
    Map<int, List<Map<String, dynamic>>> messages,
  })> readLegacyRecoveryBundle() async {
    final bundle = await readRecoveryBundle();
    return (conversations: bundle.conversations, messages: bundle.messages);
  }

  Future<Map<String, dynamic>> readRecoveryFiles() async {
    final bundle = await readLegacyRecoveryBundle();
    return {'conversations': bundle.conversations, 'messages': {for (final entry in bundle.messages.entries) '${entry.key}': entry.value}};
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

  Future<File?> _newestConversationFile(Directory root) async {
    File? newest;
    DateTime? newestTime;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!RegExp(r'^.+_conversations_v43\.json$').hasMatch(_fileName(entity))) continue;
      final modified = await entity.lastModified();
      if (newestTime == null || modified.isAfter(newestTime)) {
        newest = entity;
        newestTime = modified;
      }
    }
    return newest;
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
