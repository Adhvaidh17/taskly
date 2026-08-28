import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../providers/dashboard_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final summary = provider.summary;
    return RefreshIndicator(
      onRefresh: provider.load,
      child: provider.loading && summary.isEmpty
          ? ListView(children: [const SizedBox(height: 240), const Center(child: CircularProgressIndicator())])
          : ListView(
              key: const PageStorageKey('dashboard'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 8) / 2;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatCard(width: width, label: 'All visible tasks', value: _number(summary['total']), icon: Icons.assignment_outlined),
                        _StatCard(width: width, label: 'Assigned to me', value: _number(summary['assigned_to_me']), icon: Icons.assignment_ind_outlined, colour: Theme.of(context).colorScheme.primary),
                        _StatCard(width: width, label: 'Assigned by me', value: _number(summary['assigned_by_me']), icon: Icons.outbox_outlined, colour: context.taskly.info),
                        _StatCard(width: width, label: 'Completed', value: _number(summary['done']), icon: Icons.task_alt, colour: context.taskly.success),
                        _StatCard(width: width, label: 'In progress', value: _number(summary['in_progress']), icon: Icons.timelapse, colour: context.taskly.warning),
                        _StatCard(width: width, label: 'Overdue', value: _number(summary['overdue']), icon: Icons.warning_amber_rounded, colour: context.taskly.danger),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Task status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 14),
                        _StatusBar(label: 'To Do', value: _int(summary['todo']), total: _int(summary['total']), colour: context.taskly.danger),
                        const SizedBox(height: 12),
                        _StatusBar(label: 'In Progress', value: _int(summary['in_progress']), total: _int(summary['total']), colour: context.taskly.warning),
                        const SizedBox(height: 12),
                        _StatusBar(label: 'Completed', value: _int(summary['done']), total: _int(summary['total']), colour: context.taskly.success),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('People workload', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (provider.members.isEmpty)
                  Card(child: Padding(padding: const EdgeInsets.all(18), child: Text('No task data yet.', style: TextStyle(color: context.taskly.textMuted))))
                else
                  ...provider.members.map((member) => _MemberWorkload(data: member)),
              ],
            ),
    );
  }

  static int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
  static String _number(dynamic value) => '${_int(value)}';
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    this.colour,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final accent = colour ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: width,
      height: 112,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 17, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: context.taskly.textMuted, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 31, height: 1, color: accent, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.label, required this.value, required this.total, required this.colour});

  final String label;
  final int value;
  final int total;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : value / total;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('$value', style: TextStyle(color: colour, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(value: ratio, color: colour, minHeight: 7, borderRadius: BorderRadius.circular(10)),
      ],
    );
  }
}

class _MemberWorkload extends StatelessWidget {
  const _MemberWorkload({required this.data});

  final Map<String, dynamic> data;

  int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

  @override
  Widget build(BuildContext context) {
    final total = _int(data['total']);
    final done = _int(data['done']);
    final overdue = _int(data['overdue']);
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${data['name'] ?? '?'}'.substring(0, 1).toUpperCase())),
        title: Text('${data['name'] ?? 'Unknown'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 6,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        trailing: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$done/$total', style: const TextStyle(fontWeight: FontWeight.w800)),
              if (overdue > 0) Text('$overdue overdue', maxLines: 1, style: TextStyle(fontSize: 10, color: context.taskly.danger)),
            ],
          ),
        ),
      ),
    );
  }
}
