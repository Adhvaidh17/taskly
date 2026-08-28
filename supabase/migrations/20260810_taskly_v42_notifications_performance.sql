-- Taskly v4.2: push dispatch, task notifications, admin task visibility and hot-path indexes.
-- Run once after v4.0. Safe to rerun.
begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net;
create extension if not exists supabase_vault cascade;

alter table public.notifications
  add column if not exists push_dispatched_at timestamptz,
  add column if not exists push_attempts integer not null default 0,
  add column if not exists push_last_error text;

create index if not exists messages_channel_id_created_id_v42_idx
  on public.messages(channel_id, created_at desc, id desc)
  where deleted_at is null;
create index if not exists messages_channel_id_id_v42_idx
  on public.messages(channel_id, id desc);
create index if not exists tasks_workspace_channel_status_v42_idx
  on public.tasks(workspace_id, channel_id, status, deadline)
  where deleted_at is null;
create index if not exists tasks_creator_status_v42_idx
  on public.tasks(creator_profile_id, status, updated_at desc)
  where deleted_at is null;
create index if not exists tasks_assignee_updated_v42_idx
  on public.tasks(assignee_id, updated_at desc)
  where deleted_at is null;
create index if not exists notifications_profile_unread_v42_idx
  on public.notifications(profile_id, is_read, created_at desc);
create index if not exists notifications_push_pending_v42_idx
  on public.notifications(created_at)
  where push_dispatched_at is null;
create index if not exists attachments_task_created_v42_idx
  on public.attachments(task_id, created_at desc)
  where task_id is not null;
create index if not exists device_tokens_enabled_profile_v42_idx
  on public.device_tokens(profile_id, is_enabled)
  where is_enabled = true;
create index if not exists channel_members_profile_channel_v42_idx
  on public.channel_members(profile_id, channel_id);
create index if not exists workspace_members_profile_role_v42_idx
  on public.workspace_members(profile_id, workspace_id, role)
  where is_active = true;

-- Admin/owner must be able to see every task in a group even if a future group
-- contains multiple channels. Normal members retain the v4.0 involved-task rule.
create or replace function public.taskly_is_group_admin_v42(p_workspace_id bigint)
returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.workspace_members wm
    where wm.workspace_id=p_workspace_id
      and wm.profile_id=public.current_profile_id()
      and wm.is_active=true
      and wm.role in ('owner','admin')
  )
$$;
grant execute on function public.taskly_is_group_admin_v42(bigint) to authenticated;

drop policy if exists tasks_select_involved_v40 on public.tasks;
create policy tasks_select_involved_v40 on public.tasks for select
using (
  public.is_workspace_member(workspace_id)
  and (
    assignee_id=public.current_profile_id()
    or creator_profile_id=public.current_profile_id()
    or exists (
      select 1 from public.channel_members cm
      where cm.channel_id=tasks.channel_id
        and cm.profile_id=public.current_profile_id()
    )
    or (
      public.taskly_is_group_admin_v42(workspace_id)
      and coalesce((select c.type from public.channels c where c.id=tasks.channel_id),'team') <> 'direct'
    )
  )
);

create or replace function public.taskly_visible_task_ids_v40()
returns table(task_id bigint)
language sql stable security definer set search_path=public as $$
  with me as (select public.current_profile_id() id)
  select distinct t.id
  from public.tasks t, me
  where t.deleted_at is null
    and public.is_workspace_member(t.workspace_id)
    and (
      t.assignee_id=me.id
      or t.creator_profile_id=me.id
      or exists (
        select 1 from public.channel_members cm
        where cm.channel_id=t.channel_id and cm.profile_id=me.id
      )
      or (
        public.taskly_is_group_admin_v42(t.workspace_id)
        and coalesce((select c.type from public.channels c where c.id=t.channel_id),'team') <> 'direct'
      )
    )
$$;
grant execute on function public.taskly_visible_task_ids_v40() to authenticated;

-- WhatsApp-style notification text is generated in the same transaction as the
-- message so in-app history and push always agree. The async push transport is
-- handled separately below and can fail without failing message delivery.
create or replace function public.taskly_create_message_notifications_v40()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_sender_name text;
  v_channel_name text;
  v_channel_type text;
  v_title text;
  v_preview text;
  v_body text;
