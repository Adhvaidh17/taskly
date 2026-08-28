import 'package:flutter/foundation.dart';

import '../services/task_ai_v31.dart';

/// Optional provider wrapper. Existing ChatProvider can own this object directly
/// without adding another package or changing unrelated application state.
class TaskAiProviderV31 extends ChangeNotifier {
  TaskAiProviderV31({TaskAiCoordinatorV31? coordinator})
      : coordinator = coordinator ?? TaskAiCoordinatorV31() {
    this.coordinator.addListener(_relay);
  }

  final TaskAiCoordinatorV31 coordinator;

  TaskAiSuggestionV31? forMessage(int messageId) =>
      coordinator.suggestionForMessage(messageId);

  void start(int profileId) => coordinator.startForProfile(profileId);

  Future<TaskAiSuggestionV31?> analyse(
    int messageId, {
    int timezoneOffsetMinutes = 330,
  }) =>
      coordinator.analyseMessage(
        messageId,
        timezoneOffsetMinutes: timezoneOffsetMinutes,
      );

  void _relay() => notifyListeners();

  @override
  void dispose() {
    coordinator.removeListener(_relay);
    coordinator.dispose();
    super.dispose();
  }
}
