# Taskly v6 app-shell / UI integration

## Theme

In `MaterialApp` use:

```dart
theme: TasklyAiTheme.light(),
darkTheme: TasklyAiTheme.dark(),
themeMode: ThemeMode.system,
```

Import:

```dart
import 'core/theme/taskly_ai_theme.dart';
```

## Login

Keep your existing OTP/auth logic. Wrap only the visual login body with
`AiAuthShell` so no authentication behavior changes.

```dart
AiAuthShell(
  child: YourExistingLoginForm(),
)
```

## After login / new phone

Wrap the normal signed-in dashboard:

```dart
TasklyPostLoginGateV60(
  client: Supabase.instance.client,
  child: const DashboardScreen(),
)
```

This implements the WhatsApp-like order:
account verification -> restore from Google Drive / transfer from old phone /
skip -> tutorial -> app.

## New Chat

Remove Create Group and Groups list from Profile.

Use:

```dart
showModalBottomSheet(
  context: context,
  showDragHandle: true,
  builder: (_) => NewChatSheetV60(
    contacts: yourContactsWidget,
    onCreateGroup: openCreateGroup,
    onJoinGroup: openJoinGroup,
    onNewContact: openNewContact,
  ),
);
```

No group list belongs inside this sheet.

## Chat Info

Open `ChatInfoScreenV60` from tapping the chat header. The screen includes
Media / Links / Docs, starred messages, search, mute, disappearing messages,
chat lock, advanced privacy, encryption, storage, clear/delete/block/report and
group controls. Keep existing backend callbacks for group membership/admin.

## Settings -> Chats -> Chat backup

Create `ChatBackupService` using the current signed-in auth user, local DB,
attachment store, `BackupKeyService` and `GoogleDriveBackupService`, then open
`ChatBackupScreen`.

Automatic schedule settings are stored locally by the screen. Wire your
existing Android background scheduler/WorkManager to call `backUpNow()` at the
selected daily/weekly/monthly cadence.

## Old-phone transfer

On the old phone open `TransferChatsSourceScreen`.
On the new phone the restore gate opens `TransferChatsReceiveScreen`.
Both phones must be on the same Wi-Fi.

## Important migration rule

Do NOT run `AFTER_VERIFIED_BACKUP_PURGE_LEGACY_CHATS.sql` until:
1. all old server chat rows were copied to SQLite on the phone, and
2. the first encrypted Google Drive backup completed and was verified.

The purge file is intentionally separate so an accidental SQL run cannot erase
legacy chat history before a safe copy exists.
