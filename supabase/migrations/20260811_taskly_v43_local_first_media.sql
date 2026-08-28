-- Taskly v4.3: local-first chat hot path, task attachment tombstones,
-- and group media/link/document browsing. Safe after v4.2.
begin;

alter table public.attachments
  add column if not exists removed_at timestamptz,
  add column if not exists removed_by_profile_id bigint references public.profiles(id) on delete set null;

create index if not exists attachments_task_active_v43_idx
  on public.attachments(task_id, created_at desc)
  where task_id is not null and removed_at is null;

create index if not exists messages_channel_attachment_v43_idx
  on public.messages(channel_id, id desc)
  where deleted_at is null and attachment_path is not null;


-- Keep attachment metadata after removal so every device can show a stable
-- "removed" row instead of a broken link. Binary bytes remain in object
-- storage/device storage, never in Postgres.
create or replace function public.taskly_remove_task_attachment_v43(
  p_attachment_id bigint
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_attachment public.attachments%rowtype;
  v_task public.tasks%rowtype;
  v_me bigint := public.current_profile_id();
begin
  if v_me is null then raise exception 'Not authenticated'; end if;

  select * into v_attachment
  from public.attachments
  where id=p_attachment_id and task_id is not null;
  if v_attachment.id is null then raise exception 'Attachment not found'; end if;
  if v_attachment.removed_at is not null then return; end if;

  select * into v_task from public.tasks where id=v_attachment.task_id;
  if v_task.id is null or v_task.deleted_at is not null then
    raise exception 'Task unavailable';
  end if;
  if not public.is_workspace_member(v_task.workspace_id) then
    raise exception 'Not a workspace member';
  end if;

  if v_attachment.uploaded_by_profile_id <> v_me
     and v_task.creator_profile_id <> v_me
     and not public.taskly_is_group_admin_v42(v_task.workspace_id) then
    raise exception 'Only the uploader, task creator, or group admin can remove this attachment';
  end if;

  update public.attachments
  set removed_at=now(), removed_by_profile_id=v_me
  where id=p_attachment_id and removed_at is null;
end
$$;
grant execute on function public.taskly_remove_task_attachment_v43(bigint) to authenticated;

drop function if exists public.taskly_removed_attachment_ids_for_me_v43();

create or replace function public.taskly_removed_attachment_ids_for_me_v43()
returns bigint[]
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(array_agg(x.id order by x.removed_at desc), '{}'::bigint[])
  from (
    select a.id,a.removed_at
    from public.attachments a
    where a.uploaded_by_profile_id=public.current_profile_id()
      and a.removed_at is not null
    order by a.removed_at desc
    limit 500
  ) x
$$;
grant execute on function public.taskly_removed_attachment_ids_for_me_v43() to authenticated;

-- Metadata-only shared-content query used by Group Info. The app downloads a
-- binary only when it needs a local copy. This keeps the group-info page small.
create or replace function public.taskly_group_shared_content_v43(
  p_channel_id bigint,
  p_kind text default 'media',
  p_before_id bigint default null,
  p_limit integer default 60
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_profile bigint := public.current_profile_id();
  v_workspace bigint;
  v_limit integer := greatest(7, least(coalesce(p_limit,60),100));
  v_kind text := lower(coalesce(p_kind,'media'));
  v_result jsonb;
begin
  select c.workspace_id into v_workspace from public.channels c where c.id=p_channel_id;
  if v_workspace is null or not public.is_workspace_member(v_workspace) then
    raise exception 'Conversation unavailable';
  end if;
  if exists(select 1 from public.channel_members where channel_id=p_channel_id)
     and not exists(select 1 from public.channel_members where channel_id=p_channel_id and profile_id=v_profile) then
    raise exception 'Not a conversation member';
  end if;
  if v_kind not in ('media','documents','links') then
    raise exception 'Invalid shared content kind';
  end if;

  select coalesce(jsonb_agg(item order by (item->>'id')::bigint desc),'[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'id',m.id,
      'workspace_id',m.workspace_id,
      'channel_id',m.channel_id,
      'body',m.body,
      'type',m.type,
      'created_at',m.created_at,
      'edited_at',m.edited_at,
      'deleted_at',m.deleted_at,
      'mentioned_profile_ids',coalesce(m.mentioned_profile_ids,'{}'::bigint[]),
      'attachment_bucket',m.attachment_bucket,
      'attachment_path',m.attachment_path,
      'attachment_name',m.attachment_name,
      'attachment_mime_type',m.attachment_mime_type,
      'attachment_size_bytes',m.attachment_size_bytes,
      'forwarded_from_message_id',m.forwarded_from_message_id,
      'is_pinned',m.is_pinned,
      'sender',jsonb_build_object(
        'id',p.id,'name',p.name,'email',p.email,'phone',p.phone,
        'avatar_url',p.avatar_url,'about',p.about
      ),
      'message_reactions','[]'::jsonb,
      'suggestion',null
    ) item
    from public.messages m
    join public.profiles p on p.id=m.sender_profile_id
    where m.channel_id=p_channel_id
      and m.deleted_at is null
      and (p_before_id is null or m.id < p_before_id)
      and (
        (v_kind='media'
          and m.attachment_path is not null
          and (coalesce(m.attachment_mime_type,'') like 'image/%'
               or coalesce(m.attachment_mime_type,'') like 'video/%'))
        or
        (v_kind='documents'
          and m.attachment_path is not null
          and coalesce(m.attachment_mime_type,'') not like 'image/%'
          and coalesce(m.attachment_mime_type,'') not like 'video/%')
        or
        (v_kind='links'
          and coalesce(m.body,'') ~* '(https?://|www\.)')
      )
    order by m.id desc
    limit v_limit
  ) content;
  return v_result;
end
$$;
grant execute on function public.taskly_group_shared_content_v43(bigint,text,bigint,integer) to authenticated;

-- Only metadata changes are broadcast; file bytes never pass through Realtime.
do $$ begin
  begin
    alter publication supabase_realtime add table public.attachments;
  exception when duplicate_object then null;
  end;
end $$;

commit;
