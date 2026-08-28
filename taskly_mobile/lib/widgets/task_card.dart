import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../models/task.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.currentProfileId,
    required this.onTap,
    required this.onStatus,
  });

  final TaskItem task;
  final int currentProfileId;
  final VoidCallback onTap;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final priorityColour = switch (task.priority) {
      'high' => context.taskly.danger,
      'low' => context.taskly.success,
      _ => context.taskly.warning,
    };
    final canChange = task.canChangeStatus(currentProfileId);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 68,
                decoration: BoxDecoration(
                  color: task.isOverdue ? context.taskly.danger : priorityColour,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              decoration: task.status == 'done' ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (task.isOverdue)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.warning_amber_rounded, size: 18, color: context.taskly.danger),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 9,
                      runSpacing: 5,
                      children: [
                        if (task.assignee != null) _Meta(icon: Icons.person_outline, text: task.assignee!.name),
                        if (task.deadline != null)
                          _Meta(
                            icon: Icons.schedule,
                            text: DateFormat('dd MMM, h:mm a').format(task.deadline!),
                            colour: task.isOverdue ? context.taskly.danger : null,
                          ),
                        _Meta(
                          icon: task.workspaceKind == 'direct' ? Icons.person : Icons.groups_outlined,
                          text: task.contextName,
                        ),
                      ],
                    ),
                    if (task.subtasks.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      LinearProgressIndicator(value: task.progress, minHeight: 4, borderRadius: BorderRadius.circular(4)),
                      const SizedBox(height: 3),
                      Text('${task.completedSubtasks}/${task.subtasks.length} subtasks', style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (canChange)
                PopupMenuButton<String>(
                  tooltip: 'Change status',
                  initialValue: task.status,
                  onSelected: onStatus,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'todo', child: Text('To Do')),
                    PopupMenuItem(value: 'in-progress', child: Text('In Progress')),
                    PopupMenuItem(value: 'done', child: Text('Completed')),
                  ],
                  child: _StatusPill(status: task.status, interactive: true),
                )
              else
                _StatusPill(status: task.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, this.interactive = false});

  final String status;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = switch (status) {
      'done' => ('Completed', context.taskly.success),
      'in-progress' => ('In Progress', context.taskly.warning),
      _ => ('To Do', context.taskly.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: colour.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: colour,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (interactive) ...[
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: colour),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.colour});

  final IconData icon;
  final String text;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colour ?? context.taskly.textMuted),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 145),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colour ?? context.taskly.textMuted)),
        ),
      ],
    );
  }
}
