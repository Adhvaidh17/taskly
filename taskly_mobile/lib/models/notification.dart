import 'user.dart';

class TasklyNotification {
  const TasklyNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.isRead,
    required this.createdAt,
    this.body,
    this.taskId,
    this.channelId,
    this.messageId,
    this.workspaceId,
    this.actor,
  });

  final int id;
  final String type;
  final String title;
  final String? body;
  final bool isRead;
  final DateTime createdAt;
  final int? taskId;
  final int? channelId;
  final int? messageId;
  final int? workspaceId;
  final AppUser? actor;

  factory TasklyNotification.fromJson(Map<String, dynamic> json) => TasklyNotification(
        id: _int(json['id']),
        type: '${json['type'] ?? ''}',
        title: '${json['title'] ?? ''}',
        body: json['body'] as String?,
        isRead: json['is_read'] == true,
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
        taskId: _nullableInt(json['task_id']),
        channelId: _nullableInt(json['channel_id']),
        messageId: _nullableInt(json['message_id']),
        workspaceId: _nullableInt(json['workspace_id']),
        actor: json['actor'] is Map
            ? AppUser.fromJson(Map<String, dynamic>.from(json['actor']))
            : null,
      );
}

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
int? _nullableInt(dynamic value) => value == null ? null : _int(value);
