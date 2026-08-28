import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../providers/task_provider.dart';
import '../providers/workspace_provider.dart';
import '../widgets/task_card.dart';
import 'task_detail_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  TaskScope _mode = TaskScope.involved;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<TaskProvider>();
    final profileId = provider.currentProfileId ?? -1;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: provider.load,
          child: CustomScrollView(
            key: const PageStorageKey('task-list'),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Column(
                    children: [
                      TextField(
                        controller: _search,
                        onSubmitted: (value) {
                          provider.search = value;
                          provider.load();
                        },
                        decoration: InputDecoration(
                          hintText: 'Search tasks',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            onPressed: () => _showFilters(context, provider),
                            icon: const Icon(Icons.tune),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<TaskScope>(
                          segments: const [
                            ButtonSegment(
                              value: TaskScope.involved,
                              icon: Icon(Icons.groups_outlined, size: 18),
                              label: Text('Involved'),
                            ),
                            ButtonSegment(
                              value: TaskScope.assignedToMe,
                              icon: Icon(Icons.inbox_outlined, size: 18),
                              label: Text('To me'),
                            ),
                            ButtonSegment(
                              value: TaskScope.assignedByMe,
                              icon: Icon(Icons.outbox_outlined, size: 18),
                              label: Text('By me'),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (selection) async {
                            final value = selection.first;
                            setState(() => _mode = value);
                            provider.setScope(value);
                            await provider.load();
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      _TaskSummary(tasks: provider.tasks),
                    ],
                  ),
                ),
              ),
              if (provider.loading && provider.tasks.isEmpty)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (provider.tasks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No tasks here yet. Tasks confirmed from chats will appear automatically.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.taskly.textMuted),
                      ),
                    ),
                  ),
                )
              else
                for (final status in const ['todo', 'in-progress', 'done'])
                  _TaskGroup(
                    status: status,
                    tasks: provider.tasks.where((task) => task.status == status).toList(),
                    profileId: profileId,
                  ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
        Positioned(
          right: 18,
          bottom: 18,
          child: FloatingActionButton(
            heroTag: 'new-task',
            tooltip: 'Create task',
            onPressed: () => _createTask(context),
            child: const Icon(Icons.add_task),
          ),
        ),
      ],
    );
  }

  Future<void> _createTask(BuildContext context) async {
    final workspace = context.read<WorkspaceProvider>();
    if (workspace.channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create or join a group, or start a direct chat first.')),
      );
      return;
    }

    final title = TextEditingController();
    final details = TextEditingController();
    var priority = 'medium';
    var channelId = workspace.channels.first.id;
    var eligibleMembers = (await workspace.backend.conversationMembers(channelId))
        .map(AppUser.fromJson)
        .toList();
    if (!context.mounted) return;
    var assigneeId = eligibleMembers.firstOrNull?.id;
    DateTime? deadline;
    var reminderEnabled = false;
    var reminderMinutesBefore = 15;

    final create = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Task name')),
                const SizedBox(height: 10),
                TextField(controller: details, maxLines: 3, decoration: const InputDecoration(labelText: 'Details')),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: channelId,
                  decoration: const InputDecoration(labelText: 'Chat / group'),
                  items: workspace.channels
                      .map((channel) => DropdownMenuItem(value: channel.id, child: Text(channel.name)))
                      .toList(),
                  onChanged: (value) async {
                    final nextChannelId = value ?? channelId;
                    final rows = await workspace.backend.conversationMembers(nextChannelId);
                    if (!dialogContext.mounted) return;
                    setDialogState(() {
                      channelId = nextChannelId;
                      eligibleMembers = rows.map(AppUser.fromJson).toList();
                      assigneeId = eligibleMembers.firstOrNull?.id;
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: assigneeId,
                  decoration: const InputDecoration(labelText: 'Assigned to'),
                  items: eligibleMembers
                      .map((member) => DropdownMenuItem(value: member.id, child: Text(member.name)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => assigneeId = value),
                ),
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
                  title: Text(
                    deadline == null
                        ? 'Add deadline'
                        : '${deadline!.day}/${deadline!.month}/${deadline!.year} ${TimeOfDay.fromDateTime(deadline!).format(context)}',
                  ),
                  trailing: deadline == null
                      ? null
                      : IconButton(
                          tooltip: 'Remove deadline',
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
                    if (time == null) return;
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
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (create != true || title.text.trim().isEmpty || assigneeId == null || !context.mounted) return;
    try {
      await context.read<TaskProvider>().create(
            title: title.text,
            description: details.text,
            priority: priority,
            deadline: deadline,
            assigneeId: assigneeId!,
            channelId: channelId,
            reminderEnabled: reminderEnabled,
            reminderMinutesBefore: reminderMinutesBefore,
          );
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _showFilters(BuildContext context, TaskProvider provider) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(alignment: Alignment.centerLeft, child: Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Overdue only'),
                  value: provider.overdue,
                  onChanged: (value) => setSheetState(() => provider.overdue = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: provider.status ?? '',
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All statuses')),
                    DropdownMenuItem(value: 'todo', child: Text('To Do')),
                    DropdownMenuItem(value: 'in-progress', child: Text('In Progress')),
                    DropdownMenuItem(value: 'done', child: Text('Completed')),
                  ],
                  onChanged: (value) => setSheetState(() => provider.status = value?.isEmpty == true ? null : value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: provider.priority ?? '',
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All priorities')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                  ],
                  onChanged: (value) => setSheetState(() => provider.priority = value?.isEmpty == true ? null : value),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          provider.clearFilters();
                          setSheetState(() {});
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          provider.load();
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskSummary extends StatelessWidget {
  const _TaskSummary({required this.tasks});

  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final todo = tasks.where((task) => task.status == 'todo').length;
    final progress = tasks.where((task) => task.status == 'in-progress').length;
    final done = tasks.where((task) => task.status == 'done').length;
    return Row(
      children: [
        _SummaryChip(label: 'To do', value: todo, colour: context.taskly.danger),
        const SizedBox(width: 8),
        _SummaryChip(label: 'Active', value: progress, colour: context.taskly.warning),
        const SizedBox(width: 8),
        _SummaryChip(label: 'Done', value: done, colour: context.taskly.success),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value, required this.colour});
  final String label;
  final int value;
  final Color colour;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colour.withValues(alpha: .25)),
          ),
          child: Column(
            children: [
              Text('$value', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: colour)),
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.taskly.textMuted)),
            ],
          ),
        ),
      );
}

class _TaskGroup extends StatelessWidget {
  const _TaskGroup({required this.status, required this.tasks, required this.profileId});

  final String status;
  final List<TaskItem> tasks;
  final int profileId;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final provider = context.read<TaskProvider>();
    final (label, colour) = switch (status) {
      'done' => ('Completed', context.taskly.success),
      'in-progress' => ('In Progress', context.taskly.warning),
      _ => ('To Do', context.taskly.danger),
    };
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                CircleAvatar(radius: 5, backgroundColor: colour),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: colour)),
                const SizedBox(width: 6),
                Text('${tasks.length}', style: TextStyle(color: context.taskly.textFaint)),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return TaskCard(
                task: task,
                currentProfileId: profileId,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id))),
                onStatus: (value) async {
                  try {
                    await provider.updateStatus(task, value);
                  } catch (error) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
