# Taskly v6 ChatProvider integration

The v6 transport is intentionally additive so the group/task backend remains
untouched. The current ChatProvider still needs these chat-history methods
routed from Supabase message history to the local SQLite store.

## 1. Imports

Add:

```dart
import '../local_chat/local_chat_runtime.dart';
import '../local_chat/local_ai_task_service.dart';
```

## 2. Remove unavailable-media state

Delete these fields and every UI use of them:

```dart
final Set<int> unavailableAttachmentIds = {};
final Set<int> downloadingAttachmentIds = {};
```

There is no "removed from device" state in v6. Missing/removed media is
physically removed from the local message row; attachment-only messages vanish.

## 3. Initialize the private transport

Near the beginning of `loadConversations()` after auth is available:

```dart
await LocalChatRuntime.instance.initialize(backend.client);

_messageSubscription ??=
    LocalChatRuntime.instance.transport!.channelChanged.listen((channelId) {
  if (messages.containsKey(channelId)) {
    unawaited(_reloadMessages(channelId));
  }
  unawaited(loadConversations());
});
```

Keep `backend.conversations()` and `conversationMembers()` because channel/group
membership is permitted server metadata. Chat bodies are not.

After `loaded` is returned from `backend.conversations()`, overlay local preview:

```dart
final localRows =
    await LocalChatRuntime.instance.database.conversations();
final localByChannel = <int, Map<String, dynamic>>{
  for (final row in localRows)
    (row['channel_id'] as num).toInt(): row,
};

for (var i = 0; i < loaded.length; i++) {
  final row = localByChannel[loaded[i].channelId];
  if (row == null) continue;
  loaded[i] = loaded[i].copyWith(
    lastMessage: row['last_message'] as String?,
    lastSenderName: row['last_sender_name'] as String?,
    lastMessageAt: row['last_message_at'] == null
        ? null
        : DateTime.tryParse(row['last_message_at'] as String),
    unreadCount: (row['unread_count'] as num? ?? 0).toInt(),
  );
}
```

## 4. Replace `_reloadMessages`

```dart
Future<void> _reloadMessages(int channelId) async {
  const pageSize = 80;
  final profileId = currentProfileId ?? await backend.profileId();
  final rows = await LocalChatRuntime.instance.database.messageRows(
    channelId,
    limit: pageSize,
  );

  messages[channelId] = rows
      .map((json) =>
          MessageItem.fromJson(json, currentProfileId: profileId))
      .toList();

  localAttachmentPaths.removeWhere((_, __) => true);
  for (final row in rows) {
    final path = row['attachment_path'] as String?;
    if (path == null || path.isEmpty) continue;
    localAttachmentPaths[(row['id'] as num).toInt()] = path;
  }

  hasOlderMessages[channelId] = rows.length >= pageSize;
  notifyListeners();
}
```

Do not call `_syncLocalMediaForChannel` or download a chat attachment from
Supabase Storage in v6.

## 5. Replace `loadOlderMessages`

Use local SQLite IDs:

```dart
Future<int> loadOlderMessages(int channelId) async {
  if (loadingOlderChannels.contains(channelId) ||
      hasOlderMessages[channelId] == false) {
    return 0;
  }

  final current = messages[channelId] ?? const <MessageItem>[];
  if (current.isEmpty) return 0;

  final beforeId =
      current.map((item) => item.id).where((id) => id > 0).fold<int?>(
    null,
    (value, id) => value == null || id < value ? id : value,
  );
  if (beforeId == null) return 0;

  loadingOlderChannels.add(channelId);
  notifyListeners();
  try {
    const pageSize = 80;
    final profileId = currentProfileId ?? await backend.profileId();
    final rows = await LocalChatRuntime.instance.database.messageRows(
      channelId,
      limit: pageSize,
      beforeLocalId: beforeId,
    );
    final older = rows
        .map((json) =>
            MessageItem.fromJson(json, currentProfileId: profileId))
        .where((item) => !current.any((known) => known.id == item.id))
        .toList();

    messages[channelId] = [...older, ...current]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final row in rows) {
      final path = row['attachment_path'] as String?;
      if (path != null && path.isNotEmpty) {
        localAttachmentPaths[(row['id'] as num).toInt()] = path;
      }
    }

    hasOlderMessages[channelId] = rows.length >= pageSize;
    return older.length;
  } finally {
    loadingOlderChannels.remove(channelId);
    notifyListeners();
  }
}
```

## 6. Replace `send`

Keep the existing optimistic bubble if you want it. Replace only the network
insert section with:

```dart
final row = await LocalChatRuntime.instance.transport!.sendText(
  workspaceId: conversation.workspaceId,
  channelId: conversation.channelId,
  body: cleanBody,
  replyToClientId: replyToMessageId == null
      ? null
      : (await LocalChatRuntime.instance.database
              .messageByLocalId(replyToMessageId))?['client_message_id']
          as String?,
);

final inserted =
    MessageItem.fromJson(row, currentProfileId: profileId);

_upsertMessage(
  conversation.channelId,
  inserted,
  replaceMessageId: optimisticId,
);

final localAi = LocalAiTaskService(
  client: backend.client,
  database: LocalChatRuntime.instance.database,
);
if (showTaskCheck) {
  unawaited(
    localAi.analyse(
      clientMessageId: row['client_message_id'] as String,
      workspaceId: conversation.workspaceId,
      channelId: conversation.channelId,
      text: cleanBody,
      timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    ),
  );
}
```

The AI Edge Function sees only the current message transiently. It does not
store the chat body.

## 7. Replace `sendAttachment`

Replace the call to `backend.uploadMessageAttachment(...)` with:

```dart
final row = await LocalChatRuntime.instance.transport!.sendAttachment(
  workspaceId: conversation.workspaceId,
  channelId: conversation.channelId,
  sourcePath: prepared.path,
  mimeType: prepared.mimeType,
  replyToClientId: replyToMessageId == null
      ? null
      : (await LocalChatRuntime.instance.database
              .messageByLocalId(replyToMessageId))?['client_message_id']
          as String?,
);
```

Parse it using the existing `MessageItem.fromJson`, then:

```dart
final path = row['attachment_path'] as String?;
if (path != null) localAttachmentPaths[item.id] = path;
```

Do not upload chat media to the old permanent message bucket.

## 8. Edit / delete / react / pin

Local IDs must be converted to stable `client_message_id`:

```dart
Future<String?> _clientMessageId(int localId) async {
  final row =
      await LocalChatRuntime.instance.database.messageByLocalId(localId);
  return row?['client_message_id'] as String?;
}

Future<void> editMessage(int channelId, int messageId, String body) async {
  final id = await _clientMessageId(messageId);
  if (id == null) return;
  await LocalChatRuntime.instance.transport!.editMessage(
    channelId: channelId,
    clientMessageId: id,
    body: body,
  );
  await _reloadMessages(channelId);
}

Future<void> deleteMessage(int channelId, int messageId) async {
  final id = await _clientMessageId(messageId);
  if (id == null) return;
  await LocalChatRuntime.instance.transport!.deleteForEveryone(
    channelId: channelId,
    clientMessageId: id,
  );
  await _reloadMessages(channelId);
}

Future<void> pin(int channelId, int messageId, bool pinned) async {
  final id = await _clientMessageId(messageId);
  if (id == null) return;
  await LocalChatRuntime.instance.transport!.setPinned(
    channelId: channelId,
    clientMessageId: id,
    pinned: pinned,
  );
  await _reloadMessages(channelId);
}
```

For reaction toggle, inspect `reactions_json` for the current profile and call
`setReaction(...)` with `enabled` true/false.

## 9. Remove media from phone

Do not call `refreshLocalMedia` or record an unavailable ID:

```dart
Future<void> removeAttachmentFromDevice(
  int channelId,
  int messageId,
) async {
  final row =
      await LocalChatRuntime.instance.database.messageByLocalId(messageId);
  final id = row?['client_message_id'] as String?;
  if (id == null) return;

  await LocalChatRuntime.instance.transport!.removeAttachmentFromDevice(
    channelId: channelId,
    clientMessageId: id,
  );
  localAttachmentPaths.remove(messageId);
  await _reloadMessages(channelId);
}
```

## 10. Clear/delete chat

These are local history operations:

```dart
Future<void> clearChat(ConversationItem conversation) async {
  await LocalChatRuntime.instance.database.clearChat(conversation.channelId);
  messages[conversation.channelId] = [];
  notifyListeners();
  await loadConversations();
}

Future<void> deleteChat(ConversationItem conversation) async {
  await LocalChatRuntime.instance.database
      .deleteConversation(conversation.channelId);
  messages.remove(conversation.channelId);
  await loadConversations();
}
```

Keep group creation/joining/admin/member management on Supabase.

## 11. Dispose

Keep your existing subscriptions and also:

```dart
_messageSubscription?.cancel();
_messageSubscription = null;
```

The global runtime is closed on account sign-out using:

```dart
await LocalChatRuntime.instance.signOutCleanup();
```
