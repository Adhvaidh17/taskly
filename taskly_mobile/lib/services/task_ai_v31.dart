import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A task suggestion is always owned by one exact chat message.
/// Never display it by using "latest suggestion" or list position.
@immutable
class TaskAiSuggestionV31 {
  const TaskAiSuggestionV31({
    required this.messageId,
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.confidence,
    required this.actionType,
    required this.status,
    this.deadline,
    this.targetTaskId,
    this.aiReason,
    this.assignee,
  });

  final int messageId;
  final int id;
  final String title;
  final String description;
  final String priority;
  final double confidence;
  final String actionType;
  final String status;
  final DateTime? deadline;
  final int? targetTaskId;
  final String? aiReason;
  final Map<String, dynamic>? assignee;

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, dynamic>{};
  }

  factory TaskAiSuggestionV31.fromJson(
    Map<String, dynamic> json, {
    int? expectedMessageId,
  }) {
    final messageId = _int(json['message_id']) ?? expectedMessageId;
    final id = _int(json['id']);
    if (messageId == null || messageId <= 0 || id == null || id <= 0) {
      throw const FormatException('Suggestion has no valid message_id or id.');
    }

    final assigneeJson = _map(json['assignee']);
    return TaskAiSuggestionV31(
      messageId: messageId,
      id: id,
      title: (json['title'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      deadline: DateTime.tryParse((json['deadline'] ?? '').toString()),
      priority: (json['priority'] ?? 'medium').toString(),
      confidence: _double(json['confidence']),
      actionType: (json['action_type'] ?? 'create').toString(),
      targetTaskId: _int(json['target_task_id']),
      aiReason: json['ai_reason']?.toString(),
      status: (json['status'] ?? 'pending').toString(),
      assignee: assigneeJson.isEmpty ? null : assigneeJson,
    );
  }
}

/// Race-free task AI coordinator.
///
/// Flow:
/// 1. The message is inserted and receives its database messageId.
/// 2. analyseMessage(messageId) invokes the Edge Function immediately.
/// 3. The returned suggestion is accepted only when its message_id matches.
/// 4. Realtime and exact RPC lookup are backups, also keyed by message_id.
class TaskAiCoordinatorV31 extends ChangeNotifier {
  TaskAiCoordinatorV31({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Map<int, TaskAiSuggestionV31> _suggestionsByMessageId =
      <int, TaskAiSuggestionV31>{};
  final Map<int, Future<TaskAiSuggestionV31?>> _inFlight =
      <int, Future<TaskAiSuggestionV31?>>{};

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSubscription;
  int? _profileId;
  bool _disposed = false;

  TaskAiSuggestionV31? suggestionForMessage(int messageId) =>
      _suggestionsByMessageId[messageId];

  Map<int, TaskAiSuggestionV31> get suggestionsByMessageId =>
      Map<int, TaskAiSuggestionV31>.unmodifiable(_suggestionsByMessageId);

  void startForProfile(int profileId) {
    if (profileId <= 0 || (_profileId == profileId && _realtimeSubscription != null)) {
      return;
    }
    unawaited(_realtimeSubscription?.cancel());
    _profileId = profileId;

    _realtimeSubscription = _client
        .from('task_suggestions')
        .stream(primaryKey: const ['id'])
        .eq('sender_profile_id', profileId)
        .listen(
      _replaceFromRealtime,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Task AI realtime backup failed: $error');
      },
    );
  }

  /// Call this immediately after the message insert RPC returns its exact id.
  /// Multiple calls for the same message share one Future and never create a
  /// second paid model request.
  Future<TaskAiSuggestionV31?> analyseMessage(
    int messageId, {
    int timezoneOffsetMinutes = 330,
  }) {
    if (messageId <= 0) return Future<TaskAiSuggestionV31?>.value(null);
    final cached = _suggestionsByMessageId[messageId];
    if (cached != null) return Future<TaskAiSuggestionV31?>.value(cached);

    return _inFlight.putIfAbsent(messageId, () async {
      try {
        final response = await _client.functions.invoke(
          'analyse-task-message',
          body: <String, dynamic>{
            'message_id': messageId,
            'timezone_offset_minutes': timezoneOffsetMinutes,
            'source': 'flutter_direct_v31',
          },
        );

        final body = _asMap(response.data);
        final responseMessageId = _asInt(body['message_id']);
        final suggestionJson = _asMap(body['suggestion']);

        // Reject stale/wrong responses. This is the exact fix for a previous
        // message suggestion appearing below the newly sent message.
        if (responseMessageId == messageId && suggestionJson.isNotEmpty) {
          suggestionJson['message_id'] = messageId;
          final suggestion = TaskAiSuggestionV31.fromJson(
            suggestionJson,
            expectedMessageId: messageId,
          );
          _putExact(suggestion);
          return suggestion;
        }

        // Duplicate/already-processing responses are resolved only through an
        // exact message-id RPC; never by fetching the latest suggestion.
        return await _fetchExactWithShortPolling(messageId);
      } on FunctionException catch (error) {
        debugPrint('Task AI function failed for message $messageId: $error');
        return await _fetchExactWithShortPolling(messageId);
      } catch (error, stackTrace) {
        debugPrint('Task AI failed for message $messageId: $error\n$stackTrace');
        return await _fetchExactWithShortPolling(messageId);
      } finally {
        _inFlight.remove(messageId);
      }
    });
  }

  Future<TaskAiSuggestionV31?> _fetchExactWithShortPolling(int messageId) async {
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 120),
      Duration(milliseconds: 220),
      Duration(milliseconds: 360),
    ];
    for (final delay in delays) {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      final suggestion = await fetchExact(messageId);
      if (suggestion != null) return suggestion;
    }
    return null;
  }

  Future<TaskAiSuggestionV31?> fetchExact(int messageId) async {
    try {
      final result = await _client.rpc(
        'taskly_get_message_ai_result_v31',
        params: <String, dynamic>{'p_message_id': messageId},
      );
      final body = _asMap(result);
      if (_asInt(body['message_id']) != messageId) return null;
      final suggestionJson = _asMap(body['suggestion']);
      if (suggestionJson.isEmpty) return null;
      suggestionJson['message_id'] = messageId;
      final suggestion = TaskAiSuggestionV31.fromJson(
        suggestionJson,
        expectedMessageId: messageId,
      );
      _putExact(suggestion);
      return suggestion;
    } catch (error) {
      debugPrint('Exact Task AI lookup failed for message $messageId: $error');
      return null;
    }
  }

  void removeForMessage(int messageId) {
    if (_suggestionsByMessageId.remove(messageId) != null && !_disposed) {
      notifyListeners();
    }
  }

  void _replaceFromRealtime(List<Map<String, dynamic>> rows) {
    var changed = false;
    for (final row in rows) {
      try {
        final suggestion = TaskAiSuggestionV31.fromJson(row);
        final current = _suggestionsByMessageId[suggestion.messageId];
        if (current?.id != suggestion.id || current?.status != suggestion.status) {
          _suggestionsByMessageId[suggestion.messageId] = suggestion;
          changed = true;
        }
      } catch (_) {
        // Ignore incomplete/legacy rows. They cannot be safely correlated.
      }
    }
    if (changed && !_disposed) notifyListeners();
  }

  void _putExact(TaskAiSuggestionV31 suggestion) {
    if (suggestion.status == 'dismissed' || suggestion.status == 'confirmed') {
      _suggestionsByMessageId.remove(suggestion.messageId);
    } else {
      _suggestionsByMessageId[suggestion.messageId] = suggestion;
    }
    if (!_disposed) notifyListeners();
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
    _inFlight.clear();
    super.dispose();
  }
}
