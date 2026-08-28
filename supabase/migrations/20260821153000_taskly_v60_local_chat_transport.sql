-- Taskly v6.0: local chat + temporary encrypted device delivery.
--
-- IMPORTANT:
-- This migration does NOT delete public.messages or legacy chat media.
-- Run the separate purge SQL only after each test account has:
--   1. migrated legacy history locally,
--   2. validated counts, and
--   3. produced a successful encrypted backup.
--
-- Permanent Taskly data remains in Supabase: identities, groups/membership,
-- tasks/task details, task notifications and other task metadata.
-- Raw chat text/media for v6 never enters public.messages.

create extension if not exists pgcrypto;

create or replace function public.current_profile_id()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.profiles p
  where p.auth_user_id = auth.uid()
  limit 1
$$;

create table if not exists public.taskly_device_keys (
  profile_id bigint not null references public.profiles(id) on delete cascade,
  device_id uuid not null,
  public_key text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (profile_id, device_id),
  unique (device_id)
);

create index if not exists taskly_device_keys_active_idx
  on public.taskly_device_keys(profile_id, is_active, last_seen_at desc);

alter table public.taskly_device_keys enable row level security;

drop policy if exists taskly_device_keys_own_select on public.taskly_device_keys;
create policy taskly_device_keys_own_select
on public.taskly_device_keys
for select
to authenticated
using (profile_id = public.current_profile_id());

create table if not exists public.chat_delivery_envelopes (
  id uuid primary key default gen_random_uuid(),
  client_message_id uuid not null,
  channel_id bigint not null references public.channels(id) on delete cascade,
  sender_profile_id bigint not null references public.profiles(id) on delete cascade,
  sender_device_id uuid not null,
  recipient_profile_id bigint not null references public.profiles(id) on delete cascade,
  recipient_device_id uuid not null,
  sender_public_key text not null,
  ciphertext text not null,
  nonce text not null,
  mac text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  unique(client_message_id, recipient_device_id)
);

create index if not exists chat_delivery_recipient_idx
  on public.chat_delivery_envelopes(
    recipient_profile_id,
    recipient_device_id,
    created_at
  );

create index if not exists chat_delivery_expiry_idx
  on public.chat_delivery_envelopes(expires_at);

alter table public.chat_delivery_envelopes enable row level security;

-- Recipient-side SELECT is required for Supabase Realtime visibility.
-- The content is ciphertext only. Creation/ACK are done through SECURITY
-- DEFINER RPCs below.
drop policy if exists chat_delivery_recipient_select
  on public.chat_delivery_envelopes;
create policy chat_delivery_recipient_select
on public.chat_delivery_envelopes
for select
to authenticated
using (recipient_profile_id = public.current_profile_id());