begin
  select p.name into v_sender_name from public.profiles p where p.id=new.sender_profile_id;
  select c.name,c.type into v_channel_name,v_channel_type from public.channels c where c.id=new.channel_id;

  v_preview := case
    when new.type='contact' then 'Contact: ' || coalesce(new.shared_contact_name,new.body,'Shared contact')
    when new.type='image' then 'Photo'
    when nullif(new.attachment_name,'') is not null then new.attachment_name
    else left(coalesce(nullif(trim(new.body),''),'New message'),180)
  end;

  if v_channel_type='direct' then
    v_title := coalesce(v_sender_name,'Taskly user');
    v_body := v_preview;
  else
    v_title := coalesce(v_channel_name,'Taskly');
    v_body := coalesce(v_sender_name,'Taskly user') || ': ' || v_preview;
  end if;

  insert into public.notifications(
    profile_id,actor_profile_id,workspace_id,channel_id,message_id,
    type,title,body,is_read
  )
  select cm.profile_id,new.sender_profile_id,new.workspace_id,new.channel_id,new.id,
         'message',v_title,v_body,false
  from public.channel_members cm
  where cm.channel_id=new.channel_id
    and cm.profile_id<>new.sender_profile_id
    and not exists (
      select 1 from public.notifications n
      where n.profile_id=cm.profile_id and n.message_id=new.id
    );
  return new;
end $$;

