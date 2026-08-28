import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'core/supabase/taskly_supabase.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/contact_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/task_provider.dart';
import 'providers/workspace_provider.dart';
import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppConfig.validate();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
    runApp(TasklyApp(backend: TasklySupabase(Supabase.instance.client)));
  } catch (error) {
    runApp(TasklyStartupErrorApp(message: '$error'));
  }
}

class TasklyApp extends StatelessWidget {
  const TasklyApp({super.key, required this.backend});

  final TasklySupabase backend;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(backend)..initialise()),
        ChangeNotifierProvider(create: (_) => WorkspaceProvider(backend)),
        ChangeNotifierProvider(create: (_) => ChatProvider(backend)),
        ChangeNotifierProvider(create: (_) => TaskProvider(backend)),
        ChangeNotifierProvider(create: (_) => DashboardProvider(backend)),
        ChangeNotifierProvider(create: (_) => ContactProvider(backend)),
        ChangeNotifierProvider(create: (_) => NotificationProvider(backend)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Taskly',
        theme: AppTheme.dark(),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        if (auth.initialising) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return auth.isAuthenticated ? const ShellScreen() : const LoginScreen();
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
      home: Scaffold(
        backgroundColor: const Color(0xFF0C0E1A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 52, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  const Text(
                    'Taskly could not start',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
