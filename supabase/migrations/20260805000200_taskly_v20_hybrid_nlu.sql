-- Taskly v2.0: hybrid multilingual NLU + task canonicalizer
-- Date: 2026-08-05
-- Run after the Taskly v1.8/v1.9 migrations. Safe to rerun.

begin;

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;

alter table public.task_ai_decisions
  add column if not exists route text,
  add column if not exists model_request_count integer not null default 0,
  add column if not exists input_tokens integer not null default 0,
  add column if not exists cached_input_tokens integer not null default 0,
  add column if not exists output_tokens integer not null default 0,
  add column if not exists reasoning_tokens integer not null default 0,
  add column if not exists estimated_cost_usd numeric(12,8) not null default 0,
  add column if not exists skip_reason text,
  add column if not exists intent_confidence numeric(5,4),
  add column if not exists canonical_confidence numeric(5,4),
  add column if not exists fallback_reason text,
  add column if not exists detected_language text,
  add column if not exists canonicalizer_version text;

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

create table if not exists public.task_ai_user_aliases (
  profile_id bigint not null references public.profiles(id) on delete cascade,
  source_phrase text not null,
  canonical_action text not null,
  accepted_count integer not null default 0,
  rejected_count integer not null default 0,
  last_used_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (profile_id, source_phrase, canonical_action),
  check (char_length(source_phrase) between 2 and 40),
  check (char_length(canonical_action) between 2 and 40)
);

create index if not exists task_ai_user_aliases_profile_score_idx
  on public.task_ai_user_aliases(profile_id, accepted_count desc, updated_at desc);

alter table public.task_ai_user_aliases enable row level security;
drop policy if exists task_ai_user_aliases_own_select on public.task_ai_user_aliases;
create policy task_ai_user_aliases_own_select on public.task_ai_user_aliases
for select using (profile_id = public.current_profile_id());

