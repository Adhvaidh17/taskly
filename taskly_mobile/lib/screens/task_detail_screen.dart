import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final int taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  TaskItem? _task;
  bool _loading = true;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final task = await context.read<TaskProvider>().fetch(widget.taskId);
      if (mounted) setState(() => _task = task);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final profileId = context.watch<TaskProvider>().currentProfileId ?? -1;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Task details'),
          actions: [
            if (task != null && task.canEdit(profileId))
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _editTask();
                  if (value == 'delete') _deleteTask();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit task')),
                  PopupMenuItem(value: 'delete', child: Text('Delete task')),
                ],
              ),
          ],
          bottom: task == null
              ? null
              : const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Details'),
                    Tab(text: 'Subtasks'),
                    Tab(text: 'Comments'),
                    Tab(text: 'History'),
                  ],
                ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : task == null
                ? const Center(child: Text('Task not found'))
                : Column(
                    children: [
                      _TaskHeader(
                        task: task,
                        profileId: profileId,
                        onStatus: (status) => _changeStatus(task, status),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _DetailsTab(
                              task: task,
                              onUpload: _uploadFile,
                              onChanged: (updated) => setState(() => _task = updated),
                            ),
                            _SubtasksTab(task: task, onChanged: (updated) => setState(() => _task = updated)),
                            _CommentsTab(task: task, onChanged: (updated) => setState(() => _task = updated)),
                            _HistoryTab(task: task),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _changeStatus(TaskItem task, String status) async {
    final provider = context.read<TaskProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await provider.updateStatus(task, status);
      if (!mounted) return;
      setState(() => _task = updated);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _uploadFile() async {
    final file = await openFile();
    final path = file?.path;
    if (path == null || _task == null || !mounted) return;
    final provider = context.read<TaskProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await provider.uploadAttachment(_task!, path);
      if (!mounted) return;
      setState(() => _task = updated);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _editTask() async {
    final task = _task!;
    final title = TextEditingController(text: task.title);
    final description = TextEditingController(text: task.description);
    var priority = task.priority;
    var deadline = task.deadline;
    var reminderEnabled = task.reminderEnabled;
    var reminderMinutesBefore = task.reminderMinutesBefore;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Task name')),
                const SizedBox(height: 10),
                TextField(controller: description, maxLines: 4, decoration: const InputDecoration(labelText: 'Details')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (value) => setDialogState(() => priority = value ?? 'medium'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(deadline == null
                      ? 'No deadline'
                      : DateFormat('dd MMM yyyy, h:mm a').format(deadline!)),
                  trailing: deadline == null
                      ? null
                      : IconButton(
                          onPressed: () => setDialogState(() {
                            deadline = null;
                            reminderEnabled = false;
                          }),
                          icon: const Icon(Icons.close),
                        ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: deadline ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(deadline ?? DateTime.now()),
                    );
                    if (time != null) {
                      setDialogState(() {
                        deadline = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                        reminderEnabled = true;
                      });
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deadline != null && reminderEnabled,
                  onChanged: deadline == null
                      ? null
                      : (value) =>
                          setDialogState(() => reminderEnabled = value),
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Task reminder'),
                ),
                if (deadline != null && reminderEnabled)
                  DropdownButtonFormField<int>(
                    initialValue: reminderMinutesBefore,
                    decoration: const InputDecoration(labelText: 'Remind before'),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 minutes')),
                      DropdownMenuItem(value: 15, child: Text('15 minutes')),
                      DropdownMenuItem(value: 30, child: Text('30 minutes')),
                      DropdownMenuItem(value: 60, child: Text('1 hour')),
                      DropdownMenuItem(value: 1440, child: Text('1 day')),
                    ],
                    onChanged: (value) => setDialogState(
                      () => reminderMinutesBefore = value ?? 15,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    final updated = await context.read<TaskProvider>().updateTask(
          task,
          title: title.text,
          description: description.text,
          priority: priority,
          deadline: deadline,
          assigneeId: task.assignee?.id,
          clientId: task.client?.id,
          channelId: task.channel?.id,
          reminderEnabled: reminderEnabled,
          reminderMinutesBefore: reminderMinutesBefore,
        );
    if (mounted) setState(() => _task = updated);
  }

  Future<void> _deleteTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text('This removes the task for everyone who can currently see it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || _task == null || !mounted) return;
    await context.read<TaskProvider>().deleteTask(_task!);
    if (mounted) Navigator.pop(context);
  }
}

class _TaskHeader extends StatelessWidget {
  const _TaskHeader({required this.task, required this.profileId, required this.onStatus});

  final TaskItem task;
  final int profileId;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final canChange = task.canChangeStatus(profileId);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: context.taskly.panel,
        border: Border(bottom: BorderSide(color: context.taskly.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _Pill(label: task.priority.toUpperCase(), colour: task.priority == 'high' ? context.taskly.danger : task.priority == 'low' ? context.taskly.success : context.taskly.warning),
              _Pill(label: task.contextName, colour: Theme.of(context).colorScheme.primary),
              if (task.assignee != null) _Pill(label: 'Assigned to ${task.assignee!.name}', colour: context.taskly.info),
              if (task.isOverdue) _Pill(label: 'OVERDUE', colour: context.taskly.danger),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'todo', label: Text('To Do')),
              ButtonSegment(value: 'in-progress', label: Text('In Progress')),
              ButtonSegment(value: 'done', label: Text('Completed')),
            ],
            selected: {task.status},
            onSelectionChanged: canChange ? (value) => onStatus(value.first) : null,
          ),
          if (!canChange)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text('Only the assigned person can change this status.', style: TextStyle(fontSize: 11, color: context.taskly.textFaint)),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: colour.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colour, fontSize: 10.5, fontWeight: FontWeight.w800)),
      );
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.task,
    required this.onUpload,
    required this.onChanged,
  });

  final TaskItem task;
  final VoidCallback onUpload;
  final ValueChanged<TaskItem> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(title: 'Description', child: Text(task.description?.trim().isNotEmpty == true ? task.description! : 'No description', style: TextStyle(color: context.taskly.textMuted, height: 1.5))),
        _Section(
          title: 'Information',
          child: Column(
            children: [
              _Info(icon: Icons.person_outline, label: 'Created by', value: task.creator.name),
              if (task.assignee != null) _Info(icon: Icons.assignment_ind_outlined, label: 'Assigned to', value: task.assignee!.name),
              if (task.deadline != null) _Info(icon: Icons.schedule, label: 'Deadline', value: DateFormat('dd MMM yyyy, h:mm a').format(task.deadline!)),
              if (task.deadline != null && task.reminderEnabled)
                _Info(
                  icon: Icons.notifications_active_outlined,
                  label: 'Reminder',
                  value: _reminderLabel(task.reminderMinutesBefore),
                ),
              _Info(icon: task.workspaceKind == 'direct' ? Icons.person : Icons.groups, label: 'Chat', value: task.contextName),
            ],
          ),
        ),
        _Section(
          title: 'Attachments',
          action: TextButton.icon(onPressed: onUpload, icon: const Icon(Icons.attach_file, size: 17), label: const Text('Add')),
          child: task.attachments.isEmpty
              ? Text('No attachments', style: TextStyle(color: context.taskly.textFaint))
              : Column(
                  children: task.attachments
                      .map((attachment) => _TaskAttachmentTile(
                            task: task,
                            attachment: attachment,
                            onChanged: onChanged,
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _TaskAttachmentTile extends StatelessWidget {
  const _TaskAttachmentTile({
    required this.task,
    required this.attachment,
    required this.onChanged,
  });

  final TaskItem task;
  final Map<String, dynamic> attachment;
  final ValueChanged<TaskItem> onChanged;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final id = _intAttachment(attachment['id']);
    final localPath = provider.localAttachmentPaths[id];
    final downloading = provider.downloadingAttachmentIds.contains(id);
    final unavailable = provider.unavailableAttachmentIds.contains(id);
    final removed = attachment['removed_at'] != null;
    final uploaderId = _intAttachment(attachment['uploaded_by_profile_id']);
    final me = provider.currentProfileId ?? 0;
    final canRemove = !removed &&
        (uploaderId == me || task.creator.id == me);
    final name = '${attachment['original_name'] ?? 'Attachment'}';
    final size = _attachmentSize(attachment['size_bytes']);

    Future<void> showRemoved() async {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This attachment was removed from the task and is no longer available.'),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: (removed
                  ? context.taskly.danger
                  : Theme.of(context).colorScheme.primary)
              .withValues(alpha: 0.10),
          child: Icon(
            removed ? Icons.file_present_outlined : Icons.insert_drive_file_outlined,
            color: removed ? context.taskly.danger : null,
          ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            decoration: removed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          removed
              ? 'Removed from task${size.isEmpty ? '' : ' · $size'}'
              : localPath != null
                  ? 'Saved on this device${size.isEmpty ? '' : ' · $size'}'
                  : unavailable
                      ? 'Local copy removed${size.isEmpty ? '' : ' · $size'}'
                      : 'Not downloaded${size.isEmpty ? '' : ' · $size'}',
        ),
        trailing: removed
            ? const Icon(Icons.block_outlined, size: 20)
            : downloading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        tooltip: localPath != null
                            ? 'Open attachment'
                            : 'Download attachment',
                        icon: Icon(localPath != null
                            ? Icons.open_in_new_rounded
                            : Icons.download_rounded),
                        onPressed: () async {
                          try {
                            if (localPath != null) {
                              await provider.openTaskAttachment(attachment);
                            } else {
                              final path = await provider.downloadTaskAttachment(attachment);
                              if (path == null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Attachment could not be downloaded.')),
                                );
                              }
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$error')),
                              );
                            }
                          }
                        },
                      ),
                      if (canRemove)
                        IconButton(
                          tooltip: 'Remove attachment',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Remove attachment?'),
                                content: Text('$name will no longer be available from this task.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogContext, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(dialogContext, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              final updated = await provider.removeAttachment(task, attachment);
                              if (context.mounted) onChanged(updated);
                            }
                          },
                        ),
                    ],
                  ),
        onTap: removed
            ? showRemoved
            : localPath == null || downloading
                ? null
                : () async {
                    try {
                      await provider.openTaskAttachment(attachment);
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$error')),
                        );
                      }
                    }
                  },
      ),
    );
  }
}

