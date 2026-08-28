import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';

/// Tiny disk cache for the hot chat path.
///
/// Device-owned hot chat cache. It is intentionally kept alongside Taskly
/// media in the Android cache folder. SQLite remains the indexed local store,
/// while these JSON snapshots make recovery and instant startup possible.
class ChatCacheService {
  static const MethodChannel _channel = MethodChannel('taskly/media');
  static const int _maxCachedMessagesPerChannel = 140;
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
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (error) {
      debugPrint('TASKLY_CACHE_READ_MESSAGES_ERROR channel=$channelId $error');
      return const [];
    }
  }

  Future<void> writeMessages(
    int channelId,
    List<Map<String, dynamic>> rows,
  ) async {
    final normalized = rows
        .where((row) => _asInt(row['id']) > 0)
        .toList(growable: false)
      ..sort((a, b) => _createdAt(a).compareTo(_createdAt(b)));
    final trimmed = normalized.length > _maxCachedMessagesPerChannel
        ? normalized.sublist(normalized.length - _maxCachedMessagesPerChannel)
        : normalized;
    await _writeJson('channel_${channelId}_messages_v43.json', trimmed);
  }

  Future<void> upsertMessage(int channelId, Map<String, dynamic> row) async {
    if (_asInt(row['id']) <= 0) return;
    final current = (await readMessages(channelId)).toList();
    final index = current.indexWhere((item) => _asInt(item['id']) == _asInt(row['id']));
    if (index >= 0) {
      current[index] = row;
    } else {
      current.add(row);
    }
    await writeMessages(channelId, current);
  }

  Future<void> removeMessage(int channelId, int messageId) async {
    final current = (await readMessages(channelId)).toList();
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
    await _writeJson(
      'conversations_v43.json',
      items.map(_conversationJson).toList(growable: false),
    );
  }


  /// Imports the existing v43 cache written by older Taskly builds.
  /// Nothing is deleted from the cache during import. This is deliberately
  /// idempotent so an interrupted/offline migration can safely retry.
  Future<({
  List<Map<String, dynamic>> conversations,
  Map<int, List<Map<String, dynamic>>> messages
})> readLegacyRecoveryBundle() async {

  final conversations =
      <Map<String, dynamic>>[];

  final messages =
      <int, List<Map<String, dynamic>>>{};


  final bundle = await readRecoveryFiles();

  for (final item in bundle['conversations'] ?? []) {
    conversations.add(
      Map<String, dynamic>.from(item),
    );
  }


  final rawMessages = bundle['messages'] ?? {};

  rawMessages.forEach((key, value) {

    final channelId = int.tryParse(key.toString());

    if (channelId == null) return;


    messages[channelId] =
        (value as List)
            .map(
              (e) => Map<String, dynamic>.from(e),
            )
            .toList();

  });


  return (
    conversations: conversations,
    messages: messages,
  );
}

  /// Finds an attachment that was already exported by the old Android build.
  /// The old cache stores server paths; the device media folder stores the
  /// actual bytes, so the filename is the safest recovery key.
  Future<String?> findExistingMedia(String fileName) async {
    final root = await _root();
    if (root == null) return null;
    final tasklyRoot = root.parent;
    final mediaRoot = Directory(
      '${tasklyRoot.path}${Platform.pathSeparator}Media',
    );
    if (!await mediaRoot.exists()) return null;
    final wanted = fileName.trim();
    if (wanted.isEmpty) return null;
    await for (final entity in mediaRoot.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          entity.uri.pathSegments.isNotEmpty &&
          entity.uri.pathSegments.last == wanted) {
        return entity.path;
      }
    }
    return null;
  }

  Future<void> clearChannel(int channelId) async {
    final file = await _file('channel_${channelId}_messages_v43.json');
    if (file != null && await file.exists()) await file.delete();
  }

  Future<void> clearAll() async {
    final root = await _root();
    if (root != null && await root.exists()) {
      await root.delete(recursive: true);
    }
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

  Future<Map<String, dynamic>> readRecoveryFiles() async {
    final result = <String, dynamic>{
      'conversations': [],
      'messages': {},
    };

    final dir = await getApplicationDocumentsDirectory();

    final recoveryDir = Directory(
      '${dir.path}/.cache',
    );

    if (!await recoveryDir.exists()) {
      return result;
    }

    final files = recoveryDir.listSync();

    for (final file in files) {
      if (file is! File) continue;

      if (!file.path.endsWith('.json')) continue;

      try {
        final data = jsonDecode(
          await file.readAsString(),
        );

        if (data['conversations'] != null) {
          result['conversations']
              .addAll(data['conversations']);
        }

        if (data['messages'] != null) {
          result['messages']
              .addAll(data['messages']);
        }

      } catch (_) {
        continue;
      }
    }

    return result;
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
}

DateTime _createdAt(Map<String, dynamic> row) =>
    DateTime.tryParse('${row['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);

int _asInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