create or replace function public.taskly_feedback_source_phrase_v20(p_text text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_text text := lower(coalesce(p_text, ''));
  v_word text;
  v_index integer;
  v_stop text[] := array[
    'hey','hi','hello','dei','bro','brother','sis','machi','machan','anna','akka','arey','oye','da','di','ji','boss',
    'please','pls','plz','kindly','konjam','zara','kripya','can','could','would','will','you','need','to','make','sure',
    'remember','remind','me','i','we','let','naan','na','main','hum'
  ];
begin
  v_text := regexp_replace(v_text, 'https?://\S+', ' ', 'g');
  v_text := regexp_replace(v_text, '@[[:alnum:]_.-]+', ' ', 'g');
  v_text := regexp_replace(v_text, '[^[:alnum:]_''-]+', ' ', 'g');
  v_text := trim(regexp_replace(v_text, '[[:space:]]+', ' ', 'g'));

  for v_index in 1..12 loop
    v_word := split_part(v_text, ' ', 1);
    exit when v_word = '' or not (v_word = any(v_stop));
    v_text := trim(substr(v_text, length(v_word) + 1));
  end loop;

  v_word := split_part(v_text, ' ', 1);
  if length(v_word) between 2 and 40 then
    return v_word;
  end if;
  return null;
end;
$$;

create or replace function public.taskly_canonical_action_v20(p_title text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_first text := lower(split_part(trim(coalesce(p_title, '')), ' ', 1));
begin
  return case v_first
    when 'send' then 'send'
    when 'submit' then 'submit'
    when 'call' then 'call'
    when 'message' then 'message'
    when 'reply' then 'reply'
    when 'follow' then 'follow_up'
    when 'check' then 'check'
    when 'review' then 'check'
    when 'verify' then 'check'
    when 'prepare' then 'prepare'
    when 'create' then 'create'
    when 'design' then 'create'
    when 'write' then 'write'
    when 'update' then 'update'
    when 'edit' then 'update'
    when 'fix' then 'fix'
    when 'complete' then 'complete'
    when 'finish' then 'complete'
    when 'start' then 'start'
    when 'schedule' then 'schedule'
    when 'book' then 'book'
    when 'pay' then 'pay'
    when 'buy' then 'buy'
    when 'collect' then 'collect'
    when 'bring' then 'bring'
    when 'deliver' then 'deliver'
    when 'order' then 'order'
    when 'upload' then 'upload'
    when 'download' then 'download'
    when 'print' then 'print'
    when 'scan' then 'scan'
    when 'sign' then 'sign'
    when 'fill' then 'fill'
    when 'meet' then 'meet'
    when 'visit' then 'visit'
    when 'attend' then 'attend'
    when 'ask' then 'ask'
    when 'tell' then 'tell'
    when 'approve' then 'approve'
    when 'reject' then 'reject'
    when 'reconcile' then 'reconcile'
    when 'analyse' then 'analyse'
    when 'analyze' then 'analyse'
    when 'research' then 'research'
    else case when v_first ~ '^[[:alpha:]_]{2,40}$' then v_first else null end
  end;
end;
$$;

create or replace function public.taskly_learn_alias_from_feedback_v20()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source text;
  v_action text;
begin
  v_source := public.taskly_feedback_source_phrase_v20(new.message_text);
  if v_source is null then return new; end if;
  -- Context-sensitive generic verbs are handled by the canonicalizer itself.
  -- Learning a fixed alias for them (for example get -> buy) would break
  -- messages such as “get milk from Kumar”, which must remain collect.
  if v_source = any(array['get','fetch','take','do','make','le','eduthu']) then return new; end if;

  if new.outcome = 'accepted' then
    v_action := public.taskly_canonical_action_v20(new.final_task->>'title');
    if v_action is null then return new; end if;

    insert into public.task_ai_user_aliases(
      profile_id, source_phrase, canonical_action,
      accepted_count, rejected_count, last_used_at, updated_at
    ) values (
      new.profile_id, v_source, v_action,
      1, 0, now(), now()
    )
    on conflict (profile_id, source_phrase, canonical_action) do update
    set accepted_count = public.task_ai_user_aliases.accepted_count + 1,
        last_used_at = now(),
        updated_at = now();
  elsif new.outcome = 'rejected' then
    update public.task_ai_user_aliases
    set rejected_count = rejected_count + 1,
        last_used_at = now(),
        updated_at = now()
    where profile_id = new.profile_id
      and source_phrase = v_source;
  end if;
  return new;
end;
$$;

drop trigger if exists task_ai_feedback_learn_alias_v20 on public.task_ai_feedback;
create trigger task_ai_feedback_learn_alias_v20
after insert or update on public.task_ai_feedback
for each row execute function public.taskly_learn_alias_from_feedback_v20();

insert into public.task_ai_user_aliases(
  profile_id, source_phrase, canonical_action,
  accepted_count, rejected_count, last_used_at, created_at, updated_at
)
select
  feedback.profile_id,
  public.taskly_feedback_source_phrase_v20(feedback.message_text),
  public.taskly_canonical_action_v20(feedback.final_task->>'title'),
  count(*)::integer,
  0,
  max(feedback.created_at),
  min(feedback.created_at),
  max(feedback.created_at)
from public.task_ai_feedback feedback
where feedback.outcome = 'accepted'
  and public.taskly_feedback_source_phrase_v20(feedback.message_text) is not null
  and public.taskly_feedback_source_phrase_v20(feedback.message_text) <> all(array['get','fetch','take','do','make','le','eduthu'])
  and public.taskly_canonical_action_v20(feedback.final_task->>'title') is not null
group by feedback.profile_id,
         public.taskly_feedback_source_phrase_v20(feedback.message_text),
         public.taskly_canonical_action_v20(feedback.final_task->>'title')
on conflict (profile_id, source_phrase, canonical_action) do update
set accepted_count = greatest(public.task_ai_user_aliases.accepted_count, excluded.accepted_count),
    last_used_at = greatest(public.task_ai_user_aliases.last_used_at, excluded.last_used_at),
    updated_at = now();

create or replace function public.taskly_ai_claim_context_v20(p_message_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
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
  v_tasks jsonb := '[]'::jsonb;
  v_aliases jsonb := '[]'::jsonb;
  v_feedback jsonb := '[]'::jsonb;
begin
  if me is null then raise exception 'Not signed in'; end if;

  select * into v_profile from public.profiles where id = me;
  select * into v_message from public.messages where id = p_message_id;
  if not found or v_message.sender_profile_id is distinct from me then
    raise exception 'Message not available';
  end if;
  select * into v_workspace from public.workspaces where id = v_message.workspace_id;

  select decision.decision into v_existing_decision
  from public.task_ai_decisions decision where decision.message_id = v_message.id;

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
      'id', assignee.id, 'name', assignee.name, 'email', assignee.email,
      'phone', assignee.phone, 'avatar_url', assignee.avatar_url, 'about', assignee.about
    ) end
  ) into v_existing_suggestion
  from public.task_suggestions suggestion
  left join public.profiles assignee on assignee.id = suggestion.assignee_id
  where suggestion.message_id = v_message.id;

  if v_existing_decision is not null then
    insert into public.task_ai_runs(message_id, profile_id, status, claimed_at, completed_at, attempt_count, updated_at)
    values (v_message.id, me, 'completed', now(), now(), 1, now())
    on conflict (message_id) do update
      set status = 'completed', completed_at = coalesce(public.task_ai_runs.completed_at, now()), updated_at = now();
    return jsonb_build_object('claimed', false, 'analysed', true, 'skipped', 'already_processed', 'existing_suggestion', v_existing_suggestion);
  end if;

  insert into public.task_ai_runs(
    message_id, profile_id, status, claimed_at, completed_at,
    attempt_count, last_error, updated_at
  ) values (v_message.id, me, 'processing', now(), null, 1, null, now())
  on conflict (message_id) do nothing;
  get diagnostics v_row_count = row_count;
  v_claimed := v_row_count = 1;

  if not v_claimed then
    select * into v_run from public.task_ai_runs where message_id = v_message.id for update;
    if v_run.status = 'completed' then
      return jsonb_build_object('claimed', false, 'analysed', true, 'skipped', 'already_completed', 'existing_suggestion', v_existing_suggestion);
    end if;
    if v_run.status = 'processing' and v_run.claimed_at > now() - interval '2 minutes' then
      return jsonb_build_object('claimed', false, 'analysed', false, 'skipped', 'already_processing', 'existing_suggestion', v_existing_suggestion);
    end if;
    if v_run.status = 'failed' and v_run.claimed_at > now() - interval '10 minutes' then
      return jsonb_build_object('claimed', false, 'analysed', false, 'skipped', 'failure_cooldown', 'existing_suggestion', v_existing_suggestion);
    end if;

    update public.task_ai_runs
    set status = 'processing', claimed_at = now(), completed_at = null,
        attempt_count = attempt_count + 1, last_error = null, updated_at = now()
    where message_id = v_message.id
      and ((status = 'processing' and claimed_at <= now() - interval '2 minutes')
        or (status = 'failed' and claimed_at <= now() - interval '10 minutes'));
    get diagnostics v_row_count = row_count;
    v_claimed := v_row_count = 1;
    if not v_claimed then
      return jsonb_build_object('claimed', false, 'analysed', false, 'skipped', 'claim_not_available', 'existing_suggestion', v_existing_suggestion);
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', chosen.id, 'name', chosen.name, 'role', chosen.role
  ) order by chosen.sort_rank, lower(chosen.name), chosen.id), '[]'::jsonb)
  into v_members
  from (
    select profile.id, profile.name, member.role,
      case
        when profile.id = any(coalesce(v_message.mentioned_profile_ids, array[]::bigint[])) then 0
        when length(split_part(profile.name, ' ', 1)) >= 3
          and position(lower(split_part(profile.name, ' ', 1)) in lower(coalesce(v_message.body, ''))) > 0 then 1
        when profile.id = me then 2
        when v_workspace.kind = 'direct' then 3
        else 4
      end as sort_rank
    from public.workspace_members member
    join public.profiles profile on profile.id = member.profile_id
    where member.workspace_id = v_message.workspace_id and member.is_active = true
    order by sort_rank, lower(profile.name), profile.id
    limit 12
  ) chosen;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', task.id, 'title', task.title, 'status', task.status,
    'deadline', task.deadline, 'assignee_id', task.assignee_id
  ) order by task.created_at desc, task.id desc), '[]'::jsonb)
  into v_tasks
  from (
    select * from public.tasks
    where channel_id = v_message.channel_id and deleted_at is null and status <> 'done'
    order by created_at desc, id desc limit 5
  ) task;

  select coalesce(jsonb_agg(jsonb_build_object(
    'source_phrase', alias.source_phrase,
    'canonical_action', alias.canonical_action,
    'accepted_count', alias.accepted_count,
    'rejected_count', alias.rejected_count
  ) order by alias.accepted_count desc, alias.updated_at desc), '[]'::jsonb)
  into v_aliases
  from (
    select * from public.task_ai_user_aliases
    where profile_id = me and accepted_count > rejected_count
    order by accepted_count desc, updated_at desc limit 24
  ) alias;

  select coalesce(jsonb_agg(jsonb_build_object(
    'message_text', feedback.message_text,
    'outcome', feedback.outcome,
    'similarity', feedback.similarity,
    'final_task', feedback.final_task
  ) order by feedback.similarity desc, feedback.created_at desc), '[]'::jsonb)
  into v_feedback
  from (
    select recent.message_text, recent.outcome, recent.final_task, recent.created_at,
      similarity(lower(coalesce(recent.message_text, '')), lower(coalesce(v_message.body, '')))::numeric(5,4) as similarity
    from (
      select message_text, outcome, final_task, created_at
      from public.task_ai_feedback
      where profile_id = me
      order by created_at desc
      limit 120
    ) recent
    order by similarity desc, recent.created_at desc
    limit 6
  ) feedback
  where feedback.similarity >= 0.20;

  return jsonb_build_object(
    'claimed', true,
    'context', jsonb_build_object(
      'profile', jsonb_build_object('id', v_profile.id, 'name', v_profile.name),
      'message', jsonb_build_object(
        'id', v_message.id, 'body', left(coalesce(v_message.body, ''), 2000),
        'workspace_id', v_message.workspace_id, 'channel_id', v_message.channel_id,
        'mentioned_profile_ids', v_message.mentioned_profile_ids, 'created_at', v_message.created_at
      ),
      'workspace', jsonb_build_object('id', v_workspace.id, 'kind', v_workspace.kind, 'direct_key', v_workspace.direct_key),
      'members', v_members,
      'open_tasks', v_tasks,
      'learned_aliases', v_aliases,
      'feedback_examples', v_feedback
    )
  );