-- Fetch one expanded chat message after a Realtime event. This avoids
-- re-downloading the most recent 250-message transcript on every single event.
create or replace function public.taskly_message_v42(p_message_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_channel bigint;
  v_workspace bigint;
  v_profile bigint := public.current_profile_id();
  v_result jsonb;
begin
  select m.channel_id,m.workspace_id into v_channel,v_workspace
  from public.messages m where m.id=p_message_id;
  if v_channel is null or not public.is_workspace_member(v_workspace) then return null; end if;
  if exists(select 1 from public.channel_members where channel_id=v_channel)
     and not exists(select 1 from public.channel_members where channel_id=v_channel and profile_id=v_profile) then
    return null;
  end if;

  select jsonb_build_object(
    'id',m.id,'workspace_id',m.workspace_id,'channel_id',m.channel_id,
    'body',m.body,'type',m.type,'created_at',m.created_at,
    'edited_at',m.edited_at,'deleted_at',m.deleted_at,
    'mentioned_profile_ids',coalesce(m.mentioned_profile_ids,'{}'::bigint[]),
    'attachment_bucket',m.attachment_bucket,'attachment_path',m.attachment_path,
    'attachment_name',m.attachment_name,'attachment_mime_type',m.attachment_mime_type,
    'attachment_size_bytes',m.attachment_size_bytes,'is_pinned',m.is_pinned,
    'reply_to_message_id',m.reply_to_message_id,
    'forwarded_from_message_id',m.forwarded_from_message_id,
    'shared_contact_profile_id',m.shared_contact_profile_id,
    'shared_contact_name',m.shared_contact_name,
    'shared_contact_phone',m.shared_contact_phone,
    'shared_contact_email',m.shared_contact_email,
    'sender',jsonb_build_object(
      'id',sender.id,'name',sender.name,'email',sender.email,'phone',sender.phone,
      'phone_country_iso',sender.phone_country_iso,'avatar_url',sender.avatar_url,'about',sender.about
    ),
    'reply_to',case when reply.id is null then null else jsonb_build_object(
      'id',reply.id,'body',reply.body,'type',reply.type,'created_at',reply.created_at,
      'deleted_at',reply.deleted_at,
      'sender',jsonb_build_object('id',reply_sender.id,'name',reply_sender.name,'email',reply_sender.email)
    ) end,
    'message_reactions',coalesce((
      select jsonb_agg(jsonb_build_object('emoji',mr.emoji,'profile_id',mr.profile_id))
      from public.message_reactions mr where mr.message_id=m.id
    ),'[]'::jsonb),
    'suggestion',case when ts.id is null then null else jsonb_build_object(
      'id',ts.id,'title',ts.title,'description',ts.description,'deadline',ts.deadline,
      'priority',ts.priority,'status',ts.status,'confidence',ts.confidence,
      'action_type',ts.action_type,'target_task_id',ts.target_task_id,'ai_reason',ts.ai_reason,
      'assignee',case when assignee.id is null then null else jsonb_build_object(
        'id',assignee.id,'name',assignee.name,'email',assignee.email,'phone',assignee.phone,
        'avatar_url',assignee.avatar_url,'about',assignee.about
      ) end
    ) end
  ) into v_result
  from public.messages m
  join public.profiles sender on sender.id=m.sender_profile_id
  left join public.messages reply on reply.id=m.reply_to_message_id
  left join public.profiles reply_sender on reply_sender.id=reply.sender_profile_id
  left join public.task_suggestions ts on ts.message_id=m.id
  left join public.profiles assignee on assignee.id=ts.assignee_id
  where m.id=p_message_id;
  return v_result;
end $$;
grant execute on function public.taskly_message_v42(bigint) to authenticated;

-- Fast paged transcript. Only the newest page is loaded when a chat opens;
-- older messages are fetched in 80-row pages when the user scrolls upward.
create or replace function public.taskly_channel_messages_v42(
  p_channel_id bigint,
  p_before_id bigint default null,
  p_limit integer default 80
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_profile bigint := public.current_profile_id();
  v_workspace bigint;
  v_limit integer := greatest(20, least(coalesce(p_limit,80),120));
  v_result jsonb;
begin
  select c.workspace_id into v_workspace
  from public.channels c where c.id=p_channel_id;
  if v_workspace is null or not public.is_workspace_member(v_workspace) then
    raise exception 'Conversation unavailable';
  end if;
  if exists(select 1 from public.channel_members where channel_id=p_channel_id)
     and not exists(
       select 1 from public.channel_members
       where channel_id=p_channel_id and profile_id=v_profile
     ) then
    raise exception 'Not a conversation member';
  end if;

  select coalesce(jsonb_agg(item order by (item->>'id')::bigint),'[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'id',m.id,'workspace_id',m.workspace_id,'channel_id',m.channel_id,
      'body',m.body,'type',m.type,'created_at',m.created_at,
      'edited_at',m.edited_at,'deleted_at',m.deleted_at,
      'mentioned_profile_ids',coalesce(m.mentioned_profile_ids,'{}'::bigint[]),
      'attachment_bucket',m.attachment_bucket,'attachment_path',m.attachment_path,
      'attachment_name',m.attachment_name,'attachment_mime_type',m.attachment_mime_type,
      'attachment_size_bytes',m.attachment_size_bytes,'is_pinned',m.is_pinned,
      'reply_to_message_id',m.reply_to_message_id,
      'forwarded_from_message_id',m.forwarded_from_message_id,
      'shared_contact_profile_id',m.shared_contact_profile_id,
      'shared_contact_name',m.shared_contact_name,
      'shared_contact_phone',m.shared_contact_phone,
      'shared_contact_email',m.shared_contact_email,
      'sender',jsonb_build_object(
        'id',sender.id,'name',sender.name,'email',sender.email,'phone',sender.phone,
        'phone_country_iso',sender.phone_country_iso,'avatar_url',sender.avatar_url,'about',sender.about
      ),
      'reply_to',case when reply.id is null then null else jsonb_build_object(
        'id',reply.id,'body',reply.body,'type',reply.type,'created_at',reply.created_at,
        'deleted_at',reply.deleted_at,
        'sender',jsonb_build_object('id',reply_sender.id,'name',reply_sender.name,'email',reply_sender.email)
      ) end,
      'message_reactions',coalesce((
        select jsonb_agg(jsonb_build_object('emoji',mr.emoji,'profile_id',mr.profile_id))
        from public.message_reactions mr where mr.message_id=m.id
      ),'[]'::jsonb),
      'suggestion',case when ts.id is null then null else jsonb_build_object(
        'id',ts.id,'title',ts.title,'description',ts.description,'deadline',ts.deadline,
        'priority',ts.priority,'status',ts.status,'confidence',ts.confidence,
        'action_type',ts.action_type,'target_task_id',ts.target_task_id,'ai_reason',ts.ai_reason,
        'assignee',case when assignee.id is null then null else jsonb_build_object(
          'id',assignee.id,'name',assignee.name,'email',assignee.email,'phone',assignee.phone,
          'avatar_url',assignee.avatar_url,'about',assignee.about
        ) end
      ) end
    ) item
    from (
      select * from public.messages
      where channel_id=p_channel_id
        and (p_before_id is null or id < p_before_id)
      order by id desc
      limit v_limit
    ) m
    join public.profiles sender on sender.id=m.sender_profile_id
    left join public.messages reply on reply.id=m.reply_to_message_id
    left join public.profiles reply_sender on reply_sender.id=reply.sender_profile_id
    left join public.task_suggestions ts on ts.message_id=m.id
    left join public.profiles assignee on assignee.id=ts.assignee_id
  ) q;
  return v_result;
end $$;
grant execute on function public.taskly_channel_messages_v42(bigint,bigint,integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Push webhook secret and async dispatcher
-- ---------------------------------------------------------------------------
do $$
declare
  v_id uuid;
  v_url text := 'https://wqarwlhivahsivzaufnz.supabase.co/functions/v1/dispatch-notification';
begin
  select id into v_id from vault.decrypted_secrets where name='taskly_v42_push_webhook_secret' limit 1;
  if v_id is null then
    perform vault.create_secret(
      replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-',''),
      'taskly_v42_push_webhook_secret',
      'Taskly v4.2 notification dispatcher secret'
    );
  end if;

  select id into v_id from vault.decrypted_secrets where name='taskly_v42_push_function_url' limit 1;
  if v_id is null then
    perform vault.create_secret(v_url, 'taskly_v42_push_function_url', 'Taskly v4.2 push Edge Function URL');
  else
    perform vault.update_secret(v_id, v_url, 'taskly_v42_push_function_url', 'Taskly v4.2 push Edge Function URL');
  end if;
end $$;

create or replace function public.taskly_verify_push_webhook_v42(p_secret text)
returns boolean
language sql
stable
security definer
set search_path=public,vault
as $$
  select exists(
    select 1 from vault.decrypted_secrets s
    where s.name='taskly_v42_push_webhook_secret'
      and s.decrypted_secret=p_secret
  )
$$;
revoke all on function public.taskly_verify_push_webhook_v42(text) from public;
grant execute on function public.taskly_verify_push_webhook_v42(text) to service_role;

create or replace function public.taskly_dispatch_notification_v42()
returns trigger
language plpgsql
security definer
set search_path=public,vault,net
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name='taskly_v42_push_function_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name='taskly_v42_push_webhook_secret' limit 1;
  if coalesce(v_url,'')='' or coalesce(v_secret,'')='' then return new; end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'content-type','application/json',
      'x-taskly-push-secret',v_secret
    ),
    body := jsonb_build_object('notification_id',new.id),
    timeout_milliseconds := 4000
  );
  return new;
exception when others then
  -- Notification history must never fail because push transport is unavailable.
  return new;
end $$;

drop trigger if exists taskly_dispatch_notification_v42 on public.notifications;
create trigger taskly_dispatch_notification_v42
after insert on public.notifications
for each row execute function public.taskly_dispatch_notification_v42();

-- ---------------------------------------------------------------------------
-- Task notification recipients
-- Admin/owner: every task event in non-direct group workspaces.
-- Other users: only tasks they created, are assigned, or were just reassigned from.
-- ---------------------------------------------------------------------------
create or replace function public.taskly_task_notification_recipients_v42(
  p_task public.tasks,
  p_old_assignee bigint default null
) returns table(profile_id bigint)
language sql
stable
security definer
set search_path=public
as $$
  with channel_info as (
    select c.type from public.channels c where c.id=p_task.channel_id
  ), candidates as (
    select p_task.creator_profile_id as profile_id
    union select p_task.assignee_id where p_task.assignee_id is not null
    union select p_old_assignee where p_old_assignee is not null
    -- A member becomes involved after commenting on or attaching a file to the
    -- task, so future activity remains relevant to them too.
    union select tc.profile_id from public.task_comments tc where tc.task_id=p_task.id
    union select a.uploaded_by_profile_id from public.attachments a where a.task_id=p_task.id
    union
    select wm.profile_id
    from public.workspace_members wm
    where wm.workspace_id=p_task.workspace_id
      and wm.is_active=true
      and wm.role in ('owner','admin')
      and coalesce((select type from channel_info limit 1),'team') <> 'direct'
  )
  select distinct c.profile_id from candidates c where c.profile_id is not null
$$;

create or replace function public.taskly_notify_task_insert_v42()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor bigint := public.current_profile_id();
  v_group text;
  v_recipient bigint;
  v_title text;
  v_body text;
  v_assignee text;
