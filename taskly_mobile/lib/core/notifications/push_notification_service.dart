import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/navigation/app_destination.dart';
import '../../core/supabase/taskly_supabase.dart';

String _env(String key) {
  switch (key) {
    case 'FIREBASE_API_KEY':
      return const String.fromEnvironment('FIREBASE_API_KEY');
    case 'FIREBASE_APP_ID':
      return const String.fromEnvironment('FIREBASE_APP_ID');
    case 'FIREBASE_ANDROID_API_KEY':
      return const String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
    case 'FIREBASE_ANDROID_APP_ID':
      return const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    case 'FIREBASE_IOS_API_KEY':
      return const String.fromEnvironment('FIREBASE_IOS_API_KEY');
    case 'FIREBASE_IOS_APP_ID':
      return const String.fromEnvironment('FIREBASE_IOS_APP_ID');
    case 'FIREBASE_MESSAGING_SENDER_ID':
      return const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    case 'FIREBASE_PROJECT_ID':
      return const String.fromEnvironment('FIREBASE_PROJECT_ID');
    case 'FIREBASE_STORAGE_BUCKET':
      return const String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    case 'FIREBASE_IOS_BUNDLE_ID':
      return const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  }
  return '';
}

FirebaseOptions? _tasklyFirebaseOptions() {
  final sharedApiKey = _env('FIREBASE_API_KEY');
  final sharedAppId = _env('FIREBASE_APP_ID');
  final apiKey = Platform.isIOS
      ? (_env('FIREBASE_IOS_API_KEY').isNotEmpty
          ? _env('FIREBASE_IOS_API_KEY')
          : sharedApiKey)
      : (_env('FIREBASE_ANDROID_API_KEY').isNotEmpty
          ? _env('FIREBASE_ANDROID_API_KEY')
          : sharedApiKey);
  final appId = Platform.isIOS
      ? (_env('FIREBASE_IOS_APP_ID').isNotEmpty
          ? _env('FIREBASE_IOS_APP_ID')
          : sharedAppId)
      : (_env('FIREBASE_ANDROID_APP_ID').isNotEmpty
          ? _env('FIREBASE_ANDROID_APP_ID')
          : sharedAppId);
  final senderId = _env('FIREBASE_MESSAGING_SENDER_ID');
  final projectId = _env('FIREBASE_PROJECT_ID');
  if (apiKey.isEmpty || appId.isEmpty || senderId.isEmpty || projectId.isEmpty) {
    return null;
  }
  final storageBucket = _env('FIREBASE_STORAGE_BUCKET');
  final iosBundleId = _env('FIREBASE_IOS_BUNDLE_ID');
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
    iosBundleId: Platform.isIOS && iosBundleId.isNotEmpty ? iosBundleId : null,
  );
}

Future<bool> _initialiseFirebase() async {
  if (Firebase.apps.isNotEmpty) return true;

  // Prefer the platform-native Firebase config when the release build contains
  // google-services.json / GoogleService-Info.plist. If it is not present,
  // fall back to the values merged into config/prod.json by Taskly's setup
  // script. A missing configuration returns false instead of leaking a Java /
  // PlatformException into the UI.
  try {
    await Firebase.initializeApp();
    return true;
  } catch (_) {
    final options = _tasklyFirebaseOptions();
    if (options == null) return false;
    await Firebase.initializeApp(options: options);
    return true;
  }
}

@pragma('vm:entry-point')
Future<void> tasklyFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (!await _initialiseFirebase()) return;
  } catch (_) {
    // A missing client Firebase configuration must never crash background work.
  }
}

class PushNotificationService extends ChangeNotifier {
  PushNotificationService();

  static const _messageChannelId = 'taskly_messages';
  static const _messageChannelName = 'Chat messages';
  static const _taskChannelId = 'taskly_tasks';
  static const _taskChannelName = 'Task activity';
  static const _deviceIdKey = 'taskly_device_id';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;
  bool _firebaseReady = false;
  bool _bound = false;
  bool _setupRequired = false;
  String? _configurationError;
  AppDestination? _pendingDestination;
  TasklySupabase? _boundBackend;

  bool get firebaseReady => _firebaseReady;
  bool get setupRequired => _setupRequired;
  String? get configurationError => _configurationError;
  AppDestination? get pendingDestination => _pendingDestination;

