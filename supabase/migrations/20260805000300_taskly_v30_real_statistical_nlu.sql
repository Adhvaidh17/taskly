-- Taskly v3.0: real statistical multilingual NLU + guaranteed server-side dispatch
-- Date: 2026-08-05
-- Project: wqarwlhivahsivzaufnz
-- Run after the Taskly v1.8/v2.0 migrations. Safe to rerun.
--
-- Main reliability change:
-- Every inserted chat message is queued and dispatched by Postgres itself.
-- Flutter may still invoke the function, but it is no longer responsible for
-- deciding whether analysis happens. Duplicate execution is claim-protected.

begin;

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
create extension if not exists supabase_vault cascade;

-- ---------------------------------------------------------------------------
-- Compatibility / telemetry columns
-- ---------------------------------------------------------------------------
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
  add column if not exists canonicalizer_version text,
  add column if not exists local_model_probability numeric(6,5),
  add column if not exists local_model_version text;

create index if not exists task_ai_decisions_profile_route_created_idx
  on public.task_ai_decisions(profile_id, route, created_at desc);

alter table public.task_ai_preferences
  add column if not exists timezone_offset_minutes integer not null default 330
    check (timezone_offset_minutes between -840 and 840);

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

alter table public.task_ai_runs enable row level security;
alter table public.task_ai_user_aliases enable row level security;

drop policy if exists task_ai_runs_own_select on public.task_ai_runs;
create policy task_ai_runs_own_select on public.task_ai_runs
for select using (profile_id = public.current_profile_id());

drop policy if exists task_ai_user_aliases_own_select on public.task_ai_user_aliases;
create policy task_ai_user_aliases_own_select on public.task_ai_user_aliases
for select using (profile_id = public.current_profile_id());

-- The old v1.8 rejection streak could suppress task detection for hours.
-- Reset it and replace the feedback trigger below with learning-only behaviour.
update public.task_ai_preferences
set rejection_streak = 0,
    suppress_until = null,
    updated_at = now()
where rejection_streak <> 0 or suppress_until is not null;

update public.task_ai_channel_preferences
set rejection_streak = 0,
    suppress_until = null,
    updated_at = now()
where rejection_streak <> 0 or suppress_until is not null;

-- ---------------------------------------------------------------------------
-- Safe parsing helpers
-- ---------------------------------------------------------------------------
create or replace function public.taskly_try_timestamptz(p_value text)
returns timestamptz
language plpgsql
immutable
set search_path = public
as $$
begin
  if nullif(trim(coalesce(p_value, '')), '') is null then
    return null;
  end if;
  return p_value::timestamptz;
exception when others then
  return null;
end;
$$;

create or replace function public.taskly_feedback_source_phrase_v30(p_text text)
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
  if length(v_word) between 2 and 40 then return v_word; end if;
  return null;
end;
$$;

