import 'package:flutter/foundation.dart';

import '../core/supabase/taskly_supabase.dart';
import '../models/task.dart';

class TaskProvider extends ChangeNotifier {
  TaskProvider(this.backend);

  final TasklySupabase backend;
  List<TaskItem> tasks = [];
  bool loading = false;
  String? error;
  int? currentProfileId;
  String search = '';
  String? status;
  String? priority;
  int? assigneeId;
  int? clientId;
  bool myTasks = false;
  bool assignedByMe = false;
  bool overdue = false;
  String sort = 'deadline';

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      currentProfileId ??= await backend.profileId();
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
    } catch (exception) {
      error = '$exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<TaskItem> fetch(int id) async {
    final task = TaskItem.fromJson(await backend.task(id));
    _replace(task);
    return task;
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
      'tags': tags,
      'subtasks': subtasks.map((item) => {'title': item.trim()}).toList(),
    }));
    tasks.add(task);
    notifyListeners();
  }

  Future<TaskItem> updateStatus(TaskItem task, String newStatus) async {
    final updated = TaskItem.fromJson(await backend.changeTaskStatus(task.id, newStatus));
    _replace(updated);
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
      'version': task.version,
    }));
    _replace(updated);
    return updated;
  }

  Future<void> deleteTask(TaskItem task) async {
    await backend.deleteTask(task.id);
    tasks.removeWhere((item) => item.id == task.id);
    notifyListeners();
  }

  Future<TaskItem> addSubtask(TaskItem task, String title) async {
    final updated = TaskItem.fromJson(await backend.addSubtask(task.id, title));
    _replace(updated);
    return updated;
  }

  Future<TaskItem> deleteSubtask(TaskItem task, SubtaskItem subtask) async {
    await backend.deleteSubtask(subtask.id);
    return fetch(task.id);
  }

  Future<TaskItem> addComment(TaskItem task, String body) async {
    final updated = TaskItem.fromJson(await backend.addComment(task.id, body));
    _replace(updated);
    return updated;
  }

  Future<TaskItem> toggleSubtask(TaskItem task, SubtaskItem subtask) async {
    final updated = TaskItem.fromJson(
      await backend.updateSubtask(task.id, subtask.id, !subtask.isDone, subtask.version),
    );
    _replace(updated);
    return updated;
  }

  Future<TaskItem> uploadAttachment(TaskItem task, String filePath) async {
    final updated = TaskItem.fromJson(await backend.uploadAttachment(task.id, filePath));
    _replace(updated);
    return updated;
  }

  void showAssignedToMe() {
    myTasks = true;
    assignedByMe = false;
    notifyListeners();
  }

  void showAssignedByMe() {
    assignedByMe = true;
    myTasks = false;
    notifyListeners();
  }

  void showAllTasks() {
    assignedByMe = false;
    myTasks = false;
    notifyListeners();
  }

  void clearFilters() {
    status = null;
    priority = null;
    assigneeId = null;
    clientId = null;
    myTasks = false;
    assignedByMe = false;
    overdue = false;
    sort = 'deadline';
    search = '';
    notifyListeners();
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
}