  Future<void> initialise() async {
    if (_initialised || kIsWeb) return;
    _initialised = true;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_taskly'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _consumePayload(response.payload);
      },
    );

    if (Platform.isAndroid) {
      const messages = AndroidNotificationChannel(
        _messageChannelId,
        _messageChannelName,
        description: 'Direct and group chat messages',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );
      const tasks = AndroidNotificationChannel(
        _taskChannelId,
        _taskChannelName,
        description: 'Task assignments, updates and status changes',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(messages);
      await android?.createNotificationChannel(tasks);
    }

    try {
      final configured = await _initialiseFirebase();
      if (!configured) {
        _setupRequired = true;
        _configurationError = null;
        notifyListeners();
        return;
      }
      FirebaseMessaging.onBackgroundMessage(
        tasklyFirebaseMessagingBackgroundHandler,
      );
      _firebaseReady = true;
      _setupRequired = false;
      _configurationError = null;
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      FirebaseMessaging.onMessage.listen(_showForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteOpen);
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        final backend = _boundBackend;
        if (backend != null) unawaited(_registerToken(backend, token));
      });
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) _handleRemoteOpen(initialMessage);
      final backend = _boundBackend;
      if (backend != null) unawaited(bindSignedInUser(backend));
    } catch (error) {
      _firebaseReady = false;
      _setupRequired = true;
      _configurationError = 'Notification setup could not start.';
      debugPrint('TASKLY_PUSH_CONFIGURATION $error');
    }
    notifyListeners();
  }

  Future<void> bindSignedInUser(TasklySupabase backend) async {
    _boundBackend = backend;
    if (_bound || !_firebaseReady || kIsWeb) return;
    _bound = true;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        await backend.setPushNotificationsEnabled(false);
        return;
      }
      if (Platform.isAndroid) {
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      if (Platform.isIOS) {
        String? apnsToken;
        for (var attempt = 0; attempt < 8 && apnsToken == null; attempt++) {
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          if (apnsToken == null) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        if (apnsToken == null) throw StateError('APNs token unavailable.');
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _registerToken(backend, token);
    } catch (error) {
      _bound = false;
      debugPrint('TASKLY_PUSH_BIND_ERROR $error');
    }
  }

  Future<void> refreshRegistration() async {
    final backend = _boundBackend;
    if (backend == null || !_firebaseReady) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) await _registerToken(backend, token);
  }

  Future<void> unbind() async {
    final backend = _boundBackend;
    _bound = false;
    _boundBackend = null;
    if (backend == null || !_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await backend.unregisterDeviceToken(token);
      }
    } catch (_) {
      // Signing out must not be blocked by notification cleanup.
    }
  }

  Future<void> _registerToken(TasklySupabase backend, String token) async {
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await preferences.setString(_deviceIdKey, deviceId);
    }
    await backend.registerDeviceToken(
      token: token,
      platform: Platform.isIOS ? 'ios' : 'android',
      deviceId: deviceId,
    );
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type']?.toString() ?? 'message';
    final isTask = type.startsWith('task_') || data['task_id'] != null;
    final notification = message.notification;
    final title = notification?.title ?? data['title']?.toString();
    final body = notification?.body ?? data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) return;

    final channelId = isTask ? _taskChannelId : _messageChannelId;
    final channelName = isTask ? _taskChannelName : _messageChannelName;
    final groupKey = isTask
        ? 'taskly.tasks.${data['workspace_id'] ?? 'general'}'
        : 'taskly.chat.${data['channel_id'] ?? 'general'}';
    final payload = jsonEncode(data);
    await _local.show(
      message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title ?? 'Taskly',
      body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: isTask
              ? 'Task assignments, updates and status changes'
              : 'Direct and group chat messages',
          importance: Importance.high,
          priority: Priority.high,
          category: isTask
              ? AndroidNotificationCategory.event
              : AndroidNotificationCategory.message,
          groupKey: groupKey,
          styleInformation: BigTextStyleInformation(
            body ?? '',
            contentTitle: title ?? 'Taskly',
            summaryText: data['conversation_name']?.toString() ??
                data['group_name']?.toString(),
          ),
          ticker: isTask ? 'Taskly task' : 'Taskly message',
          icon: '@drawable/ic_stat_taskly',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      payload: payload,
    );
  }

  void _handleRemoteOpen(RemoteMessage message) {
    _setDestination(AppDestination.fromMap(message.data));
  }

  void _consumePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final value = jsonDecode(payload);
      if (value is Map) {
        _setDestination(
          AppDestination.fromMap(Map<String, dynamic>.from(value)),
        );
        return;
      }
    } catch (_) {
      final parts = payload.split(':');
      if (parts.length == 2) {
        final id = int.tryParse(parts.last);
        if (id != null) {
          _setDestination(
            parts.first == 'task'
                ? AppDestination(taskId: id)
                : AppDestination(channelId: id),
          );
        }
      }
    }
  }

  void _setDestination(AppDestination destination) {
    if (!destination.isValid) return;
    _pendingDestination = destination;
    notifyListeners();
  }

  AppDestination? takeDestination() {
    final destination = _pendingDestination;
    _pendingDestination = null;
    if (destination != null) notifyListeners();
    return destination;
  }
}