create or replace function public.taskly_register_device_key(
  p_device_id uuid,
  p_public_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id bigint := public.current_profile_id();
begin
  if v_profile_id is null then
    raise exception 'Profile not found';
  end if;

  if coalesce(length(trim(p_public_key)), 0) < 20 then
    raise exception 'Invalid device public key';
  end if;

  insert into public.taskly_device_keys(
    profile_id,
    device_id,
    public_key,
    is_active,
    last_seen_at
  )
  values(
    v_profile_id,
    p_device_id,
    p_public_key,
    true,
    now()
  )
  on conflict(profile_id, device_id) do update
  set public_key = excluded.public_key,
      is_active = true,
      last_seen_at = now();
end
$$;

create or replace function public.taskly_unregister_device(
  p_device_id uuid
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.taskly_device_keys
  set is_active = false,
      last_seen_at = now()
  where profile_id = public.current_profile_id()
    and device_id = p_device_id
$$;

create or replace function public.taskly_recipient_device_keys(
  p_channel_id bigint,
  p_current_device_id uuid
)
returns table(
  profile_id bigint,
  device_id uuid,
  public_key text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile_id bigint := public.current_profile_id();
begin
  if v_profile_id is null then
    raise exception 'Profile not found';
  end if;

  if not exists(
    select 1
    from public.channel_members cm
    where cm.channel_id = p_channel_id
      and cm.profile_id = v_profile_id
  ) then
    raise exception 'Not a channel member';
  end if;

  return query
  select k.profile_id, k.device_id, k.public_key
  from public.taskly_device_keys k
  join public.channel_members cm
    on cm.profile_id = k.profile_id
   and cm.channel_id = p_channel_id
  where k.is_active = true
    and k.device_id <> p_current_device_id
  order by k.profile_id, k.last_seen_at desc;
end
$$;

create or replace function public.taskly_enqueue_chat_envelope(
  p_client_message_id uuid,
  p_channel_id bigint,
  p_recipient_profile_id bigint,
  p_recipient_device_id uuid,
  p_sender_device_id uuid,
  p_sender_public_key text,
  p_ciphertext text,
  p_nonce text,
  p_mac text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_profile_id bigint := public.current_profile_id();
  v_id uuid;
begin
  if v_sender_profile_id is null then
    raise exception 'Profile not found';
  end if;

  if not exists(
    select 1
    from public.channel_members cm
    where cm.channel_id = p_channel_id
      and cm.profile_id = v_sender_profile_id
  ) then
    raise exception 'Sender is not a channel member';
  end if;

  if not exists(
    select 1
    from public.channel_members cm
    where cm.channel_id = p_channel_id
      and cm.profile_id = p_recipient_profile_id
  ) then
    raise exception 'Recipient is not a channel member';
  end if;

  if not exists(
    select 1
    from public.taskly_device_keys k
    where k.profile_id = p_recipient_profile_id
      and k.device_id = p_recipient_device_id
      and k.is_active = true
  ) then
    raise exception 'Recipient device is not active';
  end if;

  -- Opportunistic expiry cleanup. This is safe because expired rows are
  -- undeliverable by definition.
  delete from public.chat_delivery_envelopes
  where expires_at <= now();

  insert into public.chat_delivery_envelopes(
    client_message_id,
    channel_id,
    sender_profile_id,
    sender_device_id,
    recipient_profile_id,
    recipient_device_id,
    sender_public_key,
    ciphertext,
    nonce,
    mac
  )
  values(
    p_client_message_id,
    p_channel_id,
    v_sender_profile_id,
    p_sender_device_id,
    p_recipient_profile_id,
    p_recipient_device_id,
    p_sender_public_key,
    p_ciphertext,
    p_nonce,
    p_mac
  )
  on conflict(client_message_id, recipient_device_id) do update
  set ciphertext = excluded.ciphertext,
      nonce = excluded.nonce,
      mac = excluded.mac,
      sender_public_key = excluded.sender_public_key,
      created_at = now(),
      expires_at = now() + interval '30 days'
  returning id into v_id;

  return v_id;
end
$$;

create or replace function public.taskly_pull_chat_envelopes(
  p_device_id uuid,
  p_limit integer default 100
)
returns table(
  id uuid,
  client_message_id uuid,
  channel_id bigint,
  sender_profile_id bigint,
  sender_device_id uuid,
  sender_public_key text,
  ciphertext text,
  nonce text,
  mac text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id bigint := public.current_profile_id();
  v_limit integer := greatest(1, least(coalesce(p_limit, 100), 500));
begin
  if v_profile_id is null then
    raise exception 'Profile not found';
  end if;

  if not exists(
    select 1
    from public.taskly_device_keys k
    where k.profile_id = v_profile_id
      and k.device_id = p_device_id
      and k.is_active = true
  ) then
    raise exception 'Unknown Taskly device';
  end if;

  update public.taskly_device_keys
  set last_seen_at = now()
  where profile_id = v_profile_id
    and device_id = p_device_id;

  delete from public.chat_delivery_envelopes
  where expires_at <= now();

  return query
  select
    e.id,
    e.client_message_id,
    e.channel_id,
    e.sender_profile_id,
    e.sender_device_id,
    e.sender_public_key,
    e.ciphertext,
    e.nonce,
    e.mac,
    e.created_at
  from public.chat_delivery_envelopes e
  where e.recipient_profile_id = v_profile_id
    and e.recipient_device_id = p_device_id
    and e.expires_at > now()
  order by e.created_at asc
  limit v_limit;
end
$$;

create or replace function public.taskly_ack_chat_envelopes(
  p_device_id uuid,
  p_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id bigint := public.current_profile_id();
  v_count integer;
begin
  if v_profile_id is null then
    raise exception 'Profile not found';
  end if;

  delete from public.chat_delivery_envelopes e
  where e.recipient_profile_id = v_profile_id
    and e.recipient_device_id = p_device_id
    and e.id = any(p_ids);

  get diagnostics v_count = row_count;
  return v_count;
end
$$;

grant execute on function public.taskly_register_device_key(uuid, text)
  to authenticated;
grant execute on function public.taskly_unregister_device(uuid)
  to authenticated;
grant execute on function public.taskly_recipient_device_keys(bigint, uuid)
  to authenticated;
grant execute on function public.taskly_enqueue_chat_envelope(
  uuid, bigint, bigint, uuid, uuid, text, text, text, text
) to authenticated;
grant execute on function public.taskly_pull_chat_envelopes(uuid, integer)
  to authenticated;
grant execute on function public.taskly_ack_chat_envelopes(uuid, uuid[])
  to authenticated;

-- Ensure INSERT events are available to Realtime if the project uses the
-- standard supabase_realtime publication.
do $$
begin
  if exists(
    select 1 from pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists(
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_delivery_envelopes'
  ) then
    alter publication supabase_realtime
      add table public.chat_delivery_envelopes;
  end if;
exception
  when insufficient_privilege then
    null;
end
$$;

notify pgrst, 'reload schema';
