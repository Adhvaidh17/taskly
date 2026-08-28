begin;

create extension if not exists pgcrypto with schema extensions;

-- Taskly V51: device-owned media metadata + Cloudflare R2 object pointer.
-- Keep message/tombstone metadata in Postgres. Never store attachment bytes here.

alter table public.messages
  add column if not exists attachment_object_key text,
  add column if not exists attachment_source_device_id text,
  add column if not exists attachment_source_device_proof_hash text,
  add column if not exists attachment_status text,
  add column if not exists attachment_unavailable_at timestamptz,
  add column if not exists attachment_unavailable_reason text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_attachment_status_v51_check'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint messages_attachment_status_v51_check
      check (
        attachment_status is null
        or attachment_status in ('available', 'unavailable')
      );
  end if;
end $$;

-- Existing Supabase-storage attachments stay readable during migration.
update public.messages
set attachment_status = 'available'
where attachment_status is null
  and (
    attachment_name is not null
    or attachment_path is not null
  );

create index if not exists messages_attachment_object_key_v51_idx
  on public.messages(attachment_object_key)
  where attachment_object_key is not null;

create index if not exists messages_attachment_unavailable_v51_idx
  on public.messages(channel_id, created_at desc)
  where attachment_status = 'unavailable';

-- Short-lived server-side upload intent. Clients never receive R2 credentials.
create table if not exists public.message_media_uploads (
  id uuid primary key default gen_random_uuid(),
  profile_id bigint not null references public.profiles(id) on delete cascade,
  workspace_id bigint not null references public.workspaces(id) on delete cascade,
  channel_id bigint not null references public.channels(id) on delete cascade,
  reply_to_message_id bigint references public.messages(id) on delete set null,
  temp_object_key text not null unique,
  final_object_key text not null unique,
  original_name text not null,
  source_device_id text not null,
  source_device_proof_hash text not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  finalized_at timestamptz,
  message_id bigint references public.messages(id) on delete set null
);

alter table public.message_media_uploads
  add column if not exists message_id bigint references public.messages(id) on delete set null,
  add column if not exists source_device_proof_hash text;

create index if not exists message_media_uploads_expiry_v51_idx
  on public.message_media_uploads(expires_at)
  where finalized_at is null;

alter table public.message_media_uploads enable row level security;

-- No client-side table access. The Edge Function uses the service role after
-- validating the caller's JWT and membership.
revoke all on public.message_media_uploads from anon, authenticated;

-- Sender-only RPC used as an additional DB safety rail. The Edge Function
-- deletes R2/Supabase bytes first, then invokes this RPC using the caller JWT.
drop function if exists public.taskly_mark_attachment_unavailable_v51(bigint, text);
drop function if exists public.taskly_mark_attachment_unavailable_v51(bigint, text, text);
drop function if exists public.taskly_mark_attachment_unavailable_v51(bigint, text, text, text);
create or replace function public.taskly_mark_attachment_unavailable_v51(
  p_message_id bigint,
  p_source_device_id text,
  p_source_device_proof text,
  p_reason text default 'source_device_missing'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  me bigint := public.current_profile_id();
  row_message public.messages;
begin
  select * into row_message
  from public.messages
  where id = p_message_id
  for update;

  if not found then
    raise exception 'Message not found';
  end if;

  if row_message.sender_profile_id is distinct from me then
    raise exception 'Only the sender can mark this attachment unavailable';
  end if;

  if row_message.attachment_source_device_id is not null
     and row_message.attachment_source_device_id is distinct from nullif(trim(p_source_device_id), '') then
    raise exception 'Only the originating device can mark this attachment unavailable';
  end if;

  if row_message.attachment_source_device_proof_hash is not null
     and row_message.attachment_source_device_proof_hash is distinct from
       encode(extensions.digest(coalesce(p_source_device_proof, ''), 'sha256'), 'hex') then
    raise exception 'Invalid originating-device proof';
  end if;

  if row_message.attachment_name is null
     and row_message.attachment_path is null
     and row_message.attachment_object_key is null then
    raise exception 'Message has no attachment';
  end if;

  update public.messages
  set attachment_status = 'unavailable',
      attachment_object_key = null,
      attachment_bucket = case
        when row_message.attachment_source_device_id is not null
          then 'unavailable@' || row_message.attachment_source_device_id
        else 'unavailable'
      end,
      attachment_path = null,
      attachment_unavailable_at = coalesce(attachment_unavailable_at, now()),
      attachment_unavailable_reason = left(coalesce(nullif(trim(p_reason), ''), 'source_device_missing'), 80)
  where id = p_message_id;
end;
$$;

revoke all on function public.taskly_mark_attachment_unavailable_v51(bigint, text, text, text) from public, anon;
grant execute on function public.taskly_mark_attachment_unavailable_v51(bigint, text, text, text)
  to authenticated;

-- Messages are already realtime in Taskly installations; this is intentionally
-- defensive and harmless if they were already added to the publication.
do $$
begin
  begin
    alter publication supabase_realtime add table public.messages;
  exception
    when duplicate_object then null;
  end;
end $$;

commit;
