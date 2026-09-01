import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/channel.dart';
import 'chat_cache_service.dart';

class RecoveredChatCacheService extends ChatCacheService {
  static const List<String> _assets = [
    '../Android_media_.cache/0eca4074-e98b-4407-845e-75291e9cb8e3_conversations_v43.json',
    '../Android_media_.cache/1088ab35-0c03-4a73-97a5-b82a6688f8b7_conversations_v43.json',
    '../Android_media_.cache/0eca4074-e98b-4407-845e-75291e9cb8e3_channel_4_messages_v43.json',
    '../Android_media_.cache/0eca4074-e98b-4407-845e-75291e9cb8e3_channel_21_messages_v43.json',
    '../Android_media_.cache/0eca4074-e98b-4407-845e-75291e9cb8e3_channel_22_messages_v43.json',
    '../Android_media_.cache/0eca4074-e98b-4407-845e-75291e9cb8e3_channel_25_messages_v43.json',
    '../Android_media_.cache/1088ab35-0c03-4a73-97a5-b82a6688f8b7_channel_4_messages_v43.json',
    '../Android_media_.cache/1088ab35-0c03-4a73-97a5-b82a6688f8b7_channel_23_messages_v43.json',
  ];

  Future<String?> _asset(String path) async {
    final candidates = <String>[
      path,
      path.replaceFirst('../', ''),
      path.replaceFirst('../Android_media_.cache/', 'Android_media_.cache/'),
    ];
    for (final candidate in candidates.toSet()) {
      try {
        return await rootBundle.loadString(candidate);
      } catch (_) {}
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _rows(String path) async {
    try {
      final text = await _asset(path);
      if (text == null) return const [];
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<ConversationItem>> readConversations() async {
    final byChannel = <int, Map<String, dynamic>>{};
    for (final item in await super.readConversations()) {
      byChannel[item.channelId] = _conversationJson(item);
    }
    for (final asset in _assets.where((p) => p.endsWith('_conversations_v43.json'))) {
      for (final row in await _rows(asset)) {
        final id = _int(row['channel_id']);
        if (id <= 0) continue;
        final old = byChannel[id];
        if (old == null || _date(row['last_message_at']).isAfter(_date(old['last_message_at']))) {
          byChannel[id] = row;
        }
      }
    }
    final result = byChannel.values
        .map(ConversationItem.fromJson)
        .where((item) => item.channelId > 0)
        .toList()
      ..sort((a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    if (result.isNotEmpty) {
      await super.writeConversations(result);
    }
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> readMessages(int channelId) async {
    final merged = <String, Map<String, dynamic>>{};
    for (final row in await super.readMessages(channelId)) {
      merged[_key(row)] = row;
    }
    final marker = '_channel_${channelId}_messages_v43.json';
    for (final asset in _assets.where((p) => p.contains(marker))) {
      for (final row in await _rows(asset)) {
        merged[_key(row)] = row;
      }
    }
    final result = merged.values.toList()
      ..sort((a, b) => _date(a['created_at']).compareTo(_date(b['created_at'])));
    if (result.isNotEmpty) {
      await super.writeMessages(channelId, result);
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

  String _key(Map<String, dynamic> row) {
    final id = _int(row['id']);
    if (id > 0) return 'id:$id';
    final client = '${row['client_message_id'] ?? ''}'.trim();
    return client.isEmpty ? jsonEncode(row) : 'client:$client';
  }

  DateTime _date(Object? value) => DateTime.tryParse('$value') ?? DateTime.fromMillisecondsSinceEpoch(0);
  int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}