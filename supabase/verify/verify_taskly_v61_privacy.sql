-- Read-only-style privacy verification for Taskly v6.1.
-- This script changes no user data. It prints NOTICE lines for dynamic checks.

DO $$
DECLARE n bigint := 0;
BEGIN
  IF to_regclass('public.messages') IS NOT NULL THEN
    EXECUTE 'select count(*) from public.messages' INTO n;
  END IF;
  RAISE NOTICE 'messages = % (expected 0)', n;
END $$;

DO $$
DECLARE n bigint := 0;
BEGIN
  IF to_regclass('public.notifications') IS NOT NULL AND EXISTS(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='notifications' and column_name='type'
  ) THEN
    EXECUTE $q$select count(*) from public.notifications where lower(coalesce(type,'')) in ('message','chat_message','new_message','mention')$q$ INTO n;
  END IF;
  RAISE NOTICE 'message_notifications = % (expected 0)', n;
END $$;

DO $$
DECLARE n bigint := 0;
BEGIN
  IF to_regclass('public.attachments') IS NOT NULL AND EXISTS(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='attachments' and column_name='message_id'
  ) THEN
    EXECUTE 'select count(*) from public.attachments where message_id is not null' INTO n;
  END IF;
  RAISE NOTICE 'message_attachment_metadata = % (expected 0)', n;
END $$;


-- Tasks are preserved, but old direct pointers/verbatim message copies are removed.
DO $$
DECLARE n bigint := 0;
BEGIN
  IF to_regclass('public.tasks') IS NOT NULL AND EXISTS(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='tasks' and column_name='source_message_id'
  ) THEN
    EXECUTE 'select count(*) from public.tasks where source_message_id is not null' INTO n;
  END IF;
  RAISE NOTICE 'task_source_message_links = % (expected 0)', n;
END $$;

DO $$
DECLARE n bigint := 0;
BEGIN
  IF to_regclass('public.tasks') IS NOT NULL AND EXISTS(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='tasks' and column_name='origin_text'
  ) THEN
    EXECUTE $q$select count(*) from public.tasks where nullif(trim(origin_text),'') is not null$q$ INTO n;
  END IF;
  RAISE NOTICE 'task_origin_text_copies = % (expected 0)', n;
END $$;

-- Inspect server columns that may accidentally contain chat-like bodies/content.
-- Task/task-comment fields may legitimately appear here; review those separately.
select table_name, column_name, data_type
from information_schema.columns
where table_schema='public'
  and (
    column_name ilike '%message%'
    or column_name in ('body','content','raw_text','transcript','attachment_path','storage_path')
  )
order by table_name,column_name;

-- Device registry contains only account/device metadata.
select profile_id, device_id, device_name, platform, is_primary, is_active,
       registered_at, last_seen_at, replaced_at
from public.taskly_primary_devices_v61
order by profile_id, registered_at desc;


-- Older NLU feedback/aliases previously retained raw phrases/message text.
DO $$
DECLARE rel text; n bigint;
BEGIN
  FOREACH rel IN ARRAY ARRAY['task_ai_feedback','task_ai_decisions','task_ai_runs','task_ai_jobs_v30','task_ai_user_aliases'] LOOP
    n := 0;
    IF to_regclass('public.' || rel) IS NOT NULL THEN
      EXECUTE format('select count(*) from public.%I', rel) INTO n;
    END IF;
    RAISE NOTICE '% = % (expected 0 for legacy chat-derived AI data)', rel, n;
  END LOOP;
END $$;

-- Read-only check for legacy message media that may still exist in Storage.
-- If this count is nonzero, run the purge-legacy-chat-storage-v61 function
-- BEFORE deleting public.messages, because the old rows contain the exact paths.
DO $$
DECLARE n bigint := 0;
BEGIN
  IF to_regclass('storage.objects') IS NOT NULL THEN
    SELECT count(*) INTO n
    FROM storage.objects
    WHERE bucket_id='task-files'
      AND name LIKE '%/messages/%';
  END IF;
  RAISE NOTICE 'legacy_storage_message_objects = % (expected 0)', n;
END $$;