begin
  select p.name into v_assignee from public.profiles p where p.id=new.assignee_id;
  select coalesce(c.name,w.name,'Taskly') into v_group
  from public.workspaces w
  left join public.channels c on c.id=new.channel_id
  where w.id=new.workspace_id;

  v_title := 'Task assigned · ' || coalesce(v_group,'Taskly');
  v_body := new.title || case
    when coalesce(v_assignee,'')<>'' then ' · Assigned to ' || v_assignee
    else '' end;

  for v_recipient in select * from public.taskly_task_notification_recipients_v42(new,null)
  loop
    if v_recipient is distinct from v_actor then
      insert into public.notifications(
        profile_id,actor_profile_id,workspace_id,channel_id,task_id,
        type,title,body,is_read
      ) values(
        v_recipient,v_actor,new.workspace_id,new.channel_id,new.id,
        'task_assigned',v_title,v_body,false
      );
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists taskly_notify_task_insert_v42 on public.tasks;
create trigger taskly_notify_task_insert_v42
after insert on public.tasks
for each row execute function public.taskly_notify_task_insert_v42();

create or replace function public.taskly_notify_task_update_v42()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor bigint := public.current_profile_id();
  v_group text;
  v_recipient bigint;
  v_type text;
  v_title text;
  v_body text;
  v_assignee text;
begin
  select p.name into v_assignee from public.profiles p where p.id=new.assignee_id;
  if old.deleted_at is distinct from new.deleted_at then return new; end if;
  if old.status is not distinct from new.status
     and old.assignee_id is not distinct from new.assignee_id
     and old.title is not distinct from new.title
     and old.deadline is not distinct from new.deadline
     and old.priority is not distinct from new.priority
     and old.description is not distinct from new.description then
    return new;
  end if;

  select coalesce(c.name,w.name,'Taskly') into v_group
  from public.workspaces w
  left join public.channels c on c.id=new.channel_id
  where w.id=new.workspace_id;

  if old.status is distinct from new.status then
    v_type := 'task_status';
    v_title := 'Task status · ' || coalesce(v_group,'Taskly');
    v_body := new.title || ' · ' || case new.status
      when 'done' then 'Completed'
      when 'in-progress' then 'In progress'
      else 'To do' end;
  elsif old.assignee_id is distinct from new.assignee_id then
    v_type := 'task_reassigned';
    v_title := 'Task reassigned · ' || coalesce(v_group,'Taskly');
    v_body := new.title || case when coalesce(v_assignee,'')<>'' then ' · Assigned to ' || v_assignee else '' end;
  else
    v_type := 'task_updated';
    v_title := 'Task updated · ' || coalesce(v_group,'Taskly');
    v_body := new.title;
  end if;

  for v_recipient in select * from public.taskly_task_notification_recipients_v42(new,old.assignee_id)
  loop
    if v_recipient is distinct from v_actor then
      insert into public.notifications(
        profile_id,actor_profile_id,workspace_id,channel_id,task_id,
        type,title,body,is_read
      ) values(
        v_recipient,v_actor,new.workspace_id,new.channel_id,new.id,
        v_type,v_title,v_body,false
      );
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists taskly_notify_task_update_v42 on public.tasks;
create trigger taskly_notify_task_update_v42
after update on public.tasks
for each row execute function public.taskly_notify_task_update_v42();

-- Comments, subtask changes and task attachments are task activity too. They
-- use the same recipient rule: admins/owners see group activity, while normal
-- members see only tasks they created/are assigned to.
create or replace function public.taskly_notify_task_comment_v42()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_task public.tasks%rowtype;
  v_actor_name text;
  v_group text;
  v_recipient bigint;
begin
  select * into v_task from public.tasks where id=new.task_id;
  if v_task.id is null or v_task.deleted_at is not null then return new; end if;
  select p.name into v_actor_name from public.profiles p where p.id=new.profile_id;
  select coalesce(c.name,w.name,'Taskly') into v_group
  from public.workspaces w left join public.channels c on c.id=v_task.channel_id
  where w.id=v_task.workspace_id;

  for v_recipient in select * from public.taskly_task_notification_recipients_v42(v_task,null)
  loop
    if v_recipient is distinct from new.profile_id then
      insert into public.notifications(
        profile_id,actor_profile_id,workspace_id,channel_id,task_id,
        type,title,body,is_read
      ) values(
        v_recipient,new.profile_id,v_task.workspace_id,v_task.channel_id,v_task.id,
        'task_comment','Task comment · ' || coalesce(v_group,'Taskly'),
        coalesce(v_actor_name,'Someone') || ': ' || left(new.body,140),false
      );
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists taskly_notify_task_comment_v42 on public.task_comments;
create trigger taskly_notify_task_comment_v42
after insert on public.task_comments
for each row execute function public.taskly_notify_task_comment_v42();

