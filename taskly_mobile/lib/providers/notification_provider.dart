import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/supabase/taskly_supabase.dart';
import '../models/notification.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider(this.backend);

  final TasklySupabase backend;
  List<TasklyNotification> items = [];
  bool loading = false;
  String? error;
  StreamSubscription<void>? _subscription;
  Timer? _debounce;

  int get unreadCount => items.where((item) => !item.isRead).length;

  Future<void> load({bool background = false}) async {
    if (!background) loading = true;
    error = null;
    if (!background) notifyListeners();
    try {
      await backend.profile();
      items = (await backend.notifications()).map(TasklyNotification.fromJson).toList();
      _subscription ??= backend.notificationChanges().listen((_) {
        if (_debounce?.isActive == true) return;
        _debounce = Timer(const Duration(milliseconds: 90), () {
          unawaited(load(background: true));
        });
      });
    } catch (exception) {
      error = '$exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(TasklyNotification item) async {
    if (item.isRead) return;
    final index = items.indexWhere((value) => value.id == item.id);
    if (index >= 0) {
      items[index] = _readCopy(items[index]);
      notifyListeners();
    }
    try {
      await backend.markNotificationRead(item.id);
    } catch (exception) {
      error = '$exception';
      unawaited(load(background: true));
    }
  }

  Future<void> markAllRead() async {
    items = items.map(_readCopy).toList(growable: false);
    notifyListeners();
    try {
      await backend.markAllNotificationsRead();
    } catch (exception) {
      error = '$exception';
      unawaited(load(background: true));
    }
  }

  TasklyNotification _readCopy(TasklyNotification item) => TasklyNotification(
        id: item.id,
        type: item.type,
        title: item.title,
        body: item.body,
        isRead: true,
        createdAt: item.createdAt,
        taskId: item.taskId,
        channelId: item.channelId,
        messageId: item.messageId,
        workspaceId: item.workspaceId,
        actor: item.actor,
      );

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
