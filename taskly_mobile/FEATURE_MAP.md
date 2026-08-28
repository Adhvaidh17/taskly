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

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await backend.profile();
      items = (await backend.notifications()).map(TasklyNotification.fromJson).toList();
      _subscription ??= backend.notificationChanges().listen((_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), load);
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
    await backend.markNotificationRead(item.id);
    await load();
  }

  Future<void> markAllRead() async {
    await backend.markAllNotificationsRead();
    await load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
