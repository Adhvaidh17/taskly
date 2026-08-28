import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/channel.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../widgets/task_card.dart';
import 'task_detail_screen.dart';

class GroupTasksScreen extends StatefulWidget {
  const GroupTasksScreen({super.key, required this.conversation});

  final ConversationItem conversation;

  @override
  State<GroupTasksScreen> createState() => _GroupTasksScreenState();
}

class _GroupTasksScreenState extends State<GroupTasksScreen> {
  List<TaskItem> _tasks = const [];
  bool _loading = true;
  String? _error;
  StreamSubscription<void>? _subscription;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final provider = context.read<TaskProvider>();
    _subscription ??= provider.backend.taskChanges().listen((_) {
      if (_debounce?.isActive == true) return;
      _debounce = Timer(const Duration(milliseconds: 120), _load);
    });
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final rows = await context
          .read<TaskProvider>()
          .groupTasks(widget.conversation.workspaceId);
      if (!mounted) return;
      setState(() {
        _tasks = rows;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final profileId = provider.currentProfileId ?? -1;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Group tasks'),
            Text(
              widget.conversation.name,
              style: TextStyle(fontSize: 11, color: context.taskly.textMuted),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.error_outline, size: 48, color: context.taskly.danger),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                    ],
                  )
                : _tasks.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 150),
                          Icon(Icons.task_alt_rounded, size: 52, color: context.taskly.textFaint),
                          const SizedBox(height: 12),
                          Text(
                            'No group tasks yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.taskly.textMuted),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                        children: [
                          _GroupTaskSummary(tasks: _tasks),
                          const SizedBox(height: 12),
                          for (final status in const ['todo', 'in-progress', 'done']) ...[
                            _GroupHeading(status: status, count: _tasks.where((t) => t.status == status).length),
                            const SizedBox(height: 7),
                            ..._tasks.where((task) => task.status == status).map(
                                  (task) => TaskCard(
                                    task: task,
                                    currentProfileId: profileId,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => TaskDetailScreen(taskId: task.id),
                                      ),
                                    ),
                                    onStatus: (status) async {
                                      await provider.updateStatus(task, status);
                                      await _load();
                                    },
                                  ),
                                ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
      ),
    );
  }
}

class _GroupTaskSummary extends StatelessWidget {
  const _GroupTaskSummary({required this.tasks});

  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final todo = tasks.where((task) => task.status == 'todo').length;
    final doing = tasks.where((task) => task.status == 'in-progress').length;
    final done = tasks.where((task) => task.status == 'done').length;
    return Row(
      children: [
        Expanded(child: _Metric(label: 'To do', value: todo, colour: context.taskly.danger)),
        const SizedBox(width: 8),
        Expanded(child: _Metric(label: 'In progress', value: doing, colour: context.taskly.warning)),
        const SizedBox(width: 8),
        Expanded(child: _Metric(label: 'Done', value: done, colour: context.taskly.success)),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.colour});
  final String label;
  final int value;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.10),
          border: Border.all(color: colour.withValues(alpha: 0.18)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colour)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, style: TextStyle(fontSize: 10, color: context.taskly.textMuted)),
          ],
        ),
      );
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.status, required this.count});
  final String status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'done' => 'Completed',
      'in-progress' => 'In progress',
      _ => 'To do',
    };
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(width: 7),
        Text('$count', style: TextStyle(fontSize: 12, color: context.taskly.textMuted)),
      ],
    );
  }
}
