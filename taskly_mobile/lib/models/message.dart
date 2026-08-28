import 'user.dart';

class TaskSuggestionItem {
  const TaskSuggestionItem({
    required this.id,
    required this.title,
    required this.priority,
    required this.status,
    required this.actionType,
    this.description,
    this.deadline,
    this.assignee,
    this.confidence,
    this.aiReason,
    this.targetTaskId,
  });

  final int id;
  final String title;
  final String? description;
  final String priority;
  final String status;
  final String actionType;
  final DateTime? deadline;
  final AppUser? assignee;
  final double? confidence;
  final String? aiReason;
  final int? targetTaskId;

  bool get isPending => status == 'pending';

  factory TaskSuggestionItem.fromJson(Map<String, dynamic> json) =>
      TaskSuggestionItem(
        id: _int(json['id']),
        title: '${json['title'] ?? ''}',
        description: json['description'] as String?,
        priority: '${json['priority'] ?? 'medium'}',
        status: '${json['status'] ?? 'pending'}',
        actionType: '${json['action_type'] ?? 'create'}',
        deadline: DateTime.tryParse('${json['deadline'] ?? ''}')?.toLocal(),
        assignee: json['assignee'] is Map
            ? AppUser.fromJson(Map<String, dynamic>.from(json['assignee']))
            : null,
        confidence: json['confidence'] == null
            ? null
            : double.tryParse('${json['confidence']}'),
        aiReason: json['ai_reason'] as String?,
        targetTaskId: json['target_task_id'] == null
            ? null
            : _int(json['target_task_id']),
      );
}

class MessageReaction {
  const MessageReaction({
    required this.emoji,
    required this.count,
    required this.mine,
  });

  final String emoji;
  final int count;
  final bool mine;
}

class MessageItem {
  const MessageItem({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.body,
    required this.type,
    required this.sender,
    required this.createdAt,
    this.replyTo,
    this.suggestion,
    this.mentionedProfileIds = const [],
    this.reactions = const [],
    this.editedAt,
    this.deletedAt,
    this.attachmentBucket,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentMimeType,
    this.attachmentSizeBytes,
    this.attachmentUrl,
    this.forwardedFromMessageId,
    this.sharedContactProfileId,
    this.sharedContactName,
    this.sharedContactPhone,
    this.sharedContactEmail,
    this.isPinned = false,
  });

  final int id;
  final int workspaceId;
  final int channelId;
  final String body;
  final String type;
  final AppUser sender;
  final DateTime createdAt;
  final MessageItem? replyTo;
  final TaskSuggestionItem? suggestion;
  final List<int> mentionedProfileIds;
  final List<MessageReaction> reactions;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? attachmentBucket;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentMimeType;
  final int? attachmentSizeBytes;
  final String? attachmentUrl;
  final int? forwardedFromMessageId;
  final int? sharedContactProfileId;
  final String? sharedContactName;
  final String? sharedContactPhone;
  final String? sharedContactEmail;
  final bool isPinned;

  bool get isDeleted => deletedAt != null;
  bool get isForwarded => forwardedFromMessageId != null;
  bool get hasAttachment =>
      attachmentPath?.isNotEmpty == true || attachmentName?.isNotEmpty == true;
  bool get isImage => type == 'image' ||
      attachmentMimeType?.startsWith('image/') == true;
  bool get isContact => type == 'contact';
  bool isMine(int profileId) => sender.id == profileId;

  AppUser? get sharedTasklyContact {
    final id = sharedContactProfileId;
    final name = sharedContactName?.trim() ?? '';
    if (id == null || id <= 0 || name.isEmpty) return null;
    return AppUser(
      id: id,
      name: name,
      email: sharedContactEmail ?? '',
      phone: sharedContactPhone,
    );
  }

  Map<String, dynamic> toForwardJson() => {
        'id': id,
        'body': body,
        'type': type,
        'attachment_bucket': attachmentBucket,
        'attachment_path': attachmentPath,
        'attachment_name': attachmentName,
        'attachment_mime_type': attachmentMimeType,
        'attachment_size_bytes': attachmentSizeBytes,
        'shared_contact_profile_id': sharedContactProfileId,
        'shared_contact_name': sharedContactName,
        'shared_contact_phone': sharedContactPhone,
        'shared_contact_email': sharedContactEmail,
      };

