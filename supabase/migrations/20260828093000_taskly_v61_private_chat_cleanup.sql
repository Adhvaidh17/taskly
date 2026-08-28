-- Taskly v6.1 - private/local chat history hardening
-- 2026-08-28
-- Goal:
--   * keep tasks/task details + account/group metadata in Supabase
--   * remove legacy permanent chat history/message previews
--   * keep message/media history on user devices and encrypted user backup only
--   * never keep a "removed attachment" tombstone/list
--
-- IMPORTANT: this migration intentionally does NOT delete tasks, task comments,
-- task attachments, profiles, workspaces, channels, or memberships.

begin;

-- ---------------------------------------------------------------------------
-- 1) Remove legacy server-side message-derived data.
-- ---------------------------------------------------------------------------

do $$
declare
  rel text;
  has_message_id boolean;
begin
  -- Delete child/message-derived rows first so FK constraints cannot block purge.
  foreach rel in array array[
    'message_reactions',
    'message_reads',
    'message_receipts',
    'message_mentions',
    'message_edits',
    'message_delivery',
    'message_deliveries',
    'task_suggestions'
  ] loop
    if to_regclass('public.' || rel) is not null then
      select exists(
        select 1 from information_schema.columns
        where table_schema='public' and table_name=rel and column_name='message_id'
      ) into has_message_id;
      -- v6.3: destructive purge is deferred until every active device has acknowledged a local copy.
      null;
    end if;
  end loop;

  -- Older AI/NLU versions persisted raw chat-derived learning/telemetry.
  -- v6.1 moves this learning local-only, so purge those rows too while
  -- preserving final task records in public.tasks.
  foreach rel in array array[
    'task_ai_feedback',
    'task_ai_decisions',
    'task_ai_runs',
    'task_ai_jobs_v30',
    'task_ai_user_aliases'
  ] loop
      -- Deferred to taskly_finalize_local_chat_purge_v63.
      null;
  end loop;

  -- Message-scoped attachment metadata only. Task-scoped attachment metadata is kept.
  if to_regclass('public.attachments') is not null and exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='attachments' and column_name='message_id'
  ) then
      -- Deferred to taskly_finalize_local_chat_purge_v63.
      null;
  end if;

  -- Remove notification previews that contain chat message text / filenames.
  if to_regclass('public.notifications') is not null and exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='notifications' and column_name='type'
  ) then
    -- Deferred to taskly_finalize_local_chat_purge_v63.
    null;
  end if;

  -- Preserve task records while removing their pointer/copy of the old chat.
  -- Historical schemas used source_message_id + origin_text for AI-created tasks;
  -- source_message_id would otherwise block deleting public.messages and
  -- origin_text can be a verbatim chat copy, which v6.1 must not retain.
  if to_regclass('public.tasks') is not null then
    if exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name='tasks' and column_name='source_message_id'
    ) then
      execute 'update public.tasks set source_message_id=null where source_message_id is not null';
    end if;
    if exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name='tasks' and column_name='origin_text'
    ) then
      execute 'update public.tasks set origin_text=null where origin_text is not null';
    end if;
  end if;

  -- Any non-chat notification row that happens to reference a message may stay,
  -- but it must not keep a foreign-key pointer to the deleted transcript.
  if to_regclass('public.notifications') is not null and exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='notifications' and column_name='message_id'
  ) then
    execute 'update public.notifications set message_id=null where message_id is not null';
  end if;

  -- Finally purge the old permanent transcript table.
    -- Deferred to taskly_finalize_local_chat_purge_v63.
    null;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Old "removed attachment" lists are empty forever.
--    We retain table schemas if an old build still references them, but clear rows.
-- ---------------------------------------------------------------------------

do $$
declare
  rel text;
begin
  foreach rel in array array[
    'removed_attachments',
    'deleted_attachments',
    'attachment_tombstones',
    'removed_message_attachments'
  ] loop
    if to_regclass('public.' || rel) is not null then
      execute format('delete from public.%I', rel);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 3) Prevent permanent transcript writes from coming back.
--    v6.1 transport must use the v60 local/encrypted transport path, not public.messages.
-- ---------------------------------------------------------------------------

create or replace function public.taskly_reject_persistent_chat_v61()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  raise exception using
    errcode='42501',
    message='Taskly v6.1 does not persist chat transcripts in Supabase. Use local/encrypted chat transport.';
end;
$$;

-- Do not store chat notification previews on the server either.
create or replace function public.taskly_reject_message_notification_v61()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if lower(coalesce(new.type,'')) in ('message','chat_message','new_message','mention') then
    return null;
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.messages') is not null then
    drop trigger if exists taskly_block_persistent_chat_v61 on public.messages;
    create trigger taskly_block_persistent_chat_v61
      before insert or update on public.messages
      for each row execute function public.taskly_reject_persistent_chat_v61();
  end if;

  if to_regclass('public.notifications') is not null then
    drop trigger if exists taskly_block_message_notification_v61 on public.notifications;
    create trigger taskly_block_message_notification_v61
      before insert or update on public.notifications
      for each row execute function public.taskly_reject_message_notification_v61();
  end if;
end $$;

-- Disable known legacy message-notification trigger if it still exists.
do $$
declare
  r record;
begin
  if to_regclass('public.messages') is not null then
    for r in
      select tgname
      from pg_trigger
      where tgrelid='public.messages'::regclass
        and not tgisinternal
        and tgname <> 'taskly_block_persistent_chat_v61'
        and (tgname ilike '%notification%' or tgname ilike '%message%notify%')
    loop
      execute format('drop trigger if exists %I on public.messages', r.tgname);
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4) WhatsApp-style PRIMARY-device registry.
--    This stores device/account metadata only, never chat contents.
-- ---------------------------------------------------------------------------

create table if not exists public.taskly_primary_devices_v61 (
  id bigint generated by default as identity primary key,
  profile_id bigint not null references public.profiles(id) on delete cascade,
  device_id text not null,
  device_name text,
  platform text,
  is_primary boolean not null default true,
  is_active boolean not null default true,
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  replaced_at timestamptz,
  unique(profile_id, device_id)
);

create unique index if not exists taskly_primary_devices_v61_one_primary_idx
  on public.taskly_primary_devices_v61(profile_id)
  where is_primary=true and is_active=true;

alter table public.taskly_primary_devices_v61 enable row level security;

drop policy if exists taskly_primary_devices_v61_select_own on public.taskly_primary_devices_v61;
create policy taskly_primary_devices_v61_select_own
on public.taskly_primary_devices_v61 for select
to authenticated
using (profile_id=public.current_profile_id());

-- Direct client mutation is intentionally blocked; use RPCs below.
revoke insert, update, delete on public.taskly_primary_devices_v61 from authenticated;
grant select on public.taskly_primary_devices_v61 to authenticated;

create or replace function public.taskly_register_primary_device_v61(
  p_device_id text,
  p_device_name text default null,
  p_platform text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile bigint := public.current_profile_id();
  v_known boolean := false;
  v_previous text;
begin
  if v_profile is null then
    raise exception 'No Taskly profile for this account';
  end if;
  if nullif(trim(coalesce(p_device_id,'')),'') is null then
    raise exception 'device_id is required';
  end if;

  select exists(
    select 1 from public.taskly_primary_devices_v61
    where profile_id=v_profile and device_id=p_device_id
  ) into v_known;

  select device_id into v_previous
  from public.taskly_primary_devices_v61
  where profile_id=v_profile and is_primary=true and is_active=true
  limit 1;

  update public.taskly_primary_devices_v61
  set is_primary=false,
      is_active=false,
      replaced_at=now(),
      last_seen_at=now()
  where profile_id=v_profile
    and device_id<>p_device_id
    and (is_primary=true or is_active=true);

  insert into public.taskly_primary_devices_v61(
    profile_id,device_id,device_name,platform,is_primary,is_active,
    registered_at,last_seen_at,replaced_at
  ) values(
    v_profile,p_device_id,nullif(trim(p_device_name),''),nullif(trim(p_platform),''),
    true,true,now(),now(),null
  )
  on conflict(profile_id,device_id) do update
    set device_name=excluded.device_name,
        platform=excluded.platform,
        is_primary=true,
        is_active=true,
        last_seen_at=now(),
        replaced_at=null;

  return jsonb_build_object(
    'device_id',p_device_id,
    'is_new_device',not v_known,
    'replaced_device_id',case when v_previous is distinct from p_device_id then v_previous else null end
  );
end;
$$;

create or replace function public.taskly_primary_device_status_v61(p_device_id text)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1
    from public.taskly_primary_devices_v61 d
    where d.profile_id=public.current_profile_id()
      and d.device_id=p_device_id
      and d.is_primary=true
      and d.is_active=true
  )
$$;

create or replace function public.taskly_touch_primary_device_v61(p_device_id text)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  update public.taskly_primary_devices_v61
  set last_seen_at=now()
  where profile_id=public.current_profile_id()
    and device_id=p_device_id
    and is_primary=true and is_active=true;
end;
$$;

grant execute on function public.taskly_register_primary_device_v61(text,text,text) to authenticated;
grant execute on function public.taskly_primary_device_status_v61(text) to authenticated;
grant execute on function public.taskly_touch_primary_device_v61(text) to authenticated;

-- Realtime lets the old phone immediately notice it is no longer the primary device.
do $$ begin
  begin
    alter publication supabase_realtime add table public.taskly_primary_devices_v61;
  exception when duplicate_object then null;
  end;
end $$;

commit;
