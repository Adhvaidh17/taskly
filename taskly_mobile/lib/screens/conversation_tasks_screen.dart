import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/task_provider.dart';
import '../v62/ai_universe_shell_v62.dart';
import '../widgets/task_card.dart';
import 'task_detail_screen.dart';

class ConversationTasksScreen extends StatefulWidget {
  const ConversationTasksScreen({super.key, required this.channelId, required this.title});
  final int channelId;
  final String title;
  @override State<ConversationTasksScreen> createState() => _ConversationTasksScreenState();
}

class _ConversationTasksScreenState extends State<ConversationTasksScreen> {
  bool _loading = true;
  String? _error;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  Future<void> _load() async {
    try { await context.read<TaskProvider>().load(); if (mounted) setState(() => _loading = false); }
    catch (e) { if (mounted) setState(() { _loading = false; _error = '$e'; }); }
  }
  @override Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final tasks = provider.tasks.where((task) => task.channel?.id == widget.channelId).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: AiUniverseShellV62(
        intensity: .25,
        showStars: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : tasks.isEmpty
                    ? Center(child: Text('No tasks in ${widget.title} yet.'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                        children: [
                          Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          ...tasks.map((task) => TaskCard(
                            task: task,
                            currentProfileId: provider.currentProfileId ?? -1,
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id))),
                            onStatus: (status) async { await provider.updateStatus(task, status); await _load(); },
                          )),
                        ],
                      ),
      ),
    );
  }
}
