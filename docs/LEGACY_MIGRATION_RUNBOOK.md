# Legacy server-chat migration runbook

Do this once per existing account before purging legacy chat rows.

## Goal

Every currently accessible legacy message is copied into the signed-in user's
local SQLite database. Existing locally downloaded attachments must be bound to
the migrated row when available. No server row is deleted during this step.

## Use `LegacyChatMigrationService`

In your migration/startup screen, create it with the existing backend methods:

```dart
final migrator = LegacyChatMigrationService(
  database: LocalChatRuntime.instance.database,
  fetchConversations: () => backend.conversations(),
  fetchMessages: (channelId, beforeId, limit) async {
    // Use your current paged server-message method here.
    // Return the same JSON maps your existing MessageItem.fromJson consumes.
    return backend.messages(
      channelId,
      beforeId: beforeId,
      limit: limit,
    );
  },
);

final report = await migrator.run();
```

If your backend method uses different argument names, adapt only the callback.

## Existing media

Before migration, open the existing app once and let its current local-media
sync finish. When your legacy message JSON already knows the downloaded path,
put it in either:

```text
local_attachment_path
```

or:

```text
attachment_local_path
```

The migrator will bind that path.

If an old attachment exists only in Supabase Storage, download/copy it to the
v6 app media directory first. Do not purge the old storage object until the
v6 encrypted backup has been verified.

## Verification

After `run()`:

```dart
final localCount =
    await LocalChatRuntime.instance.database.messageCount();

debugPrint(
  'legacy migrated messages=${report.messages}, '
  'local total=$localCount',
);
```

Then:

1. Open multiple old direct chats and groups.
2. Open images/documents from old chats.
3. Settings -> Chats -> Chat backup -> **Back up now**.
4. Confirm `first_verified_backup` is present locally.
5. Preferably restore on a second test Android phone.
6. Only then manually run:

`supabase/manual/AFTER_VERIFIED_BACKUP_PURGE_LEGACY_CHATS.sql`

The purge is intentionally outside `supabase/migrations` so normal migration
commands cannot erase history accidentally.
