-- Taskly v1.9: cost-guarded multilingual grammar AI
-- Date: 2026-08-05
-- Run after 20260805_taskly_v18_human_ai.sql. Safe to rerun.

begin;

alter table public.task_ai_decisions
  add column if not exists route text,
  add column if not exists model_request_count integer not null default 0,
  add column if not exists input_tokens integer not null default 0,
  add column if not exists cached_input_tokens integer not null default 0,
  add column if not exists output_tokens integer not null default 0,
  add column if not exists reasoning_tokens integer not null default 0,
  add column if not exists estimated_cost_usd numeric(12,8) not null default 0,
  add column if not exists skip_reason text;

create index if not exists task_ai_decisions_profile_route_created_idx
  on public.task_ai_decisions(profile_id, route, created_at desc);

create table if not exists public.task_ai_runs (
  message_id bigint primary key references public.messages(id) on delete cascade,
  profile_id bigint not null references public.profiles(id) on delete cascade,
  status text not null default 'processing'
    check (status in ('processing', 'completed', 'failed')),
  claimed_at timestamptz not null default now(),
  completed_at timestamptz,
  attempt_count integer not null default 1,
  last_error text,
  updated_at timestamptz not null default now()
);

create index if not exists task_ai_runs_profile_updated_idx
  on public.task_ai_runs(profile_id, updated_at desc);

alter table public.task_ai_runs enable row level security;

drop policy if exists task_ai_runs_own_select on public.task_ai_runs;
create policy task_ai_runs_own_select on public.task_ai_runs
for select using (profile_id = public.current_profile_id());

