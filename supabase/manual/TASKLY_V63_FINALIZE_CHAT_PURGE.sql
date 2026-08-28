-- Run only after every active account/device has completed local migration.
-- This does NOT run automatically.
select public.taskly_finalize_local_chat_purge_v63();
