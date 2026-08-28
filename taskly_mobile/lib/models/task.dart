import 'user.dart';

class TaskClient {
  const TaskClient({required this.id, required this.name, required this.colour, this.icon});
  final int id;
  final String name;
  final String colour;
  final String? icon;

  factory TaskClient.fromJson(Map<String, dynamic> json) => TaskClient(
        id: _int(json['id']),
        name: '${json['name'] ?? ''}',
        colour: '${json['colour'] ?? '#64748B'}',
        icon: json['icon'] as String?,
      );
}

class TaskChannel {
  const TaskChannel({
    required this.id,
    required this.name,
    this.icon,
    this.workspaceId,
    this.workspaceName,
    this.workspaceKind,
  });

  final int id;
  final String name;
  final String? icon;
  final int? workspaceId;
  final String? workspaceName;
  final String? workspaceKind;

  factory TaskChannel.fromJson(Map<String, dynamic> json) => TaskChannel(
        id: _int(json['id']),
        name: '${json['name'] ?? ''}',
        icon: json['icon'] as String?,
        workspaceId: _nullableInt(json['workspace_id']),
        workspaceName: json['workspace_name'] as String?,
        workspaceKind: json['workspace_kind'] as String?,
      );
}

class SubtaskItem {
  const SubtaskItem({
    required this.id,
    required this.title,
    required this.isDone,
    required this.position,
    this.version = 1,
  });

  final int id;
  final String title;
  final bool isDone;
  final int position;
  final int version;

  factory SubtaskItem.fromJson(Map<String, dynamic> json) => SubtaskItem(
        id: _int(json['id']),
        title: '${json['title'] ?? ''}',
        isDone: json['is_done'] == true || json['is_done'] == 1,
        position: _int(json['position']),
        version: _int(json['version'] ?? 1),
      );
}

class TaskCommentItem {
  const TaskCommentItem({required this.id, required this.body, required this.user, this.createdAt});
  final int id;
  final String body;
  final AppUser user;
  final DateTime? createdAt;

  factory TaskCommentItem.fromJson(Map<String, dynamic> json) => TaskCommentItem(
        id: _int(json['id']),
        body: '${json['body'] ?? ''}',
        user: AppUser.fromJson(Map<String, dynamic>.from(json['user'] ?? const {})),
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
      );
}

class TaskStatusHistoryItem {
  const TaskStatusHistoryItem({
    required this.id,
    required this.toStatus,
    this.fromStatus,
    this.user,
    this.createdAt,
  });

  final int id;
  final String? fromStatus;
  final String toStatus;
  final AppUser? user;
  final DateTime? createdAt;