create or replace function public.taskly_ai_claim_context_v19(p_message_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me bigint := public.current_profile_id();
  v_profile public.profiles%rowtype;
  v_message public.messages%rowtype;
  v_workspace public.workspaces%rowtype;
  v_run public.task_ai_runs%rowtype;
  v_claimed boolean := false;
  v_row_count integer := 0;
  v_existing_decision jsonb;
  v_existing_suggestion jsonb;
  v_members jsonb := '[]'::jsonb;
  v_recent jsonb := '[]'::jsonb;
  v_style jsonb := '[]'::jsonb;
  v_tasks jsonb := '[]'::jsonb;
  v_accepted jsonb := '[]'::jsonb;
  v_rejected jsonb := '[]'::jsonb;
  v_preferences jsonb := '{}'::jsonb;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  select * into v_profile
  from public.profiles
  where id = me;

  select * into v_message
  from public.messages
  where id = p_message_id;

  if not found or v_message.sender_profile_id is distinct from me then
    raise exception 'Message not available';
  end if;

  select * into v_workspace
  from public.workspaces
  where id = v_message.workspace_id;

  select decision.decision
  into v_existing_decision
  from public.task_ai_decisions decision
  where decision.message_id = v_message.id;

  select jsonb_build_object(
    'id', suggestion.id,
    'title', suggestion.title,
    'description', suggestion.description,
    'deadline', suggestion.deadline,
    'priority', suggestion.priority,
    'status', suggestion.status,
    'confidence', suggestion.confidence,
    'action_type', suggestion.action_type,
    'target_task_id', suggestion.target_task_id,
    'ai_reason', suggestion.ai_reason,
    'assignee', case when assignee.id is null then null else jsonb_build_object(
      'id', assignee.id,
      'name', assignee.name,
      'email', assignee.email,
      'phone', assignee.phone,
      'avatar_url', assignee.avatar_url,
      'about', assignee.about
    ) end
  )
  into v_existing_suggestion
  from public.task_suggestions suggestion
  left join public.profiles assignee on assignee.id = suggestion.assignee_id
  where suggestion.message_id = v_message.id;

  if v_existing_decision is not null then
    insert into public.task_ai_runs(
      message_id, profile_id, status, claimed_at, completed_at, attempt_count, updated_at
    ) values (
      v_message.id, me, 'completed', now(), now(), 1, now()
    )
    on conflict (message_id) do update
    set status = 'completed', completed_at = coalesce(public.task_ai_runs.completed_at, now()), updated_at = now();

    return jsonb_build_object(
      'claimed', false,
      'analysed', true,
      'skipped', 'already_processed',
      'existing_suggestion', v_existing_suggestion
    );
  end if;

  insert into public.task_ai_runs(
    message_id, profile_id, status, claimed_at, completed_at,
    attempt_count, last_error, updated_at
  ) values (
    v_message.id, me, 'processing', now(), null, 1, null, now()
  )
  on conflict (message_id) do nothing;
  get diagnostics v_row_count = row_count;
  v_claimed := v_row_count = 1;

  if not v_claimed then
    select * into v_run
    from public.task_ai_runs
    where message_id = v_message.id
    for update;

    if v_run.status = 'completed' then
      return jsonb_build_object(
        'claimed', false,
        'analysed', true,
        'skipped', 'already_completed',
        'existing_suggestion', v_existing_suggestion
      );
    end if;

    if v_run.status = 'processing'
       and v_run.claimed_at > now() - interval '2 minutes' then
      return jsonb_build_object(
        'claimed', false,
        'analysed', false,
        'skipped', 'already_processing',
        'existing_suggestion', v_existing_suggestion
      );
    end if;

    if v_run.status = 'failed'
       and v_run.claimed_at > now() - interval '10 minutes' then
      return jsonb_build_object(
        'claimed', false,
        'analysed', false,
        'skipped', 'failure_cooldown',
        'existing_suggestion', v_existing_suggestion
      );
    end if;

    update public.task_ai_runs
    set status = 'processing',
        claimed_at = now(),
        completed_at = null,
        attempt_count = attempt_count + 1,
        last_error = null,
        updated_at = now()
    where message_id = v_message.id
      and (
        (status = 'processing' and claimed_at <= now() - interval '2 minutes')
        or (status = 'failed' and claimed_at <= now() - interval '10 minutes')
      );
    get diagnostics v_row_count = row_count;
    v_claimed := v_row_count = 1;

    if not v_claimed then
      return jsonb_build_object(
        'claimed', false,
        'analysed', false,
        'skipped', 'claim_not_available',
        'existing_suggestion', v_existing_suggestion
      );
    end if;
  end if;

  -- Candidate people only. This avoids sending a large workspace directory.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', chosen.id,
      'name', chosen.name,
      'role', chosen.role
    ) order by chosen.sort_rank, lower(chosen.name), chosen.id
  ), '[]'::jsonb)
  into v_members
  from (
    select profile.id,
           profile.name,
           member.role,
           case
             when profile.id = any(coalesce(v_message.mentioned_profile_ids, array[]::bigint[])) then 0
             when profile.id = me then 1
             when v_workspace.kind = 'direct' then 2
             else 3
           end as sort_rank
    from public.workspace_members member
    join public.profiles profile on profile.id = member.profile_id
    where member.workspace_id = v_message.workspace_id
      and member.is_active = true
    order by sort_rank, lower(profile.name), profile.id
    limit 20
  ) chosen;

  -- Only the two nearest messages, capped to 180 characters each.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'sender_id', recent.sender_id,
      'sender_name', recent.sender_name,
      'text', recent.body
    ) order by recent.created_at, recent.id
  ), '[]'::jsonb)
  into v_recent
  from (
    select message.id,
           message.sender_profile_id as sender_id,
           sender.name as sender_name,
           left(coalesce(message.body, ''), 180) as body,
           message.created_at
    from public.messages message
    join public.profiles sender on sender.id = message.sender_profile_id
    where message.channel_id = v_message.channel_id
      and message.id <> v_message.id
      and message.deleted_at is null
    order by message.created_at desc, message.id desc
    limit 2
  ) recent;

  -- Three short private samples are enough for spelling/code-switching style.
  select coalesce(jsonb_agg(
    jsonb_build_object('text', sample.body)
    order by sample.created_at desc, sample.id desc
  ), '[]'::jsonb)
  into v_style
  from (
    select message.id,
           left(coalesce(message.body, ''), 120) as body,
           message.created_at
    from public.messages message
    where message.sender_profile_id = me
      and message.id <> v_message.id
      and message.deleted_at is null
      and nullif(trim(coalesce(message.body, '')), '') is not null
      and message.created_at >= now() - interval '30 days'
    order by message.created_at desc, message.id desc
    limit 3
  ) sample;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', task.id,
      'title', task.title,
      'status', task.status,
      'deadline', task.deadline,
      'assignee_id', task.assignee_id
    ) order by task.created_at desc, task.id desc
  ), '[]'::jsonb)
  into v_tasks
  from (
    select *
    from public.tasks
    where channel_id = v_message.channel_id
      and deleted_at is null
      and status <> 'done'
    order by created_at desc, id desc
    limit 3
  ) task;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'text', left(feedback.message_text, 160),
      'task', jsonb_build_object(
        'title', feedback.final_task->>'title',
        'assignee_id', feedback.final_task->'assignee_id',
        'deadline', feedback.final_task->>'deadline',
        'action_type', feedback.final_task->>'action_type'
      )
    ) order by feedback.created_at desc
  ), '[]'::jsonb)
  into v_accepted
  from (
    select *
    from public.task_ai_feedback
    where profile_id = me
      and outcome = 'accepted'
    order by created_at desc
    limit 2
  ) feedback;

  select coalesce(jsonb_agg(
    jsonb_build_object('text', left(feedback.message_text, 160))
    order by feedback.created_at desc
  ), '[]'::jsonb)
  into v_rejected
  from (
    select *
    from public.task_ai_feedback
    where profile_id = me
      and outcome = 'rejected'
    order by created_at desc
    limit 2
  ) feedback;

  select coalesce(to_jsonb(preference) - 'profile_id', '{}'::jsonb)
  into v_preferences
  from public.task_ai_preferences preference
  where preference.profile_id = me;
  v_preferences := coalesce(v_preferences, jsonb_build_object(
    'enabled', true,
    'min_confidence', 0.660,
    'rejection_streak', 0,
    'suppress_until', null
  ));

  return jsonb_build_object(
    'claimed', true,
    'context', jsonb_build_object(
      'profile', jsonb_build_object('id', v_profile.id, 'name', v_profile.name),
      'message', jsonb_build_object(
        'id', v_message.id,
        'body', left(coalesce(v_message.body, ''), 2000),
        'workspace_id', v_message.workspace_id,
        'channel_id', v_message.channel_id,
        'mentioned_profile_ids', v_message.mentioned_profile_ids,
        'created_at', v_message.created_at
      ),
      'workspace', jsonb_build_object(
        'id', v_workspace.id,
        'kind', v_workspace.kind,
        'direct_key', v_workspace.direct_key
      ),
      'members', v_members,
      'recent_messages', v_recent,
      'sender_style_samples', v_style,
      'open_tasks', v_tasks,
      'accepted_examples', v_accepted,
      'rejected_examples', v_rejected,
      'preferences', v_preferences
    )
  );