int _intAttachment(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

String _attachmentSize(dynamic value) {
  final bytes = value is int ? value : int.tryParse('$value') ?? 0;
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _SubtasksTab extends StatelessWidget {
  const _SubtasksTab({required this.task, required this.onChanged});

  final TaskItem task;
  final ValueChanged<TaskItem> onChanged;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TaskProvider>();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        FilledButton.icon(
          onPressed: () async {
            final title = await _askText(context, 'Add subtask', 'Subtask name');
            if (title == null || !context.mounted) return;
            onChanged(await provider.addSubtask(task, title));
          },
          icon: const Icon(Icons.add),
          label: const Text('Add subtask'),
        ),
        const SizedBox(height: 10),
        ...task.subtasks.map(
          (subtask) => Card(
            child: CheckboxListTile(
              value: subtask.isDone,
              title: Text(subtask.title, style: TextStyle(decoration: subtask.isDone ? TextDecoration.lineThrough : null)),
              onChanged: (_) async => onChanged(await provider.toggleSubtask(task, subtask)),
              secondary: IconButton(
                onPressed: () async => onChanged(await provider.deleteSubtask(task, subtask)),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentsTab extends StatelessWidget {
  const _CommentsTab({required this.task, required this.onChanged});

  final TaskItem task;
  final ValueChanged<TaskItem> onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return Column(
      children: [
        Expanded(
          child: task.comments.isEmpty
              ? Center(child: Text('No comments yet', style: TextStyle(color: context.taskly.textFaint)))
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: task.comments.length,
                  itemBuilder: (context, index) {
                    final comment = task.comments[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text(comment.user.initials)),
                      title: Text(comment.user.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(comment.body),
                      trailing: comment.createdAt == null ? null : Text(DateFormat('dd MMM').format(comment.createdAt!), style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Add a comment'))),
                const SizedBox(width: 7),
                IconButton.filled(
                  onPressed: () async {
                    if (controller.text.trim().isEmpty) return;
                    final updated = await context.read<TaskProvider>().addComment(task, controller.text);
                    controller.clear();
                    onChanged(updated);
                  },
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: task.statusHistory.length,
      itemBuilder: (context, index) {
        final item = task.statusHistory[index];
        final timestamp = item.createdAt == null
            ? ''
            : ' · ${DateFormat('dd MMM, h:mm a').format(item.createdAt!)}';
        return ListTile(
          leading: const CircleAvatar(
            radius: 9,
            child: Icon(Icons.circle, size: 7),
          ),
          title: Text(
            '${item.fromStatus ?? 'created'} → ${item.toStatus}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text('${item.user?.name ?? 'System'}$timestamp'),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), if (action != null) action!]),
              const SizedBox(height: 9),
              child,
            ],
          ),
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 19, color: context.taskly.textMuted),
            const SizedBox(width: 10),
            SizedBox(width: 92, child: Text(label, style: TextStyle(color: context.taskly.textFaint))),
            Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

String _reminderLabel(int minutes) => switch (minutes) {
      5 => '5 minutes before',
      15 => '15 minutes before',
      30 => '30 minutes before',
      60 => '1 hour before',
      1440 => '1 day before',
      _ => '$minutes minutes before',
    };

Future<String?> _askText(BuildContext context, String title, String label) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Add')),
      ],
    ),
  );
}
