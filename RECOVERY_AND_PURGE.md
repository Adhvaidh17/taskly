# Taskly chat recovery / purge

The Android v43 cache remains authoritative recovery input. The app imports the
current account's `<auth-user-id>_channel_*_messages_v43.json` and
`<auth-user-id>_conversations_v43.json` files into its per-account SQLite store.
The cache files are not deleted by recovery.

Existing Android media under `Taskly/Media` is matched by attachment filename
and retained locally.

New local messages are also snapshotted back into the account's `.cache`
folder, so reopening the app can recover the transcript even if the SQLite
index is damaged.

Do NOT run the purge until the app has been opened online on every active
primary device/account and the recovery count has been checked.

The SQL in `supabase/ops/PURGE_CHAT_MESSAGES_AFTER_RECOVERY.sql` is the
explicit destructive step. It is intentionally not executed by the mobile
client.