create or replace function public.taskly_canonical_action_v30(p_title text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_first text := lower(split_part(trim(coalesce(p_title, '')), ' ', 1));
begin
  return case v_first
    when 'send' then 'send' when 'submit' then 'submit' when 'call' then 'call'
    when 'message' then 'message' when 'reply' then 'reply' when 'follow' then 'follow_up'
    when 'check' then 'check' when 'review' then 'check' when 'verify' then 'check'
    when 'prepare' then 'prepare' when 'create' then 'create' when 'design' then 'create'
    when 'write' then 'write' when 'update' then 'update' when 'edit' then 'update'
    when 'fix' then 'fix' when 'complete' then 'complete' when 'finish' then 'complete'
    when 'start' then 'start' when 'schedule' then 'schedule' when 'book' then 'book'
    when 'pay' then 'pay' when 'buy' then 'buy' when 'collect' then 'collect'
    when 'bring' then 'bring' when 'deliver' then 'deliver' when 'order' then 'order'
    when 'upload' then 'upload' when 'download' then 'download' when 'print' then 'print'
    when 'scan' then 'scan' when 'sign' then 'sign' when 'fill' then 'fill'
    when 'meet' then 'meet' when 'visit' then 'visit' when 'attend' then 'attend'
    when 'ask' then 'ask' when 'tell' then 'tell' when 'approve' then 'approve'
    when 'reject' then 'reject' when 'reconcile' then 'reconcile'
    when 'analyse' then 'analyse' when 'analyze' then 'analyse' when 'research' then 'research'
    else case when v_first ~ '^[[:alpha:]_]{2,40}$' then v_first else null end
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Feedback learning without global/channel shutoff
-- ---------------------------------------------------------------------------
create or replace function public.taskly_capture_ai_feedback()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message public.messages%rowtype;
  v_outcome text;
  v_source text;
  v_action text;
begin
  if old.status is not distinct from new.status
     or new.status not in ('confirmed', 'dismissed') then
    return new;
  end if;

  select * into v_message from public.messages where id = new.message_id;
  if not found or new.sender_profile_id is null then return new; end if;

  v_outcome := case when new.status = 'confirmed' then 'accepted' else 'rejected' end;

  insert into public.task_ai_feedback(
    profile_id, workspace_id, channel_id, message_id, suggestion_id,
    outcome, message_text, final_task
  ) values (
    new.sender_profile_id, new.workspace_id, v_message.channel_id,
    new.message_id, new.id, v_outcome, coalesce(v_message.body, ''),
    jsonb_build_object(
      'title', new.title, 'description', new.description,
      'assignee_id', new.assignee_id, 'deadline', new.deadline,
      'priority', new.priority, 'action_type', new.action_type,
      'target_task_id', new.target_task_id
    )
  )
  on conflict (suggestion_id) do update
  set outcome = excluded.outcome,
      final_task = excluded.final_task,
      created_at = now();

  -- Keep detection enabled. Rejections teach precision but never disable NLU.
  insert into public.task_ai_preferences(profile_id, rejection_streak, suppress_until, updated_at)
  values(new.sender_profile_id, 0, null, now())
  on conflict (profile_id) do update
  set rejection_streak = 0, suppress_until = null, updated_at = now();

  insert into public.task_ai_channel_preferences(
    profile_id, channel_id, rejection_streak, suppress_until, updated_at
  ) values(new.sender_profile_id, v_message.channel_id, 0, null, now())
  on conflict (profile_id, channel_id) do update
  set rejection_streak = 0, suppress_until = null, updated_at = now();

  v_source := public.taskly_feedback_source_phrase_v30(v_message.body);
  if v_source is not null and v_source <> all(array['get','fetch','take','do','make','le','eduthu']) then
    if v_outcome = 'accepted' then
      v_action := public.taskly_canonical_action_v30(new.title);
      if v_action is not null then
        insert into public.task_ai_user_aliases(
          profile_id, source_phrase, canonical_action,
          accepted_count, rejected_count, last_used_at, updated_at
        ) values(new.sender_profile_id, v_source, v_action, 1, 0, now(), now())
        on conflict (profile_id, source_phrase, canonical_action) do update
        set accepted_count = public.task_ai_user_aliases.accepted_count + 1,
            last_used_at = now(), updated_at = now();
      end if;
    else
      update public.task_ai_user_aliases
      set rejected_count = rejected_count + 1,
          last_used_at = now(), updated_at = now()
      where profile_id = new.sender_profile_id
        and source_phrase = v_source;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists taskly_task_suggestion_feedback on public.task_suggestions;
create trigger taskly_task_suggestion_feedback
after update of status on public.task_suggestions
for each row execute function public.taskly_capture_ai_feedback();

-- Remove the v2 alias trigger to avoid counting the same correction twice.
drop trigger if exists task_ai_feedback_learn_alias_v20 on public.task_ai_feedback;

-- ---------------------------------------------------------------------------
-- Reliable message analysis queue
-- ---------------------------------------------------------------------------
create table if not exists public.task_ai_jobs_v30 (
  message_id bigint primary key references public.messages(id) on delete cascade,
  profile_id bigint not null references public.profiles(id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued','dispatched','processing','completed','failed','dead')),
  dispatch_attempts integer not null default 0,
  request_id bigint,
  timezone_offset_minutes integer not null default 330,
  last_dispatched_at timestamptz,
  completed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists task_ai_jobs_v30_status_updated_idx
  on public.task_ai_jobs_v30(status, updated_at);

alter table public.task_ai_jobs_v30 enable row level security;
drop policy if exists task_ai_jobs_v30_own_select on public.task_ai_jobs_v30;
create policy task_ai_jobs_v30_own_select on public.task_ai_jobs_v30
for select using (profile_id = public.current_profile_id());

-- Create a deployment-specific 256-bit webhook secret inside Vault. The
-- plaintext is never hardcoded in this package or copied into Flutter.
do $$
declare
  v_id uuid;
  v_url constant text := 'https://wqarwlhivahsivzaufnz.supabase.co/functions/v1/analyse-task-message';
begin
  select id into v_id from vault.decrypted_secrets where name = 'taskly_v30_webhook_secret' limit 1;
  if v_id is null then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'taskly_v30_webhook_secret',
      'Taskly v3 database-to-edge webhook secret'
    );
  end if;

  select id into v_id from vault.decrypted_secrets where name = 'taskly_v30_function_url' limit 1;
  if v_id is null then
    perform vault.create_secret(v_url, 'taskly_v30_function_url', 'Taskly v3 analysis Edge Function URL');
  else
    perform vault.update_secret(v_id, v_url, 'taskly_v30_function_url', 'Taskly v3 analysis Edge Function URL');
  end if;
end;
$$;

-- The Edge Function uses its built-in service-role environment to verify the
-- database webhook secret without storing that secret in function settings.
create or replace function public.taskly_verify_webhook_v30(p_secret text)
returns boolean
language sql
stable
security definer
set search_path = public, vault, extensions
as $$
  select length(coalesce(p_secret, '')) >= 64
    and exists (
      select 1
      from vault.decrypted_secrets secret
      where secret.name = 'taskly_v30_webhook_secret'
        and extensions.digest(convert_to(p_secret, 'UTF8'), 'sha256')
          = extensions.digest(convert_to(secret.decrypted_secret, 'UTF8'), 'sha256')
    )
$$;

-- ---------------------------------------------------------------------------
-- Claim compact context. Works for service_role webhooks and legacy user calls.
-- ---------------------------------------------------------------------------
create or replace function public.taskly_ai_claim_context_v30(p_message_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role';
  me bigint;
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
  select * into v_message from public.messages where id = p_message_id;
  if not found or nullif(trim(coalesce(v_message.body, '')), '') is null then
    raise exception 'Message not available';
  end if;

  me := case when v_is_service then v_message.sender_profile_id else public.current_profile_id() end;
  if me is null then raise exception 'Not signed in'; end if;
  if not v_is_service and v_message.sender_profile_id is distinct from me then
    raise exception 'Message not available';
  end if;

  select * into v_profile from public.profiles where id = me;
  select * into v_workspace from public.workspaces where id = v_message.workspace_id;

  select decision.decision into v_existing_decision
  from public.task_ai_decisions decision where decision.message_id = v_message.id;

  select jsonb_build_object(
    'id', suggestion.id, 'title', suggestion.title,
    'description', suggestion.description, 'deadline', suggestion.deadline,
    'priority', suggestion.priority, 'status', suggestion.status,
    'confidence', suggestion.confidence, 'action_type', suggestion.action_type,
    'target_task_id', suggestion.target_task_id, 'ai_reason', suggestion.ai_reason,
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
    update public.task_ai_jobs_v30
    set status = 'completed', completed_at = coalesce(completed_at, now()), last_error = null, updated_at = now()
    where message_id = v_message.id;
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
    if v_run.status = 'processing' and v_run.claimed_at > now() - interval '90 seconds' then
      return jsonb_build_object('claimed', false, 'analysed', false, 'skipped', 'already_processing', 'existing_suggestion', v_existing_suggestion);
    end if;

    update public.task_ai_runs
    set status = 'processing', claimed_at = now(), completed_at = null,
        attempt_count = attempt_count + 1, last_error = null, updated_at = now()
    where message_id = v_message.id
      and (status = 'failed' or claimed_at <= now() - interval '90 seconds');
    get diagnostics v_row_count = row_count;
    v_claimed := v_row_count = 1;
    if not v_claimed then
      return jsonb_build_object('claimed', false, 'analysed', false, 'skipped', 'claim_not_available', 'existing_suggestion', v_existing_suggestion);
    end if;
  end if;

  update public.task_ai_jobs_v30
  set status = 'processing', updated_at = now(), last_error = null
  where message_id = v_message.id;

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
    limit 16
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
      'members', v_members, 'open_tasks', v_tasks,
      'learned_aliases', v_aliases, 'feedback_examples', v_feedback
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Store decisions without the old rejection-suppression gate
-- ---------------------------------------------------------------------------
create or replace function public.taskly_store_ai_decision_v30(
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
set search_path = public, extensions
as $$
declare
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role';
  me bigint;
  v_message public.messages%rowtype;
  v_workspace public.workspaces%rowtype;
  v_suggestion public.task_suggestions%rowtype;
  v_assignee public.profiles%rowtype;
  v_is_task boolean := false;
  v_confidence numeric := 0;
  v_action text := 'none';
  v_title text := '';
  v_description text;
  v_assignee_id bigint;
  v_deadline timestamptz;
  v_priority text := 'medium';
  v_target_task_id bigint;
  v_requested_status text;
  v_threshold numeric := case when p_route in ('ai_nano','ai_mini') then 0.55 else 0.68 end;
  v_is_self_chat boolean := false;
  v_other_profile_id bigint;
  v_input integer := 0;
  v_cached integer := 0;
  v_output integer := 0;
  v_reasoning integer := 0;
  v_cost numeric := 0;
  v_requests integer := case when p_route in ('ai_nano','ai_mini') then 1 else 0 end;
  v_skip text := nullif(left(coalesce(p_skip_reason, ''), 180), '');
begin
  select * into v_message from public.messages where id = p_message_id;
  if not found then raise exception 'Message not available'; end if;

  me := case when v_is_service then v_message.sender_profile_id else public.current_profile_id() end;
  if me is null then raise exception 'Not signed in'; end if;
  if not v_is_service and v_message.sender_profile_id is distinct from me then
    raise exception 'Message not available';
  end if;
  select * into v_workspace from public.workspaces where id = v_message.workspace_id;

  begin v_is_task := coalesce((p_decision->>'t')::boolean, false); exception when others then v_is_task := false; end;
  begin v_confidence := greatest(0, least(1, coalesce((p_decision->>'c')::numeric, 0))); exception when others then v_confidence := 0; end;
  v_action := coalesce(nullif(p_decision->>'a', ''), 'none');
  v_title := left(trim(coalesce(p_decision->>'ttl', '')), 180);
  v_description := nullif(left(trim(coalesce(p_decision->>'d', '')), 500), '');
  v_priority := coalesce(nullif(p_decision->>'p', ''), 'medium');
  v_requested_status := nullif(p_decision->>'st', '');
  begin v_assignee_id := nullif(p_decision->>'as', '')::bigint; exception when others then v_assignee_id := null; end;
  begin v_target_task_id := nullif(p_decision->>'tid', '')::bigint; exception when others then v_target_task_id := null; end;
  v_deadline := public.taskly_try_timestamptz(p_decision->>'due');

  begin v_input := greatest(0, coalesce((p_usage->>'input_tokens')::integer, 0)); exception when others then v_input := 0; end;
  begin v_cached := greatest(0, coalesce((p_usage->>'cached_input_tokens')::integer, 0)); exception when others then v_cached := 0; end;
  begin v_output := greatest(0, coalesce((p_usage->>'output_tokens')::integer, 0)); exception when others then v_output := 0; end;
  begin v_reasoning := greatest(0, coalesce((p_usage->>'reasoning_tokens')::integer, 0)); exception when others then v_reasoning := 0; end;
  begin v_cost := greatest(0, coalesce((p_usage->>'estimated_cost_usd')::numeric, 0)); exception when others then v_cost := 0; end;

  insert into public.task_ai_decisions(
    profile_id, workspace_id, channel_id, message_id,
    model_name, latency_ms, is_task, confidence, decision,
    route, model_request_count, input_tokens, cached_input_tokens,
    output_tokens, reasoning_tokens, estimated_cost_usd, skip_reason,
    intent_confidence, canonical_confidence, fallback_reason,
    detected_language, canonicalizer_version,
    local_model_probability, local_model_version,
    created_at, updated_at
  ) values (
    me, v_message.workspace_id, v_message.channel_id, v_message.id,
    left(coalesce(p_model_name, 'unknown'), 120), greatest(0, coalesce(p_latency_ms, 0)),
    v_is_task, v_confidence, p_decision,
    left(coalesce(p_route, 'unknown'), 40), v_requests, v_input, least(v_input, v_cached),
    v_output, least(v_output, v_reasoning), v_cost, v_skip,
    least(1, greatest(0, coalesce((p_analysis->>'intent_confidence')::numeric, 0))),
    least(1, greatest(0, coalesce((p_analysis->>'canonical_confidence')::numeric, 0))),
    nullif(left(coalesce(p_analysis->>'fallback_reason', ''), 240), ''),
    nullif(left(coalesce(p_analysis->>'language', ''), 24), ''),
    'taskly-statistical-nlu-v30',
    case when nullif(p_analysis->>'model_task_probability', '') is null then null
      else least(1, greatest(0, (p_analysis->>'model_task_probability')::numeric)) end,
    nullif(left(coalesce(p_analysis->>'local_model_version', ''), 80), ''),
    now(), now()
  )
  on conflict (message_id) do update
  set model_name = excluded.model_name, latency_ms = excluded.latency_ms,
      is_task = excluded.is_task, confidence = excluded.confidence,
      decision = excluded.decision, route = excluded.route,
      model_request_count = excluded.model_request_count,
      input_tokens = excluded.input_tokens,
      cached_input_tokens = excluded.cached_input_tokens,
      output_tokens = excluded.output_tokens,
      reasoning_tokens = excluded.reasoning_tokens,
      estimated_cost_usd = excluded.estimated_cost_usd,
      skip_reason = excluded.skip_reason,
      intent_confidence = excluded.intent_confidence,
      canonical_confidence = excluded.canonical_confidence,
      fallback_reason = excluded.fallback_reason,
      detected_language = excluded.detected_language,
      canonicalizer_version = excluded.canonicalizer_version,
      local_model_probability = excluded.local_model_probability,
      local_model_version = excluded.local_model_version,
      updated_at = now();

  if not v_is_task or v_confidence < v_threshold or v_title = '' or v_action = 'none' then
    update public.task_ai_runs
    set status = 'completed', completed_at = now(), last_error = null, updated_at = now()
    where message_id = p_message_id;
    update public.task_ai_jobs_v30
    set status = 'completed', completed_at = now(), last_error = null, updated_at = now()
    where message_id = p_message_id;
    return jsonb_build_object(
      'analysed', true, 'suggestion', null, 'route', p_route,
      'confidence', v_confidence, 'threshold', v_threshold,
      'usage', jsonb_build_object(
        'input_tokens', v_input, 'cached_input_tokens', least(v_input, v_cached),
        'output_tokens', v_output, 'reasoning_tokens', least(v_output, v_reasoning),
        'estimated_cost_usd', v_cost
      )
    );
  end if;

  if v_action not in ('create','update','status_change') then v_action := 'create'; end if;
  if v_priority not in ('low','medium','high') then v_priority := 'medium'; end if;

  v_is_self_chat := v_workspace.kind = 'direct' and v_workspace.direct_key = 'self:' || me::text;

  if v_action = 'create' then
    if v_is_self_chat then
      v_assignee_id := me;
    elsif v_assignee_id is null and cardinality(coalesce(v_message.mentioned_profile_ids, array[]::bigint[])) > 0 then
      select member.profile_id into v_assignee_id
      from public.workspace_members member
      where member.workspace_id = v_workspace.id
        and member.is_active = true
        and member.profile_id = any(v_message.mentioned_profile_ids)
      order by array_position(v_message.mentioned_profile_ids, member.profile_id)
      limit 1;
    elsif v_workspace.kind = 'direct' and v_assignee_id is null then
      select member.profile_id into v_other_profile_id
      from public.workspace_members member
      where member.workspace_id = v_workspace.id
        and member.profile_id <> me and member.is_active = true
      order by member.profile_id limit 1;
      v_assignee_id := v_other_profile_id;
    end if;

    if v_assignee_id is null or not exists(
      select 1 from public.workspace_members member
      where member.workspace_id = v_workspace.id
        and member.profile_id = v_assignee_id and member.is_active = true
    ) then
      update public.task_ai_decisions
      set skip_reason = 'invalid_assignee', updated_at = now()
      where message_id = p_message_id;
      update public.task_ai_runs set status = 'completed', completed_at = now(), last_error = null, updated_at = now() where message_id = p_message_id;
      update public.task_ai_jobs_v30 set status = 'completed', completed_at = now(), last_error = null, updated_at = now() where message_id = p_message_id;
      return jsonb_build_object('analysed', true, 'suggestion', null, 'skipped', 'invalid_assignee', 'route', p_route);
    end if;
  else
    if v_target_task_id is null or not exists(
      select 1 from public.tasks task
      where task.id = v_target_task_id and task.channel_id = v_message.channel_id and task.deleted_at is null
    ) then
      update public.task_ai_decisions set skip_reason = 'invalid_target_task', updated_at = now() where message_id = p_message_id;
      update public.task_ai_runs set status = 'completed', completed_at = now(), last_error = null, updated_at = now() where message_id = p_message_id;
      update public.task_ai_jobs_v30 set status = 'completed', completed_at = now(), last_error = null, updated_at = now() where message_id = p_message_id;
      return jsonb_build_object('analysed', true, 'suggestion', null, 'skipped', 'invalid_target_task', 'route', p_route);
    end if;
    if v_assignee_id is null then
      select task.assignee_id into v_assignee_id from public.tasks task where task.id = v_target_task_id;
    end if;
  end if;

  if v_action = 'status_change' and v_requested_status not in ('todo','in-progress','done') then
    update public.task_ai_decisions set skip_reason = 'invalid_requested_status', updated_at = now() where message_id = p_message_id;
    update public.task_ai_runs set status = 'completed', completed_at = now(), last_error = null, updated_at = now() where message_id = p_message_id;
    update public.task_ai_jobs_v30 set status = 'completed', completed_at = now(), last_error = null, updated_at = now() where message_id = p_message_id;
    return jsonb_build_object('analysed', true, 'suggestion', null, 'skipped', 'invalid_requested_status', 'route', p_route);
  end if;

  insert into public.task_suggestions(
    workspace_id, message_id, sender_profile_id, assignee_id,
    title, description, deadline, priority, confidence,
    action_type, target_task_id, ai_reason, ai_payload, status, updated_at
  ) values (
    v_message.workspace_id, v_message.id, me, v_assignee_id,
    v_title, nullif(trim(coalesce(v_description, '')), ''), v_deadline,
    v_priority, v_confidence, v_action, v_target_task_id,
    left(coalesce(p_decision->>'r', ''), 500),
    jsonb_build_object(
      'requested_status', v_requested_status,
      'language', nullif(p_decision->>'l', ''),
      'model', p_model_name, 'route', p_route,
      'local_model', nullif(p_analysis->>'local_model_version', ''),
      'decision_version', 30
    ),
    'pending', now()
  )
  on conflict (message_id) do update
  set sender_profile_id = excluded.sender_profile_id,
      assignee_id = excluded.assignee_id,
      title = excluded.title, description = excluded.description,
      deadline = excluded.deadline, priority = excluded.priority,
      confidence = excluded.confidence, action_type = excluded.action_type,
      target_task_id = excluded.target_task_id, ai_reason = excluded.ai_reason,
      ai_payload = excluded.ai_payload,
      status = case when public.task_suggestions.status in ('confirmed','dismissed')
        then public.task_suggestions.status else 'pending' end,
      updated_at = now()
  returning * into v_suggestion;

  select * into v_assignee from public.profiles where id = v_suggestion.assignee_id;

  update public.task_ai_runs
  set status = 'completed', completed_at = now(), last_error = null, updated_at = now()
  where message_id = p_message_id;
  update public.task_ai_jobs_v30
  set status = 'completed', completed_at = now(), last_error = null, updated_at = now()
  where message_id = p_message_id;

  return jsonb_build_object(
    'analysed', true, 'route', p_route, 'model', p_model_name,
    'usage', jsonb_build_object(
      'input_tokens', v_input, 'cached_input_tokens', least(v_input, v_cached),
      'output_tokens', v_output, 'reasoning_tokens', least(v_output, v_reasoning),
      'estimated_cost_usd', v_cost
    ),
    'suggestion', jsonb_build_object(
      'id', v_suggestion.id, 'title', v_suggestion.title,
      'description', v_suggestion.description, 'deadline', v_suggestion.deadline,
      'priority', v_suggestion.priority, 'status', v_suggestion.status,
      'confidence', v_suggestion.confidence, 'action_type', v_suggestion.action_type,
      'target_task_id', v_suggestion.target_task_id, 'ai_reason', v_suggestion.ai_reason,
      'assignee', case when v_assignee.id is null then null else jsonb_build_object(
        'id', v_assignee.id, 'name', v_assignee.name, 'email', v_assignee.email,
        'phone', v_assignee.phone, 'avatar_url', v_assignee.avatar_url, 'about', v_assignee.about
      ) end
    )
  );
exception when others then
  update public.task_ai_runs
  set status = 'failed', completed_at = now(), last_error = left(sqlerrm, 500), updated_at = now()
  where message_id = p_message_id;
  update public.task_ai_jobs_v30
  set status = 'dead', completed_at = now(), last_error = left(sqlerrm, 500), updated_at = now()
  where message_id = p_message_id;
  raise;
end;
$$;

create or replace function public.taskly_ai_fail_v30(p_message_id bigint, p_error text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role';
  me bigint;
  v_message public.messages%rowtype;
begin
  select * into v_message from public.messages where id = p_message_id;
  if not found then return; end if;
  me := case when v_is_service then v_message.sender_profile_id else public.current_profile_id() end;
  if me is null or (not v_is_service and v_message.sender_profile_id is distinct from me) then
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
  set status = 'failed', completed_at = now(),
      last_error = left(coalesce(p_error, 'unknown_error'), 500), updated_at = now();

  -- Do not automatically repeat a possibly billed model request.
  update public.task_ai_jobs_v30
  set status = 'dead', completed_at = now(),
      last_error = left(coalesce(p_error, 'unknown_error'), 500), updated_at = now()
  where message_id = p_message_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Database -> Edge dispatch
-- ---------------------------------------------------------------------------
create or replace function public.taskly_dispatch_analysis_v30(p_message_id bigint)
returns bigint
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  v_url text;
  v_secret text;
  v_timezone integer := 330;
  v_request_id bigint;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'taskly_v30_function_url' limit 1;
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'taskly_v30_webhook_secret' limit 1;
  select timezone_offset_minutes into v_timezone
  from public.task_ai_jobs_v30 where message_id = p_message_id;

  if nullif(v_url, '') is null or nullif(v_secret, '') is null then
    update public.task_ai_jobs_v30
    set status = 'failed', last_error = 'webhook_configuration_missing', updated_at = now()
    where message_id = p_message_id;
    return null;
  end if;

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-taskly-webhook-secret', v_secret
    ),
    body := jsonb_build_object(
      'message_id', p_message_id,
      'timezone_offset_minutes', coalesce(v_timezone, 330),
      'source', 'database_trigger_v30'
    )
  ) into v_request_id;

  update public.task_ai_jobs_v30
  set status = 'dispatched', dispatch_attempts = dispatch_attempts + 1,
      request_id = v_request_id, last_dispatched_at = now(),
      last_error = null, updated_at = now()
  where message_id = p_message_id;
  return v_request_id;
exception when others then
  update public.task_ai_jobs_v30
  set status = 'failed', last_error = left(sqlerrm, 500), updated_at = now()
  where message_id = p_message_id;
  return null;
end;
$$;

create or replace function public.taskly_enqueue_message_analysis_v30()
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
  v_timezone := coalesce(v_timezone, 330);

  insert into public.task_ai_jobs_v30(
    message_id, profile_id, status, dispatch_attempts,
    timezone_offset_minutes, created_at, updated_at
  ) values (
    new.id, new.sender_profile_id, 'queued', 0,
    v_timezone, now(), now()
  )
  on conflict (message_id) do nothing;

  perform public.taskly_dispatch_analysis_v30(new.id);
  return new;
end;
$$;

drop trigger if exists taskly_message_analysis_v30 on public.messages;
create trigger taskly_message_analysis_v30
after insert on public.messages
for each row execute function public.taskly_enqueue_message_analysis_v30();

-- Ensure sender-side Flutter Realtime listeners receive newly created suggestions.
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
    where job.dispatch_attempts < 3
      and (
        job.status in ('queued','failed')
        or (job.status = 'dispatched' and job.last_dispatched_at < now() - interval '2 minutes')
      )
    order by job.created_at
    limit greatest(1, least(coalesce(p_limit, 25), 100))
    for update skip locked
  loop
    perform public.taskly_dispatch_analysis_v30(v_job.message_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.taskly_requeue_message_v30(p_message_id bigint)
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
  if not found or v_message.sender_profile_id is distinct from me then
    raise exception 'Message not available';
  end if;

  delete from public.task_ai_decisions where message_id = p_message_id and profile_id = me;
  delete from public.task_ai_runs where message_id = p_message_id and profile_id = me;
  update public.task_ai_jobs_v30
  set status = 'queued', dispatch_attempts = 0, request_id = null,
      last_dispatched_at = null, completed_at = null,
      last_error = null, updated_at = now()
  where message_id = p_message_id and profile_id = me;
  perform public.taskly_dispatch_analysis_v30(p_message_id);
end;
$$;

create or replace function public.taskly_ai_cost_summary_v30(p_days integer default 7)
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

-- Retry only messages that never reached processing. Once processing starts,
-- paid failures are marked dead to prevent duplicate model billing.
do $$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'taskly-v30-nlu-dispatch-retry' limit 1;
  if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
  perform cron.schedule(
    'taskly-v30-nlu-dispatch-retry',
    '* * * * *',
    'select public.taskly_dispatch_pending_v30(25);'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
revoke all on function public.taskly_verify_webhook_v30(text) from public;
grant execute on function public.taskly_verify_webhook_v30(text) to service_role;

revoke all on function public.taskly_ai_claim_context_v30(bigint) from public;
grant execute on function public.taskly_ai_claim_context_v30(bigint) to authenticated, service_role;

revoke all on function public.taskly_store_ai_decision_v30(bigint, jsonb, text, text, integer, jsonb, jsonb, text) from public;
grant execute on function public.taskly_store_ai_decision_v30(bigint, jsonb, text, text, integer, jsonb, jsonb, text) to authenticated, service_role;

revoke all on function public.taskly_ai_fail_v30(bigint, text) from public;
grant execute on function public.taskly_ai_fail_v30(bigint, text) to authenticated, service_role;

revoke all on function public.taskly_requeue_message_v30(bigint) from public;
grant execute on function public.taskly_requeue_message_v30(bigint) to authenticated;

revoke all on function public.taskly_ai_cost_summary_v30(integer) from public;
grant execute on function public.taskly_ai_cost_summary_v30(integer) to authenticated;

revoke all on function public.taskly_dispatch_analysis_v30(bigint) from public;
revoke all on function public.taskly_dispatch_pending_v30(integer) from public;

notify pgrst, 'reload schema';
commit;
