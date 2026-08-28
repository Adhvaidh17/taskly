import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../files/attachment_policy.dart';
import '../utils/phone_number.dart';

class TasklySupabase {
  TasklySupabase(this.client);

  final SupabaseClient client;
  final Uuid _uuid = const Uuid();
  Map<String, dynamic>? _profileCache;

  String get authUserId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Not signed in');
    return id;
  }

  Future<Map<String, dynamic>> profile({bool refresh = false}) async {
    if (!refresh && _profileCache != null) {
      return Map<String, dynamic>.from(_profileCache!);
    }
    final row = await client
        .from('profiles')
        .select(
            'id,name,email,phone,phone_country_iso,avatar_url,about,last_seen_at')
        .eq('auth_user_id', authUserId)
        .single();
    _profileCache = Map<String, dynamic>.from(row);
    return Map<String, dynamic>.from(row);
  }

  Future<int> profileId() async => _int((await profile())['id']);

  Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String phone,
    String? phoneCountryIso,
    String? about,
  }) async {
    final resolvedCountryIso =
        phoneCountryIso ?? TasklyPhoneNumber.countryIso(phone);
    final normalizedPhone = TasklyPhoneNumber.normalize(
      phone,
      countryIso: resolvedCountryIso,
    );
    if (!TasklyPhoneNumber.isValid(normalizedPhone)) {
      throw const AuthException('A valid mobile number is required');
    }

    final cleanName = name.trim();
    final cleanAbout = about?.trim();
    final row = await client
        .from('profiles')
        .update({
          'name': cleanName,
          'phone': normalizedPhone,
          'phone_country_iso': (resolvedCountryIso ??
                  TasklyPhoneNumber.countryIso(normalizedPhone))
              ?.toUpperCase(),
          'about': cleanAbout?.isEmpty == true ? null : cleanAbout,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('auth_user_id', authUserId)
        .select(
            'id,name,email,phone,phone_country_iso,avatar_url,about,last_seen_at')
        .single();

    try {
      await client.auth.updateUser(
        UserAttributes(
          data: {
            'name': cleanName,
            'phone': normalizedPhone,
            'phone_country_iso': (resolvedCountryIso ??
                    TasklyPhoneNumber.countryIso(normalizedPhone))
                ?.toUpperCase(),
          },
        ),
      );
    } catch (_) {
      // The public profile is the source used by Taskly contacts and groups.
      // Auth metadata sync is helpful but must not block profile completion.
    }

    _profileCache = Map<String, dynamic>.from(row);
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> bootstrap() async {
    final profileRow = await profile(refresh: true);
    final groupsResult = await client.rpc('taskly_my_groups');
    final memberRows = await client
        .from('workspace_members')
        .select(
            'profiles!workspace_members_profile_id_fkey(id,name,email,phone,phone_country_iso,avatar_url,about),role')
        .eq('is_active', true);
    final clientRows = await client
        .from('clients')
        .select('id,name,colour,icon,workspace_id')
        .eq('is_active', true)
        .order('name');
    final channelRows = await client
        .from('channels')
        .select('id,name,type,icon,workspace_id')
        .eq('is_archived', false)
        .order('name');

    final memberMap = <int, Map<String, dynamic>>{};
    for (final raw in memberRows) {
      final item = Map<String, dynamic>.from(raw);
      final nestedProfile = item['profiles'];
      if (nestedProfile is! Map) {
        continue;
      }
      final profileJson = Map<String, dynamic>.from(nestedProfile);
      profileJson['role'] = item['role'];
      memberMap[_int(profileJson['id'])] = profileJson;
    }

    return {
      'profile': profileRow,
      'groups': groupsResult ?? const [],
      'members': memberMap.values.toList(),
      'clients': clientRows,
      'channels': channelRows,
    };
  }

  Future<List<Map<String, dynamic>>> groups() async {
    final result = await client.rpc('taskly_my_groups');
    return _mapList(result);
  }

  Future<Map<String, dynamic>> createGroup(
      String name, String description) async {
    final result = await client.rpc('taskly_create_group', params: {
      'p_name': name.trim(),
      'p_description': description.trim().isEmpty ? null : description.trim(),
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> joinGroup(String groupId) async {
    final result = await client
        .rpc('taskly_join_group', params: {'p_join_code': groupId.trim()});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> conversations() async {
    final result = await client.rpc('taskly_list_conversations');
    return _mapList(result);
  }

  Future<List<Map<String, dynamic>>> conversationMembers(int channelId) async {
    final result = await client.rpc('taskly_conversation_members',
        params: {'p_channel_id': channelId});
    return _mapList(result);
  }

  Future<Map<String, dynamic>> getOrCreateDirectChat(int otherProfileId) async {
    final result = await client.rpc(
      'taskly_get_or_create_direct_chat',
      params: {'p_other_profile_id': otherProfileId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> ensureSelfChat() async {
    final result = await client.rpc('taskly_ensure_self_chat');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> findContacts({
    required List<String> phoneHashes,
    required List<String> emailHashes,
  }) async {
    final result = await client.rpc('taskly_find_contacts', params: {
      'p_phone_hashes': phoneHashes,
      'p_email_hashes': emailHashes,
    });
    return _mapList(result);
  }

  Future<List<Map<String, dynamic>>> searchPeopleByPhone(
    String phoneQuery, {
    int limit = 20,
  }) async {
    final result = await client.rpc('taskly_search_people_by_phone', params: {
      'p_phone_query': phoneQuery.trim(),
      'p_limit': limit,
    });
    return _mapList(result);
  }

  static const String _messageBaseSelect = '''
    id,workspace_id,channel_id,body,type,created_at,edited_at,deleted_at,
    mentioned_profile_ids,attachment_bucket,attachment_path,attachment_name,
    attachment_mime_type,attachment_size_bytes,is_pinned,reply_to_message_id,
    forwarded_from_message_id,shared_contact_profile_id,shared_contact_name,
    shared_contact_phone,shared_contact_email
  ''';

  Future<List<Map<String, dynamic>>> messages(
    int channelId, {
    int? beforeId,
    int limit = 80,
  }) async {
    final result = await client.rpc(
      'taskly_channel_messages_v42',
      params: {
        'p_channel_id': channelId,
        'p_before_id': beforeId,
        'p_limit': limit.clamp(20, 120).toInt(),
      },
    );
    // Media stays device-local; the chat page carries only metadata until a
    // media item is displayed/downloaded. Initial chat load is intentionally
    // paged rather than expanding hundreds of messages at once.
    return _mapList(result);
  }

  Future<Uint8List> downloadMessageAttachment({
    required String bucket,
    required String path,
  }) async {
    if (bucket != 'database') {
      throw StateError('This attachment is no longer available.');
    }

    final result = await client.rpc(
      'taskly_get_message_attachment_db',
      params: {'p_attachment_path': path},
    );
    final encoded = result?.toString() ?? '';
    if (encoded.isEmpty) {
      throw StateError('This attachment is no longer available.');
    }
    return Uint8List.fromList(base64Decode(encoded));
  }

  Future<Map<String, dynamic>?> message(int messageId) async {
    final result = await client.rpc(
      'taskly_message_v42',
      params: {'p_message_id': messageId},
    );
    if (result == null || result is! Map) return null;
    return Map<String, dynamic>.from(result);
  }

  Stream<int> chatChanges(int channelId, int workspaceId) {
    late final StreamController<int> controller;
    RealtimeChannel? channel;
    controller = StreamController<int>(
      onListen: () {
        channel = client
            .channel('taskly-chat-v42-$channelId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'channel_id',
                value: channelId,
              ),
              callback: (payload) {
                final row = payload.newRecord.isNotEmpty
                    ? payload.newRecord
                    : payload.oldRecord;
                controller.add(_int(row['id']));
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'task_suggestions',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'workspace_id',
                value: workspaceId,
              ),
              callback: (payload) {
                final row = payload.newRecord.isNotEmpty
                    ? payload.newRecord
                    : payload.oldRecord;
                controller.add(_int(row['message_id']));
              },
            )..subscribe();
      },
      onCancel: () async {
        final active = channel;
        if (active != null) await client.removeChannel(active);
      },
    );
    return controller.stream;
  }

  Future<Map<String, dynamic>> sendMessage({
    required int workspaceId,
    required int channelId,
    required String body,
    List<int> mentionedProfileIds = const [],
    int? replyToMessageId,
  }) async {
    final sender = await profile();
    final inserted = await client
        .from('messages')
        .insert({
          'workspace_id': workspaceId,
          'channel_id': channelId,
          'sender_profile_id': _int(sender['id']),
          'body': body.trim(),
          'type': 'text',
          'mentioned_profile_ids': mentionedProfileIds,
          'reply_to_message_id': replyToMessageId,
          'client_mutation_id': _uuid.v4(),
        })
        .select(_messageBaseSelect)
        .single();

    final row = Map<String, dynamic>.from(inserted);
    row['sender'] = Map<String, dynamic>.from(sender);
    row['reply_to'] = null;
    row['suggestion'] = null;
    row['message_reactions'] = const <Map<String, dynamic>>[];

    return row;
  }

  Future<Map<String, dynamic>?> analyseMessage(int messageId) async {
    final response = await client.functions.invoke(
      'analyse-task-message',
      body: {
        'message_id': messageId,
        'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );
    debugPrint(
      'TASKLY_AI_RESPONSE messageId=$messageId '
      'status=${response.status} data=${response.data}',
    );
    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        'Edge Function HTTP ${response.status}: ${response.data}',
      );
    }
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return null;
  }

  Future<void> resetTaskAnalysis(int messageId) async {
    final result = await client.rpc(
      'taskly_retry_message_ai_v32',
      params: {'p_message_id': messageId},
    );
    if (result is Map && result['reset'] == false) {
      throw Exception(result['reason'] ?? 'Task analysis cannot be retried');
    }
  }

  Future<void> editMessage(int messageId, String body) async {
    await client.from('messages').update({
      'body': body.trim(),
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId);
  }

  Future<void> deleteMessage(int messageId) async {
    await client.rpc(
      'taskly_delete_message',
      params: {'p_message_id': messageId},
    );
  }

  Future<void> toggleMessagePin(int messageId, bool pinned) async {
    await client
        .from('messages')
        .update({'is_pinned': pinned}).eq('id', messageId);
  }

  Future<void> toggleReaction(int messageId, String emoji) async {
    await client.rpc('taskly_toggle_reaction', params: {
      'p_message_id': messageId,
      'p_emoji': emoji,
    });
  }

  Future<void> markChannelRead(int channelId) async {
    await client
        .rpc('taskly_mark_channel_read', params: {'p_channel_id': channelId});
  }

  Future<void> setConversationPreferences(
    int channelId, {
    bool? muted,
    bool? archived,
  }) async {
    await client.rpc('taskly_set_conversation_preferences', params: {
      'p_channel_id': channelId,
      'p_is_muted': muted,
      'p_is_archived': archived,
    });
  }

  Future<void> clearChat(int channelId) async {
    await client.rpc('taskly_clear_chat', params: {'p_channel_id': channelId});
  }

  Future<void> deleteChat(int channelId) async {
    await client.rpc('taskly_delete_chat', params: {'p_channel_id': channelId});
  }

  Future<Map<String, dynamic>> groupAdminState(int workspaceId) async {
    final result = await client.rpc(
      'taskly_group_admin_state',
      params: {'p_workspace_id': workspaceId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> updateGroup({
    required int workspaceId,
    String? name,
    String? description,
    bool? onlyAdminsCanSend,
    bool? onlyAdminsCanEdit,
    bool? approveNewMembers,
  }) async {
    final result = await client.rpc('taskly_update_group', params: {
      'p_workspace_id': workspaceId,
      'p_name': name,
      'p_description': description,
      'p_only_admins_can_send': onlyAdminsCanSend,
      'p_only_admins_can_edit': onlyAdminsCanEdit,
      'p_approve_new_members': approveNewMembers,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> resetGroupJoinCode(int workspaceId) async {
    final result = await client.rpc(
      'taskly_reset_join_code',
      params: {'p_workspace_id': workspaceId},
    );
    return '$result';
  }

  Future<void> setGroupMemberRole({
    required int workspaceId,
    required int profileId,
    required String role,
  }) async {
    await client.rpc('taskly_set_member_role', params: {
      'p_workspace_id': workspaceId,
      'p_profile_id': profileId,
      'p_role': role,
    });
  }

  Future<void> removeGroupMember({
    required int workspaceId,
    required int profileId,
  }) async {
    await client.rpc('taskly_remove_group_member', params: {
      'p_workspace_id': workspaceId,
      'p_profile_id': profileId,
    });
  }

  Future<Map<String, dynamic>> addGroupMemberByIdentifier({
    required int workspaceId,
    required String identifier,
  }) async {
    final result =
        await client.rpc('taskly_add_group_member_by_identifier', params: {
      'p_workspace_id': workspaceId,
      'p_identifier': identifier.trim(),
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> addGroupMemberByProfileId({
    required int workspaceId,
    required int profileId,
  }) async {
    final result = await client.rpc(
      'taskly_add_group_member_by_profile_id',
      params: {
        'p_workspace_id': workspaceId,
        'p_profile_id': profileId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> reviewJoinRequest(int requestId, bool approve) async {
    await client.rpc('taskly_review_join_request', params: {
      'p_request_id': requestId,
      'p_approve': approve,
    });
  }

  Future<String> leaveGroup(int workspaceId) async {
    final result = await client.rpc(
      'taskly_leave_group',
      params: {'p_workspace_id': workspaceId},
    );
    return '$result';
  }

  Future<void> deleteGroup(int workspaceId) async {
    await client.rpc(
      'taskly_delete_group',
      params: {'p_workspace_id': workspaceId},
    );
  }

  Future<void> updateSuggestion(
      int suggestionId, Map<String, dynamic> values) async {
    await client.from('task_suggestions').update(values).eq('id', suggestionId);
  }

  Future<int> confirmSuggestion(int suggestionId) async {
    final value = await client.rpc(
      'confirm_task_suggestion',
      params: {'p_suggestion_id': suggestionId},
    );
    return _int(value);
  }

  Future<void> dismissSuggestion(int suggestionId) async {
    await client.rpc(
      'taskly_dismiss_task_suggestion',
      params: {'p_suggestion_id': suggestionId},
    );
  }

  Future<Map<String, dynamic>> uploadMessageAttachment({
    required int workspaceId,
    required int channelId,
    required String filePath,
    int? replyToMessageId,
  }) async {
    final file = File(filePath);
    final validation = await AttachmentPolicy.validate(filePath);
    if (!validation.isValid) {
      throw ArgumentError(validation.error ?? 'Unsupported attachment');
    }

    final sender = await profile();
    final name = file.uri.pathSegments.last;
    final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
    final attachmentPath = _uuid.v4();
    final bytes = await file.readAsBytes();

    Map<String, dynamic>? insertedRow;
    try {
      final inserted = await client
          .from('messages')
          .insert({
            'workspace_id': workspaceId,
            'channel_id': channelId,
            'sender_profile_id': _int(sender['id']),
            'body': name,
            'type': mimeType.startsWith('image/')
                ? 'image'
                : mimeType.startsWith('video/')
                    ? 'video'
                    : 'file',
            'reply_to_message_id': replyToMessageId,
            'attachment_bucket': 'database',
            'attachment_path': attachmentPath,
            'attachment_name': name,
            'attachment_mime_type': mimeType,
            'attachment_size_bytes': bytes.length,
            'client_mutation_id': _uuid.v4(),
          })
          .select(_messageBaseSelect)
          .single();

      insertedRow = Map<String, dynamic>.from(inserted);

      await client.rpc(
        'taskly_store_message_attachment_db',
        params: {
          'p_attachment_path': attachmentPath,
          'p_data_base64': base64Encode(bytes),
        },
      );
    } catch (_) {
      if (insertedRow != null) {
        try {
          await client
              .from('messages')
              .delete()
              .eq('id', _int(insertedRow['id']));
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      rethrow;
    }

    final row = insertedRow;
    row['sender'] = Map<String, dynamic>.from(sender);
    row['reply_to'] = null;
    row['suggestion'] = null;
    row['message_reactions'] = const <Map<String, dynamic>>[];
    return row;
  }

  Future<Map<String, dynamic>> sendContactMessage({
    required int workspaceId,
    required int channelId,
    required String name,
    String? phone,
    String? email,
    int? profileId,
    int? replyToMessageId,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Contact name is required');
    final sender = await profile();
    final inserted = await client
        .from('messages')
        .insert({
          'workspace_id': workspaceId,
          'channel_id': channelId,
          'sender_profile_id': _int(sender['id']),
          'body': name.trim(),
          'type': 'contact',
          'reply_to_message_id': replyToMessageId,
          'shared_contact_profile_id': profileId,
          'shared_contact_name': name.trim(),
          'shared_contact_phone':
              phone?.trim().isEmpty == true ? null : phone?.trim(),
          'shared_contact_email':
              email?.trim().isEmpty == true ? null : email?.trim(),
          'client_mutation_id': _uuid.v4(),
        })
        .select(_messageBaseSelect)
        .single();
    final row = Map<String, dynamic>.from(inserted);
    row['sender'] = Map<String, dynamic>.from(sender);
    row['reply_to'] = null;
    row['suggestion'] = null;
    row['message_reactions'] = const <Map<String, dynamic>>[];
    return row;
  }

  Future<Map<String, dynamic>> forwardMessage({
    required int targetWorkspaceId,
    required int targetChannelId,
    required Map<String, dynamic> source,
  }) async {
    final sender = await profile();
    // Forwarding reuses the existing database attachment reference instead of
    // duplicating the binary bytes. This keeps forwarding metadata-only.
    final sourcePath = '${source['attachment_path'] ?? ''}'.trim();
    final bucket = sourcePath.isEmpty
        ? null
        : '${source['attachment_bucket'] ?? 'task-files'}';
    final inserted = await client
        .from('messages')
        .insert({
          'workspace_id': targetWorkspaceId,
          'channel_id': targetChannelId,
          'sender_profile_id': _int(sender['id']),
          'body': '${source['body'] ?? ''}',
          'type': '${source['type'] ?? 'text'}',
          'attachment_bucket': bucket,
          'attachment_path': sourcePath.isEmpty ? null : sourcePath,
          'attachment_name': source['attachment_name'],
          'attachment_mime_type': source['attachment_mime_type'],
          'attachment_size_bytes': source['attachment_size_bytes'],
          'forwarded_from_message_id': _int(source['id']),
          'shared_contact_profile_id': source['shared_contact_profile_id'],
          'shared_contact_name': source['shared_contact_name'],
          'shared_contact_phone': source['shared_contact_phone'],
          'shared_contact_email': source['shared_contact_email'],
          'client_mutation_id': _uuid.v4(),
        })
        .select(_messageBaseSelect)
        .single();
    final row = Map<String, dynamic>.from(inserted);
    row['sender'] = Map<String, dynamic>.from(sender);
    row['reply_to'] = null;
    row['suggestion'] = null;
    row['message_reactions'] = const <Map<String, dynamic>>[];
    return row;
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    required String deviceId,
  }) async {
    await client.rpc('taskly_register_device_token_v40', params: {
      'p_token': token,
      'p_platform': platform,
      'p_device_id': deviceId,
    });
  }

  Future<void> unregisterDeviceToken(String token) async {
    await client.rpc('taskly_unregister_device_token_v40', params: {
      'p_token': token,
    });
  }

  Future<void> setPushNotificationsEnabled(bool enabled) async {
    await client.rpc('taskly_set_push_enabled_v40', params: {
      'p_enabled': enabled,
    });
  }

  // Task lists deliberately fetch only fields rendered by TaskCard. Full
  // comments/history/attachments/tags are loaded only when a task is opened.
  // This keeps the Tasks tab fast even for large groups.
  static const String _taskListSelect = '''
    id,workspace_id,title,status,priority,deadline,version,created_at,updated_at,
    workspace:workspaces!tasks_workspace_id_fkey(id,name,kind),
    creator:profiles!tasks_creator_profile_id_fkey(id,name,email,phone,avatar_url,about),
    assignee:profiles!tasks_assignee_id_fkey(id,name,email,phone,avatar_url,about),
    client:clients!tasks_client_id_fkey(id,name,colour,icon),
    channel:channels!tasks_channel_id_fkey(id,name,icon,workspace_id),
    subtasks(id,title,is_done,position,version)
  ''';

  static const String _taskDetailSelect = '''
    id,workspace_id,title,description,status,priority,deadline,origin_text,
    source_type,reminder_enabled,reminder_minutes_before,version,created_at,updated_at,
    workspace:workspaces!tasks_workspace_id_fkey(id,name,kind),
    creator:profiles!tasks_creator_profile_id_fkey(id,name,email,phone,avatar_url,about),
    assignee:profiles!tasks_assignee_id_fkey(id,name,email,phone,avatar_url,about),
    client:clients!tasks_client_id_fkey(id,name,colour,icon),
    channel:channels!tasks_channel_id_fkey(id,name,icon,workspace_id),
    subtasks(id,title,is_done,position,version,created_at),
    task_comments(
      id,body,created_at,
      user:profiles!task_comments_profile_id_fkey(id,name,email,phone,avatar_url,about)
    ),
    task_status_histories(
      id,from_status,to_status,created_at,
      user:profiles!task_status_histories_changed_by_profile_id_fkey(id,name,email,phone,avatar_url,about)
    ),
    attachments(
      id,bucket,path,original_name,mime_type,size_bytes,created_at,
      uploaded_by_profile_id,removed_at,removed_by_profile_id
    ),
    task_tags(tags(name))
  ''';

  Future<List<Map<String, dynamic>>> tasks({
    String search = '',
    String? status,
    String? priority,
    int? assigneeId,
    int? clientId,
    bool myTasks = false,
    bool assignedByMe = false,
    bool overdue = false,
    String sort = 'deadline',
  }) async {
    // RLS already enforces Taskly's involved-task visibility. Avoid the old
    // two-query visible-ID list, which became expensive for large accounts.
    var query = client
        .from('tasks')
        .select(_taskListSelect)
        .isFilter('deleted_at', null);
    if (search.trim().isNotEmpty) {
      query = query.ilike('title', '%${search.trim()}%');
    }
    if (status != null) query = query.eq('status', status);
    if (priority != null) query = query.eq('priority', priority);
    if (assigneeId != null) query = query.eq('assignee_id', assigneeId);
    if (clientId != null) query = query.eq('client_id', clientId);
    final me = (myTasks || assignedByMe) ? await profileId() : null;
    if (myTasks) query = query.eq('assignee_id', me!);
    if (assignedByMe) query = query.eq('creator_profile_id', me!);
    if (overdue) {
      query = query
          .neq('status', 'done')
          .lt('deadline', DateTime.now().toUtc().toIso8601String());
    }

    final rows = switch (sort) {
      'created' => await query.order('created_at', ascending: false).limit(200),
      'priority' => await query
          .order('priority')
          .order('deadline', nullsFirst: false)
          .limit(200),
      _ => await query
          .order('deadline', nullsFirst: false)
          .order('created_at', ascending: false)
          .limit(200),
    };
    return _mapList(rows).map(_normaliseTask).toList();
  }

  Future<List<Map<String, dynamic>>> groupTasks(int workspaceId) async {
    final rows = await client
        .from('tasks')
        .select(_taskListSelect)
        .eq('workspace_id', workspaceId)
        .isFilter('deleted_at', null)
        .order('status')
        .order('deadline', nullsFirst: false)
        .order('created_at', ascending: false)
        .limit(300);
    return _mapList(rows).map(_normaliseTask).toList();
  }

  Stream<void> taskChanges() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel = client
            .channel(
                'taskly-tasks-v42-${client.auth.currentUser?.id ?? 'anon'}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'tasks',
              callback: (_) => controller.add(null),
            )..subscribe();
      },
      onCancel: () async {
        final active = channel;
        if (active != null) await client.removeChannel(active);
      },
    );
    return controller.stream;
  }

  Future<List<Map<String, dynamic>>> reminderTasks() async {
    final me = await profileId();
    final rows = await client
        .from('tasks')
        .select(_taskListSelect)
        .eq('assignee_id', me)
        .eq('reminder_enabled', true)
        .neq('status', 'done')
        .gt('deadline', DateTime.now().toUtc().toIso8601String())
        .isFilter('deleted_at', null)
        .order('deadline');
    return _mapList(rows).map(_normaliseTask).toList();
  }

  Future<Map<String, dynamic>> task(int id) async {
    final row = await client
        .from('tasks')
        .select(_taskDetailSelect)
        .eq('id', id)
        .single();
    return _normaliseTask(Map<String, dynamic>.from(row));
  }

  Future<Map<String, dynamic>> createTask(Map<String, dynamic> values) async {
    final tags = List<String>.from(values.remove('tags') ?? const []);
    final subtasks =
        List<Map<String, dynamic>>.from(values.remove('subtasks') ?? const []);
    final channelId = _int(values['channel_id']);
    final channel = await client
        .from('channels')
        .select('workspace_id')
        .eq('id', channelId)
        .single();
    values['workspace_id'] = _int(channel['workspace_id']);
    values['creator_profile_id'] = await profileId();
    values['client_mutation_id'] ??= _uuid.v4();

    final row = await client.from('tasks').insert(values).select('id').single();
    final taskId = _int(row['id']);
    if (subtasks.isNotEmpty) {
      await client.from('subtasks').insert([
        for (var index = 0; index < subtasks.length; index++)
          {
            'task_id': taskId,
            'title': subtasks[index]['title'],
            'position': index,
            'client_mutation_id': _uuid.v4(),
          },
      ]);
    }
    await _syncTags(taskId, _int(channel['workspace_id']), tags);
    return task(taskId);
  }

  Future<Map<String, dynamic>> updateTask(
      int id, Map<String, dynamic> values) async {
    final tags = values.remove('tags');
    values['version'] = (values.remove('version') as int? ?? 0) + 1;
    await client.from('tasks').update(values).eq('id', id);
    if (tags is List) {
      final row = await client
          .from('tasks')
          .select('workspace_id')
          .eq('id', id)
          .single();
      await _syncTags(
          id, _int(row['workspace_id']), tags.map((item) => '$item').toList());
    }
    return task(id);
  }

  Future<Map<String, dynamic>> changeTaskStatus(int id, String status) async {
    await client.rpc('taskly_change_task_status', params: {
      'p_task_id': id,
      'p_status': status,
    });
    return task(id);
  }

  Future<void> deleteTask(int id) async {
    await client.from('tasks').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<Map<String, dynamic>> addSubtask(int taskId, String title) async {
    final rows = await client
        .from('subtasks')
        .select('position')
        .eq('task_id', taskId)
        .order('position', ascending: false)
        .limit(1);
    final position =
        (rows as List).isEmpty ? 0 : _int((rows.first as Map)['position']) + 1;
    await client.from('subtasks').insert({
      'task_id': taskId,
      'title': title.trim(),
      'position': position,
      'client_mutation_id': _uuid.v4(),
    });
    return task(taskId);
  }

  Future<Map<String, dynamic>> updateSubtask(
    int taskId,
    int subtaskId,
    bool done,
    int version,
  ) async {
    await client.from('subtasks').update({
      'is_done': done,
      'version': version + 1,
      'completed_at': done ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', subtaskId);
    return task(taskId);
  }

  Future<void> deleteSubtask(int id) async {
    await client.from('subtasks').delete().eq('id', id);
  }

  Future<Map<String, dynamic>> addComment(int taskId, String body) async {
    await client.from('task_comments').insert({
      'task_id': taskId,
      'profile_id': await profileId(),
      'body': body.trim(),
      'client_mutation_id': _uuid.v4(),
    });
    return task(taskId);
  }

  Future<Map<String, dynamic>> uploadAttachment(
      int taskId, String filePath) async {
    final file = File(filePath);
    final validation = await AttachmentPolicy.validate(filePath);
    if (!validation.isValid) {
      throw ArgumentError(validation.error ?? 'Unsupported attachment');
    }

    final taskRow = await client
        .from('tasks')
        .select('workspace_id')
        .eq('id', taskId)
        .single();

    final workspaceId = _int(taskRow['workspace_id']);
    final name = file.uri.pathSegments.last;
    final mimeType = lookupMimeType(name) ?? 'application/octet-stream';
    final attachmentPath = _uuid.v4();
    final bytes = await file.readAsBytes();

    Map<String, dynamic>? attachmentRow;
    try {
      final inserted = await client
          .from('attachments')
          .insert({
            'workspace_id': workspaceId,
            'task_id': taskId,
            'uploaded_by_profile_id': await profileId(),
            'bucket': 'database',
            'path': attachmentPath,
            'original_name': name,
            'mime_type': mimeType,
            'size_bytes': bytes.length,
          })
          .select('id')
          .single();

      attachmentRow = Map<String, dynamic>.from(inserted);

      await client.rpc(
        'taskly_store_task_attachment_db',
        params: {
          'p_attachment_id': _int(attachmentRow['id']),
          'p_data_base64': base64Encode(bytes),
        },
      );
    } catch (_) {
      if (attachmentRow != null) {
        try {
          await client
              .from('attachments')
              .delete()
              .eq('id', _int(attachmentRow['id']));
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      rethrow;
    }

    return task(taskId);
  }

  Future<Uint8List> downloadTaskAttachment({
    required String bucket,
    required String path,
  }) async {
    if (bucket != 'database') {
      throw StateError('This attachment is no longer available.');
    }

    final result = await client.rpc(
      'taskly_get_task_attachment_db',
      params: {'p_attachment_path': path},
    );
    final encoded = result?.toString() ?? '';
    if (encoded.isEmpty) {
      throw StateError('This attachment is no longer available.');
    }
    return Uint8List.fromList(base64Decode(encoded));
  }

  Future<Map<String, dynamic>> removeTaskAttachment(
    int taskId,
    Map<String, dynamic> attachment,
  ) async {
    final attachmentId = _int(attachment['id']);
    if (attachmentId <= 0) throw ArgumentError('Invalid attachment');

    await client.rpc(
      'taskly_remove_task_attachment_db',
      params: {'p_attachment_id': attachmentId},
    );
    return task(taskId);
  }

  Future<List<Map<String, dynamic>>> groupSharedContent(
    int channelId, {
    String kind = 'media',
    int? beforeId,
    int limit = 60,
  }) async {
    final result = await client.rpc('taskly_group_shared_content_v43', params: {
      'p_channel_id': channelId,
      'p_kind': kind,
      'p_before_id': beforeId,
      'p_limit': limit.clamp(7, 100).toInt(),
    });
    return _mapList(result);
  }

  Future<List<int>> removedTaskAttachmentIdsForMe() async {
    final result = await client.rpc('taskly_removed_attachment_ids_for_me_v43');
    return (result as List? ?? const [])
        .map((value) => _int(value))
        .where((id) => id > 0)
        .toList(growable: false);
  }

  Stream<int> taskAttachmentRemovalChanges(int profileId) {
    late final StreamController<int> controller;
    RealtimeChannel? channel;
    controller = StreamController<int>(
      onListen: () {
        channel = client
            .channel('taskly-attachment-removals-v43-$profileId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'attachments',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'uploaded_by_profile_id',
                value: profileId,
              ),
              callback: (payload) {
                final row = payload.newRecord;
                if (row['removed_at'] != null) {
                  final id = _int(row['id']);
                  if (id > 0) controller.add(id);
                }
              },
            )..subscribe();
      },
      onCancel: () async {
        final active = channel;
        if (active != null) await client.removeChannel(active);
      },
    );
    return controller.stream;
  }

  Future<Map<String, dynamic>> dashboard() async {
    final result = await client.rpc('taskly_dashboard');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> notifications() async {
    final rows = await client.from('notifications').select('''
          id,type,title,body,is_read,created_at,task_id,workspace_id,channel_id,message_id,
          actor:profiles!notifications_actor_profile_id_fkey(id,name,email,phone,avatar_url,about)
        ''').order('created_at', ascending: false).limit(100);
    return _mapList(rows);
  }

  Stream<void> notificationChanges() {
    final profileId = _int(_profileCache?['id']);
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel = client
            .channel('taskly-notifications-v42-$profileId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'profile_id',
                value: profileId,
              ),
              callback: (_) => controller.add(null),
            )..subscribe();
      },
      onCancel: () async {
        final active = channel;
        if (active != null) await client.removeChannel(active);
      },
    );
    return controller.stream;
  }

  Future<void> markNotificationRead(int id) async {
    await client.rpc('taskly_mark_notification_read',
        params: {'p_notification_id': id});
  }

  Future<void> markAllNotificationsRead() async {
    await client.rpc('taskly_mark_all_notifications_read');
  }

  Future<void> _syncTags(
      int taskId, int workspaceId, List<String> names) async {
    await client.from('task_tags').delete().eq('task_id', taskId);
    for (final raw in names.toSet()) {
      final name = raw.trim().toLowerCase();
      if (name.isEmpty) continue;
      final rows = await client
          .from('tags')
          .select('id')
          .eq('workspace_id', workspaceId)
          .eq('name', name)
          .limit(1);
      int tagId;
      if ((rows as List).isEmpty) {
        final inserted = await client
            .from('tags')
            .insert({'workspace_id': workspaceId, 'name': name})
            .select('id')
            .single();
        tagId = _int(inserted['id']);
      } else {
        tagId = _int((rows.first as Map)['id']);
      }
      await client
          .from('task_tags')
          .insert({'task_id': taskId, 'tag_id': tagId});
    }
  }

  Map<String, dynamic> _normaliseTask(Map<String, dynamic> row) {
    final workspace = row['workspace'] is Map
        ? Map<String, dynamic>.from(row['workspace'] as Map)
        : <String, dynamic>{};
    row['workspace_name'] = workspace['name'];
    row['workspace_kind'] = workspace['kind'];
    final channel = row['channel'];
    if (channel is Map) {
      final channelMap = Map<String, dynamic>.from(channel);
      channelMap['workspace_name'] = workspace['name'];
      channelMap['workspace_kind'] = workspace['kind'];
      row['channel'] = channelMap;
    }
    row['comments'] = row.remove('task_comments') ?? const [];
    row['status_history'] = row.remove('task_status_histories') ?? const [];
    final links = row.remove('task_tags') as List? ?? const [];
    row['tags'] = links
        .map((item) => item is Map && item['tags'] is Map
            ? (item['tags'] as Map)['name']
            : null)
        .whereType<Object>()
        .map((item) => '$item')
        .toList();
    return row;
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value == null) return [];
    return (value as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
}
