import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/chat_cache_service.dart';
import '../services/local_media_service.dart';
import '../core/supabase/taskly_supabase.dart';
import 'chat_provider.dart';

class CacheFirstChatProvider extends ChatProvider {
  CacheFirstChatProvider(TasklySupabase backend, LocalMediaService media)
      : super(backend, media);

  final ChatCacheService _recoveryCache = ChatCacheService();

  Future<List<ConversationItem>> _cachedConversations() async {
    try {
      return await _recoveryCache.readConversations();
    } catch (error) {
      debugPrint('TASKLY_CACHE_FIRST_CONVERSATIONS $error');
      return const [];
    }
  }

  Future<List<MessageItem>> _cachedMessages(int channelId, int profileId) async {
    try {
      final rows = await _recoveryCache.readMessages(channelId);
      return rows
          .where((row) => row['deleted_at'] == null)
          .map((row) => MessageItem.fromJson(row, currentProfileId: profileId))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (error) {
      debugPrint('TASKLY_CACHE_FIRST_MESSAGES channel=$channelId $error');
      return const [];
    }
  }

  void _mergeCachedMembers(int channelId, Iterable<MessageItem> items) {
    final byId = <int, AppUser>{
      for (final member in members[channelId] ?? const <AppUser>[]) member.id: member,
    };
    for (final item in items) {
      byId[item.sender.id] = item.sender;
    }
    if (byId.isNotEmpty) {
      members[channelId] = byId.values.toList(growable: false);
    }
  }

  @override
  Future<void> loadConversations() async {
    final cached = await _cachedConversations();
    if (cached.isNotEmpty) {
      conversations = cached;
      notifyListeners();
    }
    try {
      await super.loadConversations();
      if (conversations.isEmpty && cached.isNotEmpty) {
        conversations = cached;
      } else if (cached.isNotEmpty) {
        final byChannel = <int, ConversationItem>{
          for (final item in cached) item.channelId: item,
        };
        for (final item in conversations) {
          final old = byChannel[item.channelId];
          byChannel[item.channelId] = old == null
              ? item
              : item.copyWith(
                  name: item.name.isNotEmpty ? item.name : old.name,
                  lastMessage: item.lastMessage?.isNotEmpty == true
                      ? item.lastMessage
                      : old.lastMessage,
                  lastSenderName: item.lastSenderName?.isNotEmpty == true
                      ? item.lastSenderName
                      : old.lastSenderName,
                  lastMessageAt: item.lastMessageAt ?? old.lastMessageAt,
                );
        }
        conversations = byChannel.values.toList()
          ..sort((a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      }
    } catch (error) {
      debugPrint('TASKLY_CACHE_FIRST_LOAD $error');
      if (cached.isNotEmpty) {
        conversations = cached;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> openConversation(ConversationItem conversation) async {
    int profileId = currentProfileId ?? 0;
    if (profileId <= 0) {
      try {
        profileId = await backend.profileId();
        currentProfileId = profileId;
      } catch (error) {
        debugPrint('TASKLY_CACHE_FIRST_PROFILE_ID $error');
      }
    }

    final cached = await _cachedMessages(conversation.channelId, profileId);
    if (cached.isNotEmpty) {
      messages[conversation.channelId] = cached;
      hasOlderMessages[conversation.channelId] = cached.length >= 200;
      loadingMessages = false;
      _mergeCachedMembers(conversation.channelId, cached);
      notifyListeners();
    }

    try {
      await super.openConversation(conversation);
    } catch (error) {
      debugPrint('TASKLY_CACHE_FIRST_OPEN channel=${conversation.channelId} $error');
    }

    final current = messages[conversation.channelId] ?? const <MessageItem>[];
    if (current.isEmpty && cached.isNotEmpty) {
      messages[conversation.channelId] = cached;
      hasOlderMessages[conversation.channelId] = cached.length >= 200;
      loadingMessages = false;
      _mergeCachedMembers(conversation.channelId, cached);
      notifyListeners();
      return;
    }

    if (cached.isNotEmpty && current.isNotEmpty) {
      final byKey = <String, MessageItem>{};
      for (final item in cached) {
        byKey['${item.id}:${item.createdAt.toUtc().microsecondsSinceEpoch}'] = item;
      }
      for (final item in current) {
        byKey['${item.id}:${item.createdAt.toUtc().microsecondsSinceEpoch}'] = item;
      }
      final merged = byKey.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messages[conversation.channelId] = merged;
      _mergeCachedMembers(conversation.channelId, merged);
      loadingMessages = false;
      notifyListeners();
    }
  }
}
