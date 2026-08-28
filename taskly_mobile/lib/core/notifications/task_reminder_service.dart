import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../models/task.dart';

class TaskReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  Future<void> initialise() async {
    if (kIsWeb) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(settings);

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _ready = true;
  }

  Future<void> syncTasks(
    List<TaskItem> tasks, {
    required int currentProfileId,
  }) async {
    if (!_ready || kIsWeb) return;

    // Taskly currently owns only task-reminder local notifications.
    // Rebuilding the schedule avoids duplicate or stale alarms after edits.
    await _plugin.cancelAll();

    final now = DateTime.now();
    for (final task in tasks) {
      final deadline = task.deadline;
      if (!task.reminderEnabled ||
          deadline == null ||
          task.status == 'done' ||
          task.assignee?.id != currentProfileId) {
        continue;
      }

      final remindAt = deadline.subtract(
        Duration(minutes: task.reminderMinutesBefore),
      );
      if (!remindAt.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        _notificationId(task.id),
        'Task due soon',
        '${task.title} · ${_dueText(deadline)}',
        tz.TZDateTime.from(remindAt.toUtc(), tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'taskly_task_reminders',
            'Task reminders',
            channelDescription: 'Reminders before assigned Taskly tasks are due',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'task:${task.id}',
      );
    }
  }

  Future<void> cancelTask(int taskId) async {
    if (!_ready || kIsWeb) return;
    await _plugin.cancel(_notificationId(taskId));
  }

  int _notificationId(int taskId) => 700000000 + (taskId % 200000000);

  String _dueText(DateTime deadline) {
    final local = deadline.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return 'due ${local.day}/${local.month} at $hour:$minute $period';
  }
}