end;
$$;

create or replace function public.taskly_store_ai_decision_v20(
  p_message_id bigint,
  p_decision jsonb,
  p_model_name text,
  p_route text,
  p_latency_ms integer,
  p_usage jsonb default '{}'::jsonb,
  p_analysis jsonb default '{}'::jsonb,
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
  v_requests integer := case when p_route in ('ai_nano', 'ai_mini') then 1 else 0 end;
begin
  if me is null then raise exception 'Not signed in'; end if;

  v_result := public.taskly_store_ai_decision(
    p_message_id, p_decision, p_model_name, greatest(0, coalesce(p_latency_ms, 0))
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
      intent_confidence = least(1, greatest(0, coalesce((p_analysis->>'intent_confidence')::numeric, 0))),
      canonical_confidence = least(1, greatest(0, coalesce((p_analysis->>'canonical_confidence')::numeric, 0))),
      fallback_reason = nullif(left(coalesce(p_analysis->>'fallback_reason', ''), 240), ''),
      detected_language = nullif(left(coalesce(p_analysis->>'language', ''), 24), ''),
      canonicalizer_version = 'taskly-hybrid-v20',
      updated_at = now()
  where message_id = p_message_id and profile_id = me;

  insert into public.task_ai_runs(
    message_id, profile_id, status, claimed_at, completed_at,
    attempt_count, last_error, updated_at
  ) values (p_message_id, me, 'completed', now(), now(), 1, null, now())
  on conflict (message_id) do update
    set status = 'completed', completed_at = now(), last_error = null, updated_at = now();

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
  set status = 'failed', claimed_at = now(), completed_at = now(),
      last_error = left(sqlerrm, 500), updated_at = now()
  where message_id = p_message_id and profile_id = me;
  raise;
end;
$$;

create or replace function public.taskly_ai_fail_v20(p_message_id bigint, p_error text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me bigint := public.current_profile_id();
  v_message public.messages%rowtype;
begin
  if me is null then raise exception 'Not signed in'; end if;
  select * into v_message from public.messages where id = p_message_id;
  if not found or v_message.sender_profile_id is distinct from me then raise exception 'Message not available'; end if;

  insert into public.task_ai_runs(
    message_id, profile_id, status, claimed_at, completed_at,
    attempt_count, last_error, updated_at
  ) values (
    p_message_id, me, 'failed', now(), now(), 1,
    left(coalesce(p_error, 'unknown_error'), 500), now()
  )
  on conflict (message_id) do update
    set status = 'failed', claimed_at = now(), completed_at = now(),
        last_error = left(coalesce(p_error, 'unknown_error'), 500), updated_at = now();
end;
$$;

create or replace function public.taskly_ai_cost_summary_v20(p_days integer default 7)
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
  if me is null then raise exception 'Not signed in'; end if;

  select jsonb_build_object(
    'days', v_days,
    'messages_analysed', count(*),
    'model_requests', coalesce(sum(model_request_count), 0),
    'local_messages', count(*) filter (where model_request_count = 0),
    'input_tokens', coalesce(sum(input_tokens), 0),
    'cached_input_tokens', coalesce(sum(cached_input_tokens), 0),
    'output_tokens', coalesce(sum(output_tokens), 0),
    'reasoning_tokens', coalesce(sum(reasoning_tokens), 0),
    'estimated_cost_usd', coalesce(sum(estimated_cost_usd), 0),
    'average_intent_confidence', round(avg(intent_confidence), 4),
    'average_canonical_confidence', round(avg(canonical_confidence), 4),
    'routes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'route', grouped.route, 'messages', grouped.messages,
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
  ) into v_summary
  from public.task_ai_decisions decision
  where decision.profile_id = me
    and decision.created_at >= now() - make_interval(days => v_days);
  return v_summary;
end;
$$;

revoke all on function public.taskly_ai_claim_context_v20(bigint) from public;
grant execute on function public.taskly_ai_claim_context_v20(bigint) to authenticated;

revoke all on function public.taskly_store_ai_decision_v20(bigint, jsonb, text, text, integer, jsonb, jsonb, text) from public;
grant execute on function public.taskly_store_ai_decision_v20(bigint, jsonb, text, text, integer, jsonb, jsonb, text) to authenticated;

revoke all on function public.taskly_ai_fail_v20(bigint, text) from public;
grant execute on function public.taskly_ai_fail_v20(bigint, text) to authenticated;

revoke all on function public.taskly_ai_cost_summary_v20(integer) from public;
grant execute on function public.taskly_ai_cost_summary_v20(integer) to authenticated;

notify pgrst, 'reload schema';
commit;