create or replace function public.taskly_notify_subtask_v42()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_task public.tasks%rowtype;
  v_task_id bigint;
  v_actor bigint := public.current_profile_id();
  v_group text;
  v_recipient bigint;
  v_subtask_title text;
  v_body text;
begin
  if tg_op='UPDATE'
     and old.title is not distinct from new.title
     and old.is_done is not distinct from new.is_done then
    return new;
  end if;

  if tg_op='DELETE' then
    v_task_id := old.task_id;
    v_subtask_title := old.title;
  else
    v_task_id := new.task_id;
    v_subtask_title := new.title;
  end if;

  select * into v_task from public.tasks where id=v_task_id;
  if v_task.id is null or v_task.deleted_at is not null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  select coalesce(c.name,w.name,'Taskly') into v_group
  from public.workspaces w left join public.channels c on c.id=v_task.channel_id
  where w.id=v_task.workspace_id;

  v_body := case
    when tg_op='INSERT' then v_task.title || ' · Added subtask: ' || v_subtask_title
    when tg_op='DELETE' then v_task.title || ' · Removed subtask: ' || v_subtask_title
    when new.is_done is distinct from old.is_done and new.is_done then v_task.title || ' · Completed: ' || v_subtask_title
    when new.is_done is distinct from old.is_done then v_task.title || ' · Reopened: ' || v_subtask_title
    else v_task.title || ' · Subtask updated: ' || v_subtask_title
  end;

  for v_recipient in select * from public.taskly_task_notification_recipients_v42(v_task,null)
  loop
    if v_recipient is distinct from v_actor then
      insert into public.notifications(
        profile_id,actor_profile_id,workspace_id,channel_id,task_id,
        type,title,body,is_read
      ) values(
        v_recipient,v_actor,v_task.workspace_id,v_task.channel_id,v_task.id,
        'task_subtask','Task activity · ' || coalesce(v_group,'Taskly'),v_body,false
      );
    end if;
  end loop;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

drop trigger if exists taskly_notify_subtask_v42 on public.subtasks;
create trigger taskly_notify_subtask_v42
after insert or update or delete on public.subtasks
for each row execute function public.taskly_notify_subtask_v42();

create or replace function public.taskly_notify_task_attachment_v42()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_task public.tasks%rowtype;
  v_group text;
  v_recipient bigint;
begin
  if new.task_id is null then return new; end if;
  select * into v_task from public.tasks where id=new.task_id;
  if v_task.id is null or v_task.deleted_at is not null then return new; end if;
  select coalesce(c.name,w.name,'Taskly') into v_group
  from public.workspaces w left join public.channels c on c.id=v_task.channel_id
  where w.id=v_task.workspace_id;
  for v_recipient in select * from public.taskly_task_notification_recipients_v42(v_task,null)
  loop
    if v_recipient is distinct from new.uploaded_by_profile_id then
      insert into public.notifications(
        profile_id,actor_profile_id,workspace_id,channel_id,task_id,
        type,title,body,is_read
      ) values(
        v_recipient,new.uploaded_by_profile_id,v_task.workspace_id,v_task.channel_id,v_task.id,
        'task_attachment','Task attachment · ' || coalesce(v_group,'Taskly'),
        v_task.title || ' · ' || left(new.original_name,120),false
      );
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists taskly_notify_task_attachment_v42 on public.attachments;
create trigger taskly_notify_task_attachment_v42
after insert on public.attachments
for each row when (new.task_id is not null)
execute function public.taskly_notify_task_attachment_v42();

-- Avoid duplicate task notifications when a rapid UI update writes the same row twice.
create index if not exists notifications_task_profile_created_v42_idx
  on public.notifications(task_id,profile_id,created_at desc)
  where task_id is not null;

-- Realtime hot tables. Duplicate publication membership is harmlessly ignored.
do $$ begin
  begin alter publication supabase_realtime add table public.tasks; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
end $$;

commit;
