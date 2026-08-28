import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/notifications/task_reminder_service.dart';
import '../core/supabase/taskly_supabase.dart';
import '../models/task.dart';
import '../services/local_media_service.dart';

enum TaskScope { involved, assignedToMe, assignedByMe }

class TaskProvider extends ChangeNotifier {
  TaskProvider(this.backend, this.reminderService, this.media);

  final TasklySupabase backend;
  final TaskReminderService reminderService;
  final LocalMediaService media;
  List<TaskItem> tasks = [];
  bool loading = false;
  String? error;
  int? currentProfileId;
  String search = '';
  String? status;
  String? priority;
  int? assigneeId;
  int? clientId;
  TaskScope scope = TaskScope.involved;
  bool get myTasks => scope == TaskScope.assignedToMe;
  bool get assignedByMe => scope == TaskScope.assignedByMe;
  bool overdue = false;
  String sort = 'deadline';

  final Map<int, String> localAttachmentPaths = {};
  final Set<int> downloadingAttachmentIds = {};
  final Set<int> unavailableAttachmentIds = {};
  StreamSubscription<void>? _taskSubscription;
  StreamSubscription<int>? _attachmentRemovalSubscription;
  bool _removedAttachmentCleanupDone = false;
  Timer? _taskDebounce;

  Future<void> load({bool syncReminders = true, bool background = false}) async {
    if (!background) loading = true;
    error = null;
    if (!background) notifyListeners();
    try {
      currentProfileId ??= await backend.profileId();
      unawaited(_ensureAttachmentRemovalSync());
      final rows = await backend.tasks(
        search: search,
        status: status,
        priority: priority,
        assigneeId: assigneeId,
        clientId: clientId,
        myTasks: myTasks,
        assignedByMe: assignedByMe,
        overdue: overdue,
        sort: sort,
      );
      tasks = rows.map(TaskItem.fromJson).toList();
      _taskSubscription ??= backend.taskChanges().listen((_) {
        if (_taskDebounce?.isActive == true) return;
        _taskDebounce = Timer(const Duration(milliseconds: 120), () {
          unawaited(load(syncReminders: false, background: true));
        });
      });
      if (syncReminders) await _syncReminders();
    } catch (exception) {
      error = '$exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<TaskItem> fetch(int id) async {
    currentProfileId ??= await backend.profileId();
    final task = TaskItem.fromJson(await backend.task(id));
    _replace(task);
    await _restoreTaskAttachmentState(task);
    await _syncReminders();
    return task;
  }

  Future<List<TaskItem>> groupTasks(int workspaceId) async {
    final rows = await backend.groupTasks(workspaceId);
    return rows.map(TaskItem.fromJson).toList();
  }

  Future<void> create({
    required String title,
    String description = '',
    String priority = 'medium',
    DateTime? deadline,
    required int assigneeId,
    int? clientId,
    required int channelId,
    List<String> tags = const [],
    List<String> subtasks = const [],
    bool reminderEnabled = true,
    int reminderMinutesBefore = 15,
  }) async {
    final task = TaskItem.fromJson(await backend.createTask({
      'title': title.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'status': 'todo',
      'priority': priority,
      'deadline': deadline?.toUtc().toIso8601String(),
      'assignee_id': assigneeId,
      'client_id': clientId,
      'channel_id': channelId,
      'source_type': 'manual',
      'reminder_enabled': deadline != null && reminderEnabled,
      'reminder_minutes_before': reminderMinutesBefore,
      'tags': tags,
      'subtasks': subtasks.map((item) => {'title': item.trim()}).toList(),
    }));
    tasks.add(task);
    await _syncReminders();
    notifyListeners();
  }

  Future<TaskItem> updateStatus(TaskItem task, String newStatus) async {
    final updated =
        TaskItem.fromJson(await backend.changeTaskStatus(task.id, newStatus));
    _replace(updated);
    await _syncReminders();
    return updated;
  }

  Future<TaskItem> updateTask(
    TaskItem task, {
    required String title,
    required String description,
    required String priority,
    DateTime? deadline,
    int? assigneeId,
    int? clientId,
    int? channelId,
    List<String>? tags,
    bool? reminderEnabled,
    int? reminderMinutesBefore,
  }) async {
    final updated = TaskItem.fromJson(await backend.updateTask(task.id, {
      'title': title.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'priority': priority,
      'deadline': deadline?.toUtc().toIso8601String(),
      'assignee_id': assigneeId,
      'client_id': clientId,
      'channel_id': channelId,
      if (tags != null) 'tags': tags,
      if (reminderEnabled != null)
        'reminder_enabled': deadline != null && reminderEnabled,
      if (reminderMinutesBefore != null)
        'reminder_minutes_before': reminderMinutesBefore,
      'version': task.version,
    }));
    _replace(updated);
    await _syncReminders();
    return updated;
  }

  Future<void> deleteTask(TaskItem task) async {
    await backend.deleteTask(task.id);
    tasks.removeWhere((item) => item.id == task.id);
    await reminderService.cancelTask(task.id);
    await _syncReminders();
    notifyListeners();
  }

  Future<TaskItem> addSubtask(TaskItem task, String title) async {
    final updated =
        TaskItem.fromJson(await backend.addSubtask(task.id, title));
    _replace(updated);
    await _syncReminders();
    return updated;
  }

  Future<TaskItem> deleteSubtask(TaskItem task, SubtaskItem subtask) async {
    await backend.deleteSubtask(subtask.id);
    return fetch(task.id);
  }

  Future<TaskItem> addComment(TaskItem task, String body) async {
    final updated = TaskItem.fromJson(await backend.addComment(task.id, body));
    _replace(updated);
    await _syncReminders();
    return updated;
  }

  Future<TaskItem> toggleSubtask(TaskItem task, SubtaskItem subtask) async {
    final updated = TaskItem.fromJson(
      await backend.updateSubtask(
        task.id,
        subtask.id,
        !subtask.isDone,
        subtask.version,
      ),
    );
    _replace(updated);
    await _syncReminders();
    return updated;
  }

  Future<TaskItem> uploadAttachment(TaskItem task, String filePath) async {
    final prepared = await media.prepareTaskAttachmentOutgoing(filePath);
    final updated = TaskItem.fromJson(
      await backend.uploadAttachment(task.id, prepared.path),
    );
    _replace(updated);
    final matches = updated.attachments.where(
      (item) => '${item['original_name'] ?? ''}' == prepared.name,
    );
    if (matches.isNotEmpty) {
      final attachmentId = _int(matches.last['id']);
      if (attachmentId > 0) {
        await media.bindTaskAttachment(attachmentId, prepared.path);
        localAttachmentPaths[attachmentId] = prepared.path;
        unavailableAttachmentIds.remove(attachmentId);
      }
    }
    notifyListeners();
    return updated;
  }

  Future<TaskItem> removeAttachment(
    TaskItem task,
    Map<String, dynamic> attachment,
  ) async {
    final id = _int(attachment['id']);
    if (id <= 0) return task;
    final uploaderId = _int(attachment['uploaded_by_profile_id']);
    final me = currentProfileId ?? await backend.profileId();
    final updated = TaskItem.fromJson(
      await backend.removeTaskAttachment(task.id, attachment),
    );
    _replace(updated);
    if (uploaderId == me) {
      await media.removeTaskAttachmentLocal(id);
      localAttachmentPaths.remove(id);
      unavailableAttachmentIds.add(id);
    }
    notifyListeners();
    return updated;
  }

  Future<String?> localTaskAttachmentPath(Map<String, dynamic> attachment) async {
    final id = _int(attachment['id']);
    if (id <= 0) return null;
    final cached = localAttachmentPaths[id];
    if (cached != null) return cached;
    final existing = await media.existingTaskAttachment(id);
    if (existing.path != null) {
      localAttachmentPaths[id] = existing.path!;
      unavailableAttachmentIds.remove(id);
      notifyListeners();
      return existing.path;
    }
    if (existing.unavailable) {
      unavailableAttachmentIds.add(id);
      notifyListeners();
    }
    return null;
  }

  Future<String?> downloadTaskAttachment(Map<String, dynamic> attachment) async {
    if (attachment['removed_at'] != null) {
      final id = _int(attachment['id']);
      if (id > 0) unavailableAttachmentIds.add(id);
      return null;
    }
    final id = _int(attachment['id']);
    if (id <= 0 || downloadingAttachmentIds.contains(id)) return null;
    downloadingAttachmentIds.add(id);
    unavailableAttachmentIds.remove(id);
    notifyListeners();
    try {
      final bucket = '${attachment['bucket'] ?? 'task-files'}';
      final path = '${attachment['path'] ?? ''}';
      final name = '${attachment['original_name'] ?? path.split('/').last}';
      final mime = '${attachment['mime_type'] ?? 'application/octet-stream'}';
      final result = await media.downloadTaskAttachment(
        attachmentId: id,
        bucket: bucket,
        remotePath: path,
        name: name,
        mimeType: mime,
        backend: backend,
      );
      if (result.path != null) {
        localAttachmentPaths[id] = result.path!;
        return result.path;
      }
      if (result.unavailable) unavailableAttachmentIds.add(id);
      return null;
    } finally {
      downloadingAttachmentIds.remove(id);
      notifyListeners();
    }
  }

  Future<void> openTaskAttachment(Map<String, dynamic> attachment) async {
    if (attachment['removed_at'] != null) {
      throw const FileSystemException('This attachment has been removed from the task.');
    }
    var path = await localTaskAttachmentPath(attachment);
    path ??= await downloadTaskAttachment(attachment);
    if (path == null) {
      throw const FileSystemException('Attachment is not available on this device.');
    }
    await media.openFile(
      path,
      mimeType: '${attachment['mime_type'] ?? 'application/octet-stream'}',
    );
  }

  void setScope(TaskScope value) {
    scope = value;
    notifyListeners();
  }

  void showAssignedToMe() => setScope(TaskScope.assignedToMe);
  void showAssignedByMe() => setScope(TaskScope.assignedByMe);
  void showAllTasks() => setScope(TaskScope.involved);

  void clearLocalAttachmentState() {
    localAttachmentPaths.clear();
    downloadingAttachmentIds.clear();
    unavailableAttachmentIds.clear();
    notifyListeners();
  }

  void clearFilters() {
    status = null;
    priority = null;
    assigneeId = null;
    clientId = null;
    scope = TaskScope.involved;
    overdue = false;
    sort = 'deadline';
    search = '';
    notifyListeners();
  }

  Future<void> _restoreTaskAttachmentState(TaskItem task) async {
    for (final attachment in task.attachments) {
      final id = _int(attachment['id']);
      if (id <= 0) continue;
      if (attachment['removed_at'] != null) {
        unavailableAttachmentIds.add(id);
        localAttachmentPaths.remove(id);
        final uploaderId = _int(attachment['uploaded_by_profile_id']);
        final me = currentProfileId ?? await backend.profileId();
        if (uploaderId == me) await media.removeTaskAttachmentLocal(id);
        continue;
      }
      final existing = await media.existingTaskAttachment(id);
      if (existing.path != null) {
        localAttachmentPaths[id] = existing.path!;
      } else if (existing.unavailable) {
        unavailableAttachmentIds.add(id);
      }
    }
    notifyListeners();
  }

  Future<void> _ensureAttachmentRemovalSync() async {
    final profileId = currentProfileId;
    if (profileId == null) return;

    _attachmentRemovalSubscription ??=
        backend.taskAttachmentRemovalChanges(profileId).listen((attachmentId) {
      unawaited(_removeUploaderLocalAttachment(attachmentId));
    });

    if (_removedAttachmentCleanupDone) return;
    _removedAttachmentCleanupDone = true;
    try {
      final removedIds = await backend.removedTaskAttachmentIdsForMe();
      for (final attachmentId in removedIds) {
        await _removeUploaderLocalAttachment(attachmentId);
      }
    } catch (_) {
      // Cleanup is best-effort and must never delay the Tasks tab.
      _removedAttachmentCleanupDone = false;
    }
  }

  Future<void> _removeUploaderLocalAttachment(int attachmentId) async {
    await media.removeTaskAttachmentLocal(attachmentId);
    localAttachmentPaths.remove(attachmentId);
    downloadingAttachmentIds.remove(attachmentId);
    unavailableAttachmentIds.add(attachmentId);
    notifyListeners();
  }

  Future<void> _syncReminders() async {
    final profileId = currentProfileId;
    if (profileId == null) return;
    try {
      final reminderRows = await backend.reminderTasks();
      final reminderTasks = reminderRows.map(TaskItem.fromJson).toList();
      await reminderService.syncTasks(
        reminderTasks,
        currentProfileId: profileId,
      );
    } catch (_) {
      // A reminder failure must not block task loading or editing.
    }
  }

  void _replace(TaskItem task) {
    final index = tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _taskDebounce?.cancel();
    _taskSubscription?.cancel();
    _attachmentRemovalSubscription?.cancel();
    super.dispose();
  }
}

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
