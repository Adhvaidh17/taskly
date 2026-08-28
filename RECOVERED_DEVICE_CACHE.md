# Recovered device cache detected

The supplied Android data contains the legacy v43 cache. The app now imports
these files automatically into the account-scoped local SQLite database and
keeps the cache files intact.

Detected message snapshots:
- channel 4: 50 messages (two identical namespace snapshots)
- channel 21: 35 messages
- channel 22: 59 messages
- channel 23: 2 messages
- channel 25: 2 messages

The importer skips rows with `deleted_at`, removes attachment metadata when the
actual media file is absent, and matches existing media by filename under
`Taskly/Media`.

Do not clear the Taskly `.cache` folder before first launch of this build.
