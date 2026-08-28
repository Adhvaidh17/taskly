-- Taskly v3.1 — race-free high-recall AI verification
-- Run AFTER v3.0. Safe to rerun.
--
-- Fixes:
-- 1. Removes the immediate database webhook that raced the Flutter Edge call.
-- 2. Keeps a delayed database watchdog only when the client call never arrives.
-- 3. Exposes an exact message_id result RPC. Never fetch "latest suggestion".
-- 4. Clears stale processing rows left by old races.

begin;

-- ---------------------------------------------------------------------------
-- Exact correlation lookup for Flutter and duplicate-call recovery
-- ---------------------------------------------------------------------------
create or replace function public.taskly_get_message_ai_result_v31(p_message_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me bigint := public.current_profile_id();
  v_message public.messages%rowtype;
  v_run public.task_ai_runs%rowtype;
  v_decision public.task_ai_decisions%rowtype;
  v_suggestion public.task_suggestions%rowtype;
  v_assignee public.profiles%rowtype;
begin
  if me is null then raise exception 'Not signed in'; end if;

  select * into v_message
  from public.messages
  where id = p_message_id
    and sender_profile_id = me
    and deleted_at is null;
  if not found then raise exception 'Message not available'; end if;

  select * into v_run from public.task_ai_runs where message_id = p_message_id;
  select * into v_decision from public.task_ai_decisions where message_id = p_message_id;
  select * into v_suggestion from public.task_suggestions where message_id = p_message_id;
  if v_suggestion.id is not null then
    select * into v_assignee from public.profiles where id = v_suggestion.assignee_id;
  end if;

  return jsonb_build_object(
    'message_id', p_message_id,
    'analysed', v_decision.message_id is not null or coalesce(v_run.status, '') = 'completed',
    'processing', coalesce(v_run.status, '') = 'processing',
    'failed', coalesce(v_run.status, '') = 'failed',
    'route', v_decision.route,
    'suggestion', case when v_suggestion.id is null then null else jsonb_build_object(
      'message_id', p_message_id,
      'id', v_suggestion.id,
      'title', v_suggestion.title,
      'description', v_suggestion.description,
      'deadline', v_suggestion.deadline,
      'priority', v_suggestion.priority,
      'status', v_suggestion.status,
      'confidence', v_suggestion.confidence,
      'action_type', v_suggestion.action_type,
      'target_task_id', v_suggestion.target_task_id,
      'ai_reason', v_suggestion.ai_reason,
      'assignee', case when v_assignee.id is null then null else jsonb_build_object(
        'id', v_assignee.id,
        'name', v_assignee.name,
        'email', v_assignee.email,
        'phone', v_assignee.phone,
        'avatar_url', v_assignee.avatar_url,
        'about', v_assignee.about
      ) end
    ) end
  );
end;
$$;

revoke all on function public.taskly_get_message_ai_result_v31(bigint) from public;
grant execute on function public.taskly_get_message_ai_result_v31(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Queue only. Flutter performs the immediate, synchronous Edge Function call.
-- The database no longer competes for the same message claim.
-- ---------------------------------------------------------------------------
create or replace function public.taskly_enqueue_message_analysis_v31()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_timezone integer := 330;
begin
  if nullif(trim(coalesce(new.body, '')), '') is null or new.deleted_at is not null then
    return new;
  end if;

  select coalesce(preference.timezone_offset_minutes, 330)
  into v_timezone
  from public.task_ai_preferences preference
  where preference.profile_id = new.sender_profile_id;

  insert into public.task_ai_jobs_v30(
    message_id, profile_id, status, dispatch_attempts,
    timezone_offset_minutes, created_at, updated_at
  ) values (
    new.id, new.sender_profile_id, 'queued', 0,
    coalesce(v_timezone, 330), now(), now()
  )
  on conflict (message_id) do nothing;

  -- Deliberately DO NOT call taskly_dispatch_analysis_v30 here.
  return new;
end;
$$;

drop trigger if exists taskly_message_analysis_v30 on public.messages;
drop trigger if exists taskly_message_analysis_v31 on public.messages;
create trigger taskly_message_analysis_v31
after insert on public.messages
for each row execute function public.taskly_enqueue_message_analysis_v31();

-- ---------------------------------------------------------------------------
-- Legacy UI compatibility: if an older chat screen merges rows by created_at,
-- keep the suggestion directly after its source message instead of after a
-- newer message. New v3.1 Flutter code still uses exact message_id mapping.
-- ---------------------------------------------------------------------------
create or replace function public.taskly_align_suggestion_time_v31()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_time timestamptz;
begin
  select message.created_at into v_message_time
  from public.messages message
  where message.id = new.message_id;
  if v_message_time is not null then
    new.created_at := v_message_time + interval '1 millisecond';
  end if;
  return new;
end;
$$;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'task_suggestions'
      and column_name = 'created_at'
  ) then
    execute 'drop trigger if exists taskly_align_suggestion_time_v31 on public.task_suggestions';
    execute 'create trigger taskly_align_suggestion_time_v31 before insert or update of message_id on public.task_suggestions for each row execute function public.taskly_align_suggestion_time_v31()';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Watchdog: only recover messages whose direct client call did not start.
-- A 12-second grace period prevents the old duplicate-claim race.
-- Paid/processing/completed/dead requests are never automatically repeated.
-- ---------------------------------------------------------------------------
create or replace function public.taskly_dispatch_pending_v30(p_limit integer default 25)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job record;
  v_count integer := 0;
begin
  for v_job in
    select job.message_id
    from public.task_ai_jobs_v30 job
    left join public.task_ai_runs run on run.message_id = job.message_id
    where job.dispatch_attempts < 2
      and job.created_at < now() - interval '12 seconds'
      and job.status in ('queued','failed')
      and (run.message_id is null or run.status = 'failed')
      and not exists (
        select 1 from public.task_ai_decisions decision
        where decision.message_id = job.message_id
      )
    order by job.created_at
    limit greatest(1, least(coalesce(p_limit, 25), 100))
    for update of job skip locked
  loop
    perform public.taskly_dispatch_analysis_v30(v_job.message_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Old races may have left rows marked processing forever. They are reset only
-- when there is no stored decision and they are older than 2 minutes.
update public.task_ai_runs run
set status = 'failed',
    completed_at = now(),
    last_error = 'stale_v30_race_reset',
    updated_at = now()
where run.status = 'processing'
  and run.claimed_at < now() - interval '2 minutes'
  and not exists (
    select 1 from public.task_ai_decisions decision
    where decision.message_id = run.message_id
  );

update public.task_ai_jobs_v30 job
set status = 'queued',
    dispatch_attempts = 0,
    request_id = null,
    last_dispatched_at = null,
    completed_at = null,
    last_error = null,
    updated_at = now()
where job.status in ('processing','dispatched','failed')
  and job.updated_at < now() - interval '2 minutes'
  and not exists (
    select 1 from public.task_ai_decisions decision
    where decision.message_id = job.message_id
  );

-- Replace the old retry schedule with the delayed watchdog.
do $$
declare
  v_job record;
begin
  for v_job in
    select jobid from cron.job
    where jobname in ('taskly-v30-nlu-dispatch-retry', 'taskly-v31-ai-watchdog')
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;

  perform cron.schedule(
    'taskly-v31-ai-watchdog',
    '* * * * *',
    'select public.taskly_dispatch_pending_v30(25);'
  );
end;
$$;

-- Realtime remains a backup delivery channel. Every row already has message_id.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'task_suggestions'
  ) then
    alter publication supabase_realtime add table public.task_suggestions;
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
