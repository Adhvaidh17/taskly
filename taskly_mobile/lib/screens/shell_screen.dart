import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/notifications/push_notification_service.dart';
import '../providers/chat_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/task_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/incoming_share_service.dart';
import 'chat_room_screen.dart';
import 'chats_screen.dart';
import 'dashboard_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'incoming_share_sheet.dart';
import 'task_detail_screen.dart';
import '../v62/ai_universe_shell_v62.dart';
import 'tasks_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with WidgetsBindingObserver {
  int _index = 0;
  bool _loaded = false;
  bool _listenersBound = false;
  PushNotificationService? _push;
  IncomingShareService? _shares;

  static const _titles = ['Chats', 'Tasks', 'Dashboard', 'Profile'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<ChatProvider>().loadConversations());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listenersBound) {
      _listenersBound = true;
      _push = context.read<PushNotificationService>()..addListener(_handlePush);
      _shares = context.read<IncomingShareService>()..addListener(_handleShare);
    }
    if (_loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<WorkspaceProvider>().load();
      if (!mounted) return;
      await Future.wait([
        context.read<ChatProvider>().loadConversations(),
        context.read<TaskProvider>().load(),
        context.read<DashboardProvider>().load(),
        context.read<NotificationProvider>().load(),
      ]);
    });
  }

  Future<void> _handlePush() async {
    final destination = _push?.takeDestination();
    if (destination == null || !mounted) return;
    if (destination.taskId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: destination.taskId!)),
      );
      return;
    }
    if (destination.channelId != null && mounted) {
      final chat = context.read<ChatProvider>();
      if (chat.conversations.isEmpty) await chat.loadConversations();
      if (!mounted) return;
      final matches = chat.conversations.where((item) => item.channelId == destination.channelId);
      if (matches.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: matches.first)),
        );
      }
    }
  }

  Future<void> _handleShare() async {
    final payload = _shares?.consume();
    if (payload == null || !mounted) return;
    if (context.read<ChatProvider>().conversations.isEmpty) {
      await context.read<ChatProvider>().loadConversations();
    }
    if (mounted) await showIncomingShareFlow(context, payload);
  }

  @override
  void dispose() {
    _push?.removeListener(_handlePush);
    _shares?.removeListener(_handleShare);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<NotificationProvider>();
    final scheme = Theme.of(context).colorScheme;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: surface,
      extendBody: false,
      appBar: AppBar(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Text('T', style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onPrimary)),
            ),
            const SizedBox(width: 9),
            Text(_titles[_index], style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            icon: Badge(
              isLabelVisible: notifications.unreadCount > 0,
              label: Text('${notifications.unreadCount}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AiUniverseShellV62(
        intensity: 0.10,
        showStars: false,
        child: IndexedStack(
          index: _index,
          children: const [
            ChatsScreen(),
            TasksScreen(),
            DashboardScreen(),
            ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.task_alt_outlined), selectedIcon: Icon(Icons.task_alt), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
