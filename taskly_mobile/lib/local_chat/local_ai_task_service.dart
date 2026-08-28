import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_chat_database.dart';

class LocalAiTaskService {
  LocalAiTaskService({
    required this.client,
    required this.database,
  });

  final SupabaseClient client;
  final LocalChatDatabase database;

  Future<Map<String, dynamic>?> analyse({
    required String clientMessageId,
    required int workspaceId,
    required int channelId,
    required String text,
    required int timezoneOffsetMinutes,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Transient request only. The Edge Function does not insert this chat body
    // into Taskly's database.
    final response = await client.functions.invoke(
      'analyse-local-task',
      body: {
        'client_message_id': clientMessageId,
        'workspace_id': workspaceId,
        'channel_id': channelId,
        'text': trimmed,
        'timezone_offset_minutes': timezoneOffsetMinutes,
      },
    );

    if (response.status < 200 || response.status >= 300) return null;
    final data = response.data;
    if (data is! Map) return null;

    final payload = Map<String, dynamic>.from(data);
    if (payload['is_task'] != true) return null;

    await database.saveTaskSuggestion(
      clientMessageId,
      channelId,
      payload,
    );
    return payload;
  }

  Future<void> dismiss(String clientMessageId) {
    return database.dismissTaskSuggestion(clientMessageId);
  }
}