  MessageItem withSuggestion(TaskSuggestionItem? value) => MessageItem(
        id: id,
        workspaceId: workspaceId,
        channelId: channelId,
        body: body,
        type: type,
        sender: sender,
        createdAt: createdAt,
        replyTo: replyTo,
        suggestion: value,
        mentionedProfileIds: mentionedProfileIds,
        reactions: reactions,
        editedAt: editedAt,
        deletedAt: deletedAt,
        attachmentBucket: attachmentBucket,
        attachmentPath: attachmentPath,
        attachmentName: attachmentName,
        attachmentMimeType: attachmentMimeType,
        attachmentSizeBytes: attachmentSizeBytes,
        attachmentUrl: attachmentUrl,
        forwardedFromMessageId: forwardedFromMessageId,
        sharedContactProfileId: sharedContactProfileId,
        sharedContactName: sharedContactName,
        sharedContactPhone: sharedContactPhone,
        sharedContactEmail: sharedContactEmail,
        isPinned: isPinned,
      );

  factory MessageItem.fromJson(
    Map<String, dynamic> json, {
    int? currentProfileId,
  }) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in (json['message_reactions'] as List? ?? const [])) {
      final reaction = Map<String, dynamic>.from(raw as Map);
      grouped.putIfAbsent('${reaction['emoji']}', () => []).add(reaction);
    }
    final reactions = grouped.entries
        .map(
          (entry) => MessageReaction(
            emoji: entry.key,
            count: entry.value.length,
            mine: currentProfileId != null &&
                entry.value.any(
                  (item) => _int(item['profile_id']) == currentProfileId,
                ),
          ),
        )
        .toList();

    final replyJson = json['reply_to'];
    final rawSuggestion = json['suggestion'];
    final suggestionJson = rawSuggestion is List
        ? (rawSuggestion.isEmpty ? null : rawSuggestion.first)
        : rawSuggestion;
    return MessageItem(
      id: _int(json['id']),
      workspaceId: _int(json['workspace_id']),
      channelId: _int(json['channel_id']),
      body: '${json['body'] ?? ''}',
      type: '${json['type'] ?? 'text'}',
      sender: AppUser.fromJson(
        Map<String, dynamic>.from(json['sender'] ?? const {}),
      ),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal() ??
          DateTime.now(),
      replyTo: replyJson is Map
          ? MessageItem.fromJson(
              {
                ...Map<String, dynamic>.from(replyJson),
                'workspace_id': json['workspace_id'],
                'channel_id': json['channel_id'],
                'sender': replyJson['sender'] ??
                    const {'id': 0, 'name': 'Unknown', 'email': ''},
              },
              currentProfileId: currentProfileId,
            )
          : null,
      suggestion: suggestionJson is Map
          ? TaskSuggestionItem.fromJson(
              Map<String, dynamic>.from(suggestionJson),
            )
          : null,
      mentionedProfileIds:
          (json['mentioned_profile_ids'] as List? ?? const []).map(_int).toList(),
      reactions: reactions,
      editedAt: DateTime.tryParse('${json['edited_at'] ?? ''}')?.toLocal(),
      deletedAt: DateTime.tryParse('${json['deleted_at'] ?? ''}')?.toLocal(),
      attachmentBucket: json['attachment_bucket'] as String?,
      attachmentPath: json['attachment_path'] as String?,
      attachmentName: json['attachment_name'] as String?,
      attachmentMimeType: json['attachment_mime_type'] as String?,
      attachmentSizeBytes: json['attachment_size_bytes'] == null
          ? null
          : _int(json['attachment_size_bytes']),
      attachmentUrl: json['attachment_url'] as String?,
      forwardedFromMessageId: json['forwarded_from_message_id'] == null
          ? null
          : _int(json['forwarded_from_message_id']),
      sharedContactProfileId: json['shared_contact_profile_id'] == null
          ? null
          : _int(json['shared_contact_profile_id']),
      sharedContactName: json['shared_contact_name'] as String?,
      sharedContactPhone: json['shared_contact_phone'] as String?,
      sharedContactEmail: json['shared_contact_email'] as String?,
      isPinned: json['is_pinned'] == true,
    );
  }
}

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
