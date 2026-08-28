import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/notifications/task_reminder_service.dart';
import 'core/supabase/taskly_supabase.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/contact_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/task_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/workspace_provider.dart';
import 'screens/complete_phone_screen.dart';
import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';
import 'v62/ai_onboarding_screen_v62.dart';
import 'services/incoming_share_service.dart';
import 'services/local_media_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppConfig.validate();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
    final reminderService = TaskReminderService();
    try {
      await reminderService.initialise();
    } catch (_) {
      // Reminders must never stop Taskly from starting.
    }
    final backend = TasklySupabase(Supabase.instance.client);
    final themeProvider = ThemeProvider();
    final pushService = PushNotificationService();
    final incomingShareService = IncomingShareService();
    final localMediaService = LocalMediaService();
    await Future.wait([
      themeProvider.initialise(),
      incomingShareService.initialise(),
    ]);
    // Push/Firebase setup runs after first paint so it never slows app launch.
    unawaited(pushService.initialise());
    runApp(
      TasklyApp(
        backend: backend,
        reminderService: reminderService,
        themeProvider: themeProvider,
        pushService: pushService,
        incomingShareService: incomingShareService,
        localMediaService: localMediaService,
      ),
    );
  } catch (error) {
    runApp(TasklyStartupErrorApp(message: '$error'));
  }
}

class TasklyApp extends StatelessWidget {
  const TasklyApp({
    super.key,
    required this.backend,
    required this.reminderService,
    required this.themeProvider,
    required this.pushService,
    required this.incomingShareService,
    required this.localMediaService,
  });

  final TasklySupabase backend;
  final TaskReminderService reminderService;
  final ThemeProvider themeProvider;
  final PushNotificationService pushService;
  final IncomingShareService incomingShareService;
  final LocalMediaService localMediaService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(backend)..initialise()),
        ChangeNotifierProvider(create: (_) => WorkspaceProvider(backend)),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(backend, localMediaService),
        ),
        ChangeNotifierProvider(
          create: (_) => TaskProvider(backend, reminderService, localMediaService),
        ),
        ChangeNotifierProvider(create: (_) => DashboardProvider(backend)),
        ChangeNotifierProvider(create: (_) => ContactProvider(backend)),
        ChangeNotifierProvider(create: (_) => NotificationProvider(backend)),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: pushService),
        ChangeNotifierProvider.value(value: incomingShareService),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Taskly',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _pushBound = false;
  bool _onboardingChecked = false;
  bool _showOnboarding = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        if (auth.isAuthenticated && auth.user != null && !_onboardingChecked) {
          _onboardingChecked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final prefs = await SharedPreferences.getInstance();
            final key = 'taskly.v62.onboarding.${auth.user!.id}';
            if (!mounted) return;
            setState(() => _showOnboarding = prefs.getBool(key) != true);
          });
        } else if (!auth.isAuthenticated) {
          _onboardingChecked = false;
          _showOnboarding = false;
        }
        if (auth.isAuthenticated && auth.user != null && !_pushBound) {
          _pushBound = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.read<PushNotificationService>().bindSignedInUser(auth.backend);
            }
          });
        } else if (!auth.isAuthenticated) {
          _pushBound = false;
        }
        if (auth.initialising) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!auth.isAuthenticated) return const LoginScreen();
        if (auth.user == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      auth.error ?? 'Your Taskly profile could not be loaded.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: auth.refreshProfile,
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: auth.logout,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (_showOnboarding && auth.user != null) {
          return AiOnboardingScreenV62(
            onComplete: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('taskly.v62.onboarding.${auth.user!.id}', true);
              if (mounted) setState(() => _showOnboarding = false);
            },
          );
        }
        final phone = auth.user?.phone?.trim() ?? '';
        if (phone.isEmpty) return const CompletePhoneScreen();
        return const ShellScreen();
      },
    );
  }
}

class TasklyStartupErrorApp extends StatelessWidget {
  const TasklyStartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Taskly',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 52,
                          color: context.taskly.danger,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Taskly could not start',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.taskly.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