  factory TaskStatusHistoryItem.fromJson(Map<String, dynamic> json) => TaskStatusHistoryItem(
        id: _int(json['id']),
        fromStatus: json['from_status'] as String?,
        toStatus: '${json['to_status'] ?? 'todo'}',
        user: json['user'] is Map
            ? AppUser.fromJson(Map<String, dynamic>.from(json['user']))
            : null,
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
      );
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.status,
    required this.priority,
    required this.version,
    required this.creator,
    this.workspaceName,
    this.workspaceKind,
    this.description,
    this.deadline,
    this.assignee,
    this.client,
    this.channel,
    this.originText,
    this.sourceType,
    this.reminderEnabled = false,
    this.reminderMinutesBefore = 15,
    this.subtasks = const [],
    this.comments = const [],
    this.tags = const [],
    this.attachments = const [],
    this.statusHistory = const [],
  });

  final int id;
  final int workspaceId;
  final String? workspaceName;
  final String? workspaceKind;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final DateTime? deadline;
  final AppUser creator;
  final AppUser? assignee;
  final TaskClient? client;
  final TaskChannel? channel;
  final String? originText;
  final String? sourceType;
  final bool reminderEnabled;
  final int reminderMinutesBefore;
  final int version;
  final List<SubtaskItem> subtasks;
  final List<TaskCommentItem> comments;
  final List<String> tags;
  final List<Map<String, dynamic>> attachments;
  final List<TaskStatusHistoryItem> statusHistory;

  bool get isOverdue => status != 'done' && deadline != null && deadline!.isBefore(DateTime.now());
  int get completedSubtasks => subtasks.where((item) => item.isDone).length;
  double get progress => subtasks.isEmpty ? 0 : completedSubtasks / subtasks.length;
  String get contextName => workspaceName ?? channel?.workspaceName ?? channel?.name ?? 'Taskly';

  bool canChangeStatus(int profileId) => assignee?.id == profileId;
  bool canEdit(int profileId) => creator.id == profileId;

  TaskItem copyWith({String? status, int? version}) => TaskItem(
        id: id,
        workspaceId: workspaceId,
        workspaceName: workspaceName,
        workspaceKind: workspaceKind,
        title: title,
        description: description,
        status: status ?? this.status,
        priority: priority,
        deadline: deadline,
        creator: creator,
        assignee: assignee,
        client: client,
        channel: channel,
        originText: originText,
        sourceType: sourceType,
        reminderEnabled: reminderEnabled,
        reminderMinutesBefore: reminderMinutesBefore,
        version: version ?? this.version,
        subtasks: subtasks,
        comments: comments,
        tags: tags,
        attachments: attachments,
        statusHistory: statusHistory,
      );

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final workspace = json['workspace'] is Map
        ? Map<String, dynamic>.from(json['workspace'])
        : const <String, dynamic>{};
    final rawTags = json['tags'] as List? ?? const [];
    return TaskItem(
      id: _int(json['id']),
      workspaceId: _int(json['workspace_id'] ?? workspace['id']),
      workspaceName: json['workspace_name'] as String? ?? workspace['name'] as String?,
      workspaceKind: json['workspace_kind'] as String? ?? workspace['kind'] as String?,
      title: '${json['title'] ?? ''}',
      description: _cleanDescription(json['description']),
      status: '${json['status'] ?? 'todo'}',
      priority: '${json['priority'] ?? 'medium'}',
      deadline: DateTime.tryParse('${json['deadline'] ?? ''}')?.toLocal(),
      creator: AppUser.fromJson(Map<String, dynamic>.from(json['creator'] ?? const {})),
      assignee: json['assignee'] is Map
          ? AppUser.fromJson(Map<String, dynamic>.from(json['assignee']))
          : null,
      client: json['client'] is Map
          ? TaskClient.fromJson(Map<String, dynamic>.from(json['client']))
          : null,
      channel: json['channel'] is Map
          ? TaskChannel.fromJson(Map<String, dynamic>.from(json['channel']))
          : null,
      originText: json['origin_text'] as String?,
      sourceType: json['source_type'] as String?,
      reminderEnabled: json['reminder_enabled'] == true || json['reminder_enabled'] == 1,
      reminderMinutesBefore: _int(json['reminder_minutes_before'] ?? 15),
      version: _int(json['version'] ?? 1),
      subtasks: (json['subtasks'] as List? ?? const [])
          .map((item) => SubtaskItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      comments: (json['comments'] as List? ?? const [])
          .map((item) => TaskCommentItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      tags: rawTags.map((item) => item is Map ? '${item['name']}' : '$item').toList(),
      attachments: (json['attachments'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      statusHistory: (json['status_history'] as List? ?? const [])
          .map((item) => TaskStatusHistoryItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

String? _cleanDescription(dynamic value) {
  var text = value == null ? '' : '$value';
  text = text.replaceAll(
    RegExp(r'^\s*\(?sender local time\)?.*$', caseSensitive: false, multiLine: true),
    '',
  );
  text = text.replaceAll(
    RegExp(r'\n?\s*original message\s*:.*$', caseSensitive: false, dotAll: true),
    '',
  );
  text = text.trim();
  return text.isEmpty ? null : text;
}

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
int? _nullableInt(dynamic value) => value == null ? null : _int(value);
