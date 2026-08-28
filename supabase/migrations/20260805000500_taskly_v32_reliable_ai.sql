-- Taskly v3.2 — reliable compact AI verifier and exact per-message diagnostics
-- Run after the v3.0 and v3.1 migrations. Safe to rerun.

begin;

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
    'error', nullif(v_run.last_error, ''),
    'route', v_decision.route,
    'model_name', v_decision.model_name,
    'confidence', v_decision.confidence,
    'is_task', v_decision.is_task,
    'decision_reason', nullif(v_decision.decision->>'r', ''),
    'input_tokens', coalesce(v_decision.input_tokens, 0),
    'output_tokens', coalesce(v_decision.output_tokens, 0),
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

-- Manual retry helper for a message that failed before a decision was stored.
-- It never deletes confirmed or dismissed suggestions.
create or replace function public.taskly_retry_message_ai_v32(p_message_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me bigint := public.current_profile_id();
  v_message public.messages%rowtype;
  v_status text;
  v_timezone integer := 330;
begin
  if me is null then raise exception 'Not signed in'; end if;

  select * into v_message
  from public.messages
  where id = p_message_id
    and sender_profile_id = me
    and deleted_at is null;
  if not found then raise exception 'Message not available'; end if;

  select status into v_status
  from public.task_suggestions
  where message_id = p_message_id;

  if v_status in ('confirmed', 'dismissed') then
    return jsonb_build_object('reset', false, 'reason', 'suggestion_already_final');
  end if;

  delete from public.task_suggestions
  where message_id = p_message_id and status = 'pending';
  delete from public.task_ai_decisions where message_id = p_message_id;
  delete from public.task_ai_runs where message_id = p_message_id;

  select coalesce(preference.timezone_offset_minutes, 330)
  into v_timezone
  from public.task_ai_preferences preference
  where preference.profile_id = me;

  insert into public.task_ai_jobs_v30(
    message_id, profile_id, status, dispatch_attempts,
    timezone_offset_minutes, created_at, updated_at
  ) values (
    p_message_id, me, 'queued', 0,
    coalesce(v_timezone, 330), now(), now()
  )
  on conflict (message_id) do update
  set status = 'queued', dispatch_attempts = 0, request_id = null,
      last_dispatched_at = null, completed_at = null, last_error = null,
      timezone_offset_minutes = excluded.timezone_offset_minutes,
      updated_at = now();

  return jsonb_build_object('reset', true, 'message_id', p_message_id);
end;
$$;

revoke all on function public.taskly_retry_message_ai_v32(bigint) from public;
grant execute on function public.taskly_retry_message_ai_v32(bigint) to authenticated;

notify pgrst, 'reload schema';
commit;
