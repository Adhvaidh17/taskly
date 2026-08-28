-- RUN ONLY AFTER ALL ACTIVE DEVICES HAVE BEEN RECOVERED AND VERIFIED.
-- This is intentionally NOT run by the Flutter client.
-- Execute in Supabase SQL Editor as an administrator.
select public.taskly_chat_purge_readiness_v63();

-- The function refuses to purge unless every active primary device has
-- acknowledged a complete local copy.
select public.taskly_finalize_local_chat_purge_v63();
