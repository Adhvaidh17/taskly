import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../providers/task_provider.dart';
import '../widgets/task_card.dart';
import 'task_detail_screen.dart';

class AssignedByMeScreen extends StatefulWidget {
  const AssignedByMeScreen({super.key});

  @override
  State<AssignedByMeScreen> createState() => _AssignedByMeScreenState();
}

class _AssignedByMeScreenState extends State<AssignedByMeScreen> {
  late Future<List<TaskItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<TaskItem>> _load() async {
    final provider = context.read<TaskProvider>();
    provider.currentProfileId ??= await provider.backend.profileId();
    final rows = await provider.backend.tasks(assignedByMe: true, sort: 'created');
    return rows.map(TaskItem.fromJson).toList();
  }

  Future<void> _changeStatus(TaskItem task, String status) async {
    final provider = context.read<TaskProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await provider.updateStatus(task, status);
      if (!mounted) return;
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileId = context.read<TaskProvider>().currentProfileId ?? -1;
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks I assigned')),
      body: FutureBuilder<List<TaskItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
          final tasks = snapshot.data ?? const [];
          if (tasks.isEmpty) return Center(child: Text('You have not assigned any tasks yet.', style: TextStyle(color: context.taskly.textMuted)));
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return TaskCard(
                  task: task,
                  currentProfileId: profileId,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id))),
                  onStatus: (status) => _changeStatus(task, status),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
