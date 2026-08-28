class AppDestination {
  const AppDestination({this.channelId, this.taskId});

  final int? channelId;
  final int? taskId;

  bool get isValid => channelId != null || taskId != null;

  factory AppDestination.fromMap(Map<String, dynamic> data) {
    int? parse(Object? value) {
      if (value is int) return value;
      return int.tryParse('$value');
    }

    return AppDestination(
      channelId: parse(data['channel_id'] ?? data['channelId']),
      taskId: parse(data['task_id'] ?? data['taskId']),
    );
  }
}