end;
$$;

create or replace function public.taskly_store_ai_decision_v19(
  p_message_id bigint,
  p_decision jsonb,
  p_model_name text,
  p_route text,
  p_latency_ms integer,
  p_usage jsonb default '{}'::jsonb,
  p_skip_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me bigint := public.current_profile_id();
  v_result jsonb;
  v_input integer := greatest(0, coalesce((p_usage->>'input_tokens')::integer, 0));
  v_cached integer := greatest(0, coalesce((p_usage->>'cached_input_tokens')::integer, 0));
  v_output integer := greatest(0, coalesce((p_usage->>'output_tokens')::integer, 0));
  v_reasoning integer := greatest(0, coalesce((p_usage->>'reasoning_tokens')::integer, 0));
  v_cost numeric := greatest(0, coalesce((p_usage->>'estimated_cost_usd')::numeric, 0));
  v_requests integer := case when p_route in ('nano', 'mini') then 1 else 0 end;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  v_result := public.taskly_store_ai_decision(
    p_message_id,
    p_decision,
    p_model_name,
    greatest(0, coalesce(p_latency_ms, 0))
  );

  update public.task_ai_decisions
  set route = left(coalesce(p_route, 'unknown'), 40),
      model_request_count = v_requests,
      input_tokens = v_input,
      cached_input_tokens = least(v_input, v_cached),
      output_tokens = v_output,
      reasoning_tokens = least(v_output, v_reasoning),
      estimated_cost_usd = v_cost,
      skip_reason = nullif(left(coalesce(p_skip_reason, ''), 180), ''),
      updated_at = now()
  where message_id = p_message_id
    and profile_id = me;

  insert into public.task_ai_runs(
    message_id, profile_id, status, claimed_at, completed_at,
    attempt_count, last_error, updated_at
  ) values (
    p_message_id, me, 'completed', now(), now(), 1, null, now()
  )
  on conflict (message_id) do update
  set status = 'completed',
      completed_at = now(),
      last_error = null,
      updated_at = now();

  return v_result || jsonb_build_object(
    'route', p_route,
    'model', p_model_name,
    'usage', jsonb_build_object(
      'input_tokens', v_input,
      'cached_input_tokens', least(v_input, v_cached),
      'output_tokens', v_output,
      'reasoning_tokens', least(v_output, v_reasoning),
      'estimated_cost_usd', v_cost
    )
  );
exception when others then
  update public.task_ai_runs
  set status = 'failed',
      claimed_at = now(),
      completed_at = now(),
      last_error = left(sqlerrm, 500),
      updated_at = now()
  where message_id = p_message_id
    and profile_id = me;
  raise;
end;
$$;

create or replace function public.taskly_ai_fail_v19(
  p_message_id bigint,
  p_error text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me bigint := public.current_profile_id();
  v_message public.messages%rowtype;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  select * into v_message
  from public.messages
  where id = p_message_id;

  if not found or v_message.sender_profile_id is distinct from me then
    raise exception 'Message not available';
  end if;

  insert into public.task_ai_runs(
    message_id, profile_id, status, claimed_at, completed_at,
    attempt_count, last_error, updated_at
  ) values (
    p_message_id, me, 'failed', now(), now(), 1,
    left(coalesce(p_error, 'unknown_error'), 500), now()
  )
  on conflict (message_id) do update
  set status = 'failed',
      claimed_at = now(),
      completed_at = now(),
      last_error = left(coalesce(p_error, 'unknown_error'), 500),
      updated_at = now();
end;
$$;

create or replace function public.taskly_ai_cost_summary_v19(p_days integer default 7)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me bigint := public.current_profile_id();
  v_days integer := greatest(1, least(coalesce(p_days, 7), 90));
  v_summary jsonb;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  select jsonb_build_object(
    'days', v_days,
    'messages_analysed', count(*),
    'model_requests', coalesce(sum(model_request_count), 0),
    'zero_model_messages', count(*) filter (where model_request_count = 0),
    'input_tokens', coalesce(sum(input_tokens), 0),
    'cached_input_tokens', coalesce(sum(cached_input_tokens), 0),
    'output_tokens', coalesce(sum(output_tokens), 0),
    'reasoning_tokens', coalesce(sum(reasoning_tokens), 0),
    'estimated_cost_usd', coalesce(sum(estimated_cost_usd), 0),
    'routes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'route', grouped.route,
        'messages', grouped.messages,
        'model_requests', grouped.model_requests,
        'estimated_cost_usd', grouped.estimated_cost_usd
      ) order by grouped.messages desc, grouped.route)
      from (
        select coalesce(decision.route, 'legacy') as route,
               count(*) as messages,
               coalesce(sum(decision.model_request_count), 0) as model_requests,
               coalesce(sum(decision.estimated_cost_usd), 0) as estimated_cost_usd
        from public.task_ai_decisions decision
        where decision.profile_id = me
          and decision.created_at >= now() - make_interval(days => v_days)
        group by coalesce(decision.route, 'legacy')
      ) grouped
    ), '[]'::jsonb)
  )
  into v_summary
  from public.task_ai_decisions decision
  where decision.profile_id = me
    and decision.created_at >= now() - make_interval(days => v_days);

  return v_summary;
end;
$$;

revoke all on function public.taskly_ai_claim_context_v19(bigint) from public;
grant execute on function public.taskly_ai_claim_context_v19(bigint) to authenticated;

revoke all on function public.taskly_store_ai_decision_v19(bigint, jsonb, text, text, integer, jsonb, text) from public;
grant execute on function public.taskly_store_ai_decision_v19(bigint, jsonb, text, text, integer, jsonb, text) to authenticated;

revoke all on function public.taskly_ai_fail_v19(bigint, text) from public;
grant execute on function public.taskly_ai_fail_v19(bigint, text) to authenticated;

revoke all on function public.taskly_ai_cost_summary_v19(integer) from public;
grant execute on function public.taskly_ai_cost_summary_v19(integer) to authenticated;

notify pgrst, 'reload schema';
commit;
