import { createClient } from "@supabase/supabase-js";
import { analyseLocally } from "./grammar_engine.ts";
import { parseDeadline } from "./datetime_parser.ts";
import { guardTaskDecision } from "./title_guard.ts";
import type {
  CompactMember,
  CompactTask,
  EngineContext,
  EngineResult,
  FeedbackExample,
  LearnedAlias,
  TaskDecision,
} from "./types.ts";

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-taskly-webhook-secret",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json; charset=utf-8",
};

const SYSTEM_INSTRUCTIONS = `You are Taskly's final verifier for exactly one chat message.
Classify the message as a task only when it is a future request, assignment, commitment, reminder, or a change to an existing task. Greetings, thanks, ordinary conversation, information questions, and completed past statements are not tasks.
The JSON field meanings are exact:
- is_task: whether Taskly should show a task request.
- confidence: confidence in that decision; use 0.90-1.00 for clear cases, 0.65-0.89 for likely cases, and below 0.55 only when genuinely uncertain.
- action: create, update, status_change, or none.
- title: for create, a short verb-first task name of 2-8 words. Never include greetings, requester names, dates, or times.
- description: one newly written sentence describing what must be done and for whom when relevant. Do not copy the whole chat message.
- assignee_id: use only an ID from people when a person is explicitly named or mentioned; otherwise null so Taskly can apply direct/self-chat defaults.
- deadline_iso: ISO-8601 with offset when a deadline exists, otherwise an empty string.
- target_task_id: use only an ID from open_tasks for update/status_change, otherwise null.
Understand English and any language, including Tanglish, Hinglish, Tamil, Hindi, transliteration, code-switching, slang, shorthand, dialects, and spelling mistakes.
Examples:
"hey bro get me the milk today at 5" => task, create, title "Buy milk".
"get the milk from Kumar today at 5" => task, create, title "Collect milk from Kumar".
"send the report tomorrow at 10" => task, create, title "Send report".
"I sent the report yesterday" => not a task.
"When will you send the report?" => not a task unless it clearly requests an action.
Return only JSON matching the schema.`;

const DECISION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    is_task: {
      type: "boolean",
      description: "True only when Taskly should show a task creation or task-change request.",
    },
    confidence: {
      type: "number",
      minimum: 0,
      maximum: 1,
      description: "Confidence in the classification. Clear task or clear non-task cases should normally be at least 0.9.",
    },
    action: {
      type: "string",
      enum: ["none", "create", "update", "status_change"],
      description: "The task operation. Use none when is_task is false.",
    },
    title: {
      type: "string",
      maxLength: 90,
      description: "Short verb-first task title without greetings, dates, or times. Empty when not creating a task.",
    },
    description: {
      type: "string",
      maxLength: 260,
      description: "A concise newly written task sentence, not a copy of the whole message.",
    },
    assignee_id: {
      anyOf: [{ type: "integer" }, { type: "null" }],
      description: "An exact ID from people only when the assignee is explicit; otherwise null.",
    },
    deadline_iso: {
      type: "string",
      maxLength: 40,
      description: "ISO-8601 deadline with timezone offset, or an empty string.",
    },
    priority: {
      type: "string",
      enum: ["low", "medium", "high"],
    },
    target_task_id: {
      anyOf: [{ type: "integer" }, { type: "null" }],
      description: "An exact ID from open_tasks for an update/status change; otherwise null.",
    },
    requested_status: {
      type: "string",
      enum: ["", "todo", "in-progress", "done"],
    },
    reason: {
      type: "string",
      maxLength: 120,
      description: "A short explanation of the decision.",
    },
    language: {
      type: "string",
      maxLength: 24,
      description: "Detected language or code-mixed language label.",
    },
  },
  required: [
    "is_task", "confidence", "action", "title", "description",
    "assignee_id", "deadline_iso", "priority", "target_task_id",
    "requested_status", "reason", "language",
  ],
} as const;

type UnknownRecord = Record<string, unknown>;
type Usage = {
  input_tokens: number;
  cached_input_tokens: number;
  output_tokens: number;
  reasoning_tokens: number;
  estimated_cost_usd: number;
};

class BilledModelOutputError extends Error {
  constructor(readonly code: string, readonly usage: Usage, readonly latencyMs: number) {
    super(code);
    this.name = "BilledModelOutputError";
  }
}

function responseJson(status: number, body: UnknownRecord): Response {
  return new Response(JSON.stringify(body), { status, headers: CORS_HEADERS });
}

function asRecord(value: unknown): UnknownRecord {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as UnknownRecord : {};
}
function asArray(value: unknown): unknown[] { return Array.isArray(value) ? value : []; }
function asString(value: unknown, fallback = ""): string { return typeof value === "string" ? value : fallback; }
function asNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}
function asNullableNumber(value: unknown): number | null {
  const parsed = asNumber(value, Number.NaN);
  return Number.isFinite(parsed) ? parsed : null;
}
function uniqueNumbers(value: unknown): number[] {
  return [...new Set(asArray(value).map(asNullableNumber).filter((item): item is number => item !== null))];
}
function envNumber(name: string, fallback: number): number {
  const parsed = Number(Deno.env.get(name));
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

function noTaskDecision(confidence: number, reason: string, language: string): TaskDecision {
  return {
    t: false, c: Math.max(0, Math.min(1, confidence)), a: "none", ttl: "", d: "", as: null,
    due: "", p: "medium", tid: null, st: "", r: reason.slice(0, 120), l: language.slice(0, 24),
  };
}

function normaliseDecision(value: unknown): TaskDecision {
  const row = asRecord(value);
  const action = asString(row.action ?? row.a);
  const priority = asString(row.priority ?? row.p);
  const status = asString(row.requested_status ?? row.st);
  const explicitTask = row.is_task === true || row.t === true;
  return {
    t: explicitTask,
    c: Math.max(0, Math.min(1, asNumber(row.confidence ?? row.c))),
    a: action === "create" || action === "update" || action === "status_change" ? action : "none",
    ttl: asString(row.title ?? row.ttl).trim().slice(0, 90),
    d: asString(row.description ?? row.d).trim().slice(0, 260),
    as: asNullableNumber(row.assignee_id ?? row.as),
    due: asString(row.deadline_iso ?? row.due).trim().slice(0, 40),
    p: priority === "low" || priority === "high" ? priority : "medium",
    tid: asNullableNumber(row.target_task_id ?? row.tid),
    st: status === "todo" || status === "in-progress" || status === "done" ? status : "",
    r: asString(row.reason ?? row.r).trim().slice(0, 120),
    l: asString(row.language ?? row.l).trim().slice(0, 24),
  };
}

function extractOutputText(response: UnknownRecord): string {
  const direct = asString(response.output_text).trim();
  if (direct) return direct;
  const parts: string[] = [];
  for (const itemValue of asArray(response.output)) {
    const item = asRecord(itemValue);
    if (item.type !== "message") continue;
    for (const contentValue of asArray(item.content)) {
      const content = asRecord(contentValue);
      if (content.type === "output_text") {
        const text = asString(content.text).trim();
        if (text) parts.push(text);
      }
    }
  }
  return parts.join("\n").trim();
}

function usageFromResponse(response: UnknownRecord, route: "ai_nano" | "ai_mini"): Usage {
  const usage = asRecord(response.usage);
  const inputDetails = asRecord(usage.input_tokens_details);
  const outputDetails = asRecord(usage.output_tokens_details);
  const inputTokens = Math.max(0, Math.trunc(asNumber(usage.input_tokens)));
  const cachedTokens = Math.max(0, Math.min(inputTokens, Math.trunc(asNumber(inputDetails.cached_tokens))));
  const outputTokens = Math.max(0, Math.trunc(asNumber(usage.output_tokens)));
  const reasoningTokens = Math.max(0, Math.trunc(asNumber(outputDetails.reasoning_tokens)));
  const prefix = route === "ai_nano" ? "OPENAI_TASK_NANO" : "OPENAI_TASK_COMPLEX";
  const inputRate = envNumber(`${prefix}_INPUT_PER_MILLION`, route === "ai_nano" ? 0.05 : 0.75);
  const cachedRate = envNumber(`${prefix}_CACHED_INPUT_PER_MILLION`, route === "ai_nano" ? 0.005 : 0.075);
  const outputRate = envNumber(`${prefix}_OUTPUT_PER_MILLION`, route === "ai_nano" ? 0.40 : 4.50);
  const estimated = (((inputTokens - cachedTokens) * inputRate) + (cachedTokens * cachedRate) + (outputTokens * outputRate)) / 1_000_000;
  return {
    input_tokens: inputTokens,
    cached_input_tokens: cachedTokens,
    output_tokens: outputTokens,
    reasoning_tokens: reasoningTokens,
    estimated_cost_usd: Number(estimated.toFixed(8)),
  };
}

function comparableText(value: string): string {
  return value.toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

function looksCopied(value: string, original: string): boolean {
  const compactValue = comparableText(value);
  const compactOriginal = comparableText(original);
  if (!compactValue || compactOriginal.length < 18) return false;
  return compactValue === compactOriginal
    || (compactValue.length >= compactOriginal.length * 0.82 && compactOriginal.includes(compactValue));
}

function validateModelDecision(
  decision: TaskDecision,
  members: CompactMember[],
  tasks: CompactTask[],
  originalMessage: string,
  engine: EngineResult,
  createdAt: string,
  timezoneOffsetMinutes: number,
): TaskDecision {
  const memberIds = new Set(members.map((member) => member.id));
  const taskIds = new Set(tasks.map((task) => task.id));
  if (decision.as !== null && !memberIds.has(decision.as)) decision.as = null;
  if (decision.tid !== null && !taskIds.has(decision.tid)) decision.tid = null;
  if (!decision.t) return noTaskDecision(decision.c, decision.r || "Not a task.", decision.l);

  if (decision.a === "create") {
    const candidate = engine.candidate;
    if ((!decision.ttl || looksCopied(decision.ttl, originalMessage)) && candidate?.title) {
      decision.ttl = candidate.title.slice(0, 90);
      decision.c = Math.min(decision.c, Math.max(0.60, candidate.confidence));
    }
    if ((!decision.d || looksCopied(decision.d, originalMessage)) && candidate?.description) {
      decision.d = candidate.description.slice(0, 260);
    }
    if (!decision.ttl) {
      return noTaskDecision(Math.min(decision.c, 0.45), "Model output lacked a safe title.", decision.l);
    }
    if (!decision.d) decision.d = `${decision.ttl}.`;
  }

  if ((decision.a === "update" || decision.a === "status_change") && decision.tid === null) {
    return noTaskDecision(Math.min(decision.c, 0.45), "Existing task could not be safely resolved.", decision.l);
  }
  const parsedDeadline = parseDeadline(originalMessage, createdAt, timezoneOffsetMinutes);
  return guardTaskDecision(decision, originalMessage, engine.candidate, parsedDeadline);
}

function recoverWithConfidentLocalDecision(
  modelDecision: TaskDecision,
  engine: EngineResult,
  originalMessage: string,
  createdAt: string,
  timezoneOffsetMinutes: number,
): TaskDecision {
  if (modelDecision.t || modelDecision.c > 0.35 || !engine.decision?.t) return modelDecision;
  if (engine.route !== "local_create" && engine.route !== "local_update") return modelDecision;
  if (engine.intentConfidence < 0.82 || engine.canonicalConfidence < 0.70) return modelDecision;

  const localDeadline = parseDeadline(originalMessage, createdAt, timezoneOffsetMinutes);
  const recovered = guardTaskDecision(
    { ...engine.decision },
    originalMessage,
    engine.candidate,
    localDeadline,
  );
  if (!recovered.t) return modelDecision;
  recovered.c = Math.max(0.72, Math.min(0.88, Math.max(engine.intentConfidence, engine.canonicalConfidence)));
  recovered.r = "High-confidence local NLU recovered a low-confidence AI rejection.";
  return recovered;
}

function compactModelContext(
  rawContext: UnknownRecord,
  engine: EngineResult,
  timezoneOffsetMinutes: number,
  route: "ai_nano" | "ai_mini",
): UnknownRecord {
  const message = asRecord(rawContext.message);
  const profile = asRecord(rawContext.profile);
  const workspace = asRecord(rawContext.workspace);
  const people = asArray(rawContext.members).slice(0, 12).map((value) => {
    const row = asRecord(value);
    return { id: asNumber(row.id), name: asString(row.name).slice(0, 48) };
  });
  const openTasks = route === "ai_mini" ? asArray(rawContext.open_tasks).map((value) => {
    const row = asRecord(value);
    return {
      id: asNumber(row.id),
      title: asString(row.title).slice(0, 90),
      status: asString(row.status),
      assignee_id: asNullableNumber(row.assignee_id),
      deadline: asString(row.deadline),
    };
  }) : [];
  const candidate = engine.candidate ? {
    action: engine.candidate.actionKey,
    object: engine.candidate.object.slice(0, 100),
    source: engine.candidate.source.slice(0, 60),
    proposed_title: engine.candidate.title.slice(0, 90),
    proposed_description: engine.candidate.description.slice(0, 180),
    issues: engine.candidate.issues.slice(0, 3),
  } : null;
  return {
    current_time_iso: asString(message.created_at),
    timezone_offset_minutes: timezoneOffsetMinutes,
    sender: { id: asNumber(profile.id), name: asString(profile.name).slice(0, 60) },
    workspace: { kind: asString(workspace.kind), direct_key: asString(workspace.direct_key).slice(0, 80) },
    chat_message: asString(message.body).slice(0, 420),
    mentioned_profile_ids: uniqueNumbers(message.mentioned_profile_ids),
    people,
    open_tasks: openTasks,
    local_nlu: {
      task_confidence: Number(engine.intentConfidence.toFixed(3)),
      canonicalization_confidence: Number(engine.canonicalConfidence.toFixed(3)),
      reason: engine.fallbackReason || engine.reason,
      candidate,
    },
  };
}

async function callOpenAI(
  apiKey: string,
  model: string,
  route: "ai_nano" | "ai_mini",
  modelContext: UnknownRecord,
): Promise<{ decision: TaskDecision; usage: Usage; latencyMs: number }> {
  const controller = new AbortController();
  const timeoutMs = Math.max(4_000, Math.trunc(envNumber("OPENAI_TASK_TIMEOUT_MS", 10_000)));
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const started = Date.now();
  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({
        model,
        store: false,
        reasoning: { effort: "minimal" },
        max_output_tokens: Math.max(140, Math.min(240, Math.trunc(envNumber("OPENAI_TASK_MAX_OUTPUT_TOKENS", 180)))),
        instructions: SYSTEM_INSTRUCTIONS,
        prompt_cache_key: "taskly-task-v33",
        input: [{
          role: "user",
          content: [{
            type: "input_text",
            text: `Analyse this one Taskly chat message. Context JSON:
${JSON.stringify(modelContext)}`,
          }],
        }],
        text: {
          verbosity: "low",
          format: {
            type: "json_schema",
            name: "taskly_task_v33",
            description: "Taskly task classification and canonical task fields for one chat message.",
            strict: true,
            schema: DECISION_SCHEMA,
          },
        },
      }),
      signal: controller.signal,
    });
    const body = asRecord(await response.json().catch(() => ({})));
    if (!response.ok) {
      const error = asRecord(body.error);
      throw new Error(`OpenAI ${response.status}: ${asString(error.message, "request failed").slice(0, 240)}`);
    }
    const usage = usageFromResponse(body, route);
    if (asString(body.status) === "incomplete") {
      const details = asRecord(body.incomplete_details);
      throw new BilledModelOutputError(
        `model_incomplete:${asString(details.reason, "unknown")}`,
        usage,
        Date.now() - started,
      );
    }
    const latencyMs = Date.now() - started;
    const outputText = extractOutputText(body);
    if (!outputText) throw new BilledModelOutputError("model_empty_output", usage, latencyMs);
    try {
      return { decision: normaliseDecision(JSON.parse(outputText)), usage, latencyMs };
    } catch {
      throw new BilledModelOutputError("model_invalid_json", usage, latencyMs);
    }
  } finally {
    clearTimeout(timer);
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (request.method !== "POST") return responseJson(405, { analysed: false, suggestion: null, skipped: "method_not_allowed" });

  const authorization = request.headers.get("authorization") ?? "";
  const suppliedWebhookSecret = request.headers.get("x-taskly-webhook-secret") ?? "";
  const authenticatedRequest = authorization.toLocaleLowerCase().startsWith("bearer ");
  if (!authenticatedRequest && suppliedWebhookSecret.length < 32) {
    return responseJson(401, { analysed: false, suggestion: null, skipped: "not_authenticated" });
  }

  let payload: UnknownRecord;
  try { payload = asRecord(await request.json()); }
  catch { return responseJson(400, { analysed: false, suggestion: null, skipped: "invalid_json" }); }

  const messageId = asNullableNumber(payload.message_id ?? payload.messageId);
  if (messageId === null || messageId <= 0) {
    return responseJson(400, { analysed: false, suggestion: null, skipped: "invalid_message_id" });
  }
  const timezoneOffset = asNullableNumber(payload.timezone_offset_minutes ?? payload.utc_offset_minutes ?? payload.timezoneOffsetMinutes)
    ?? Math.trunc(envNumber("TASKLY_DEFAULT_TIMEZONE_OFFSET_MINUTES", 330));

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const userKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey || (!authenticatedRequest && suppliedWebhookSecret.length < 32)) {
    return responseJson(200, { analysed: false, suggestion: null, skipped: "supabase_not_configured" });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let internalRequest = false;
  if (suppliedWebhookSecret.length >= 32) {
    const verification = await serviceClient.rpc("taskly_verify_webhook_v30", {
      p_secret: suppliedWebhookSecret,
    });
    internalRequest = verification.error === null && verification.data === true;
  }
  if (!internalRequest && !authenticatedRequest) {
    return responseJson(401, { analysed: false, suggestion: null, skipped: "invalid_webhook_secret" });
  }
  if (!internalRequest && !userKey) {
    return responseJson(200, { analysed: false, suggestion: null, skipped: "supabase_anon_key_missing" });
  }

  const supabase = internalRequest
    ? serviceClient
    : createClient(supabaseUrl, userKey, {
      global: { headers: { authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

  const claim = await supabase.rpc("taskly_ai_claim_context_v30", { p_message_id: messageId });
  if (claim.error) {
    console.error("taskly_ai_claim_context_v30 failed", claim.error.message);
    return responseJson(200, { analysed: false, suggestion: null, skipped: "context_unavailable" });
  }
  const claimData = asRecord(claim.data);
  if (claimData.claimed !== true) {
    const existingSuggestion = asRecord(claimData.existing_suggestion);
    if (Object.keys(existingSuggestion).length > 0) existingSuggestion.message_id = messageId;
    return responseJson(200, {
      message_id: messageId,
      analysed: claimData.analysed === true,
      suggestion: Object.keys(existingSuggestion).length > 0 ? existingSuggestion : null,
      skipped: asString(claimData.skipped, "duplicate_or_already_processed"),
      duplicate: true,
    });
  }

  const rawContext = asRecord(claimData.context);
  const message = asRecord(rawContext.message);
  const profile = asRecord(rawContext.profile);
  const workspace = asRecord(rawContext.workspace);
  const members: CompactMember[] = asArray(rawContext.members).map((value) => {
    const row = asRecord(value);
    return { id: asNumber(row.id), name: asString(row.name), role: asString(row.role) || null };
  }).filter((member) => member.id > 0 && member.name);
  const openTasks: CompactTask[] = asArray(rawContext.open_tasks).map((value) => {
    const row = asRecord(value);
    return {
      id: asNumber(row.id), title: asString(row.title), status: asString(row.status) || null,
      assignee_id: asNullableNumber(row.assignee_id), deadline: asString(row.deadline) || null,
    };
  }).filter((task) => task.id > 0 && task.title);
  const learnedAliases: LearnedAlias[] = asArray(rawContext.learned_aliases).map((value) => {
    const row = asRecord(value);
    return {
      source_phrase: asString(row.source_phrase).toLocaleLowerCase(),
      canonical_action: asString(row.canonical_action).toLocaleLowerCase(),
      accepted_count: Math.max(0, Math.trunc(asNumber(row.accepted_count))),
      rejected_count: Math.max(0, Math.trunc(asNumber(row.rejected_count))),
    };
  }).filter((row) => row.source_phrase && row.canonical_action);
  const feedbackExamples: FeedbackExample[] = asArray(rawContext.feedback_examples).map((value) => {
    const row = asRecord(value);
    return {
      message_text: asString(row.message_text),
      outcome: asString(row.outcome),
      similarity: Math.max(0, Math.min(1, asNumber(row.similarity))),
      final_task: asRecord(row.final_task),
    };
  });

  const engineContext: EngineContext = {
    profileId: asNumber(profile.id),
    profileName: asString(profile.name),
    workspaceKind: asString(workspace.kind),
    directKey: asString(workspace.direct_key) || null,
    members,
    mentionedProfileIds: uniqueNumbers(message.mentioned_profile_ids),
    openTasks,
    createdAt: asString(message.created_at),
    timezoneOffsetMinutes: timezoneOffset,
    learnedAliases,
    feedbackExamples,
  };
  const engine = analyseLocally(asString(message.body).slice(0, 2_000), engineContext);

  const zeroUsage: Usage = { input_tokens: 0, cached_input_tokens: 0, output_tokens: 0, reasoning_tokens: 0, estimated_cost_usd: 0 };
  const analysisMeta = {
    intent_confidence: engine.intentConfidence,
    canonical_confidence: engine.canonicalConfidence,
    fallback_reason: engine.fallbackReason,
    language: engine.languageHint,
    model_task_probability: engine.modelTaskProbability ?? null,
    local_model_version: engine.modelVersion ?? null,
  };

  async function store(decision: TaskDecision, modelName: string, route: string, latencyMs: number, usage: Usage, skipReason: string): Promise<Response> {
    const stored = await supabase.rpc("taskly_store_ai_decision_v30", {
      p_message_id: messageId,
      p_decision: decision,
      p_model_name: modelName,
      p_route: route,
      p_latency_ms: latencyMs,
      p_usage: usage,
      p_analysis: analysisMeta,
      p_skip_reason: skipReason || null,
    });
    if (stored.error) {
      console.error("taskly_store_ai_decision_v30 failed", stored.error.message);
      await supabase.rpc("taskly_ai_fail_v30", { p_message_id: messageId, p_error: "store_failed" });
      return responseJson(200, { analysed: false, suggestion: null, skipped: "store_failed" });
    }
    const body = asRecord(stored.data);
    body.message_id = messageId;
    body.model_name = modelName;
    body.diagnostic = {
      decision_is_task: decision.t,
      decision_confidence: decision.c,
      decision_action: decision.a,
      decision_reason: decision.r,
      engine_route: engine.route,
      local_intent_confidence: engine.intentConfidence,
      local_canonical_confidence: engine.canonicalConfidence,
    };
    const suggestion = asRecord(body.suggestion);
    if (Object.keys(suggestion).length > 0) {
      suggestion.message_id = messageId;
      body.suggestion = suggestion;
    }
    return responseJson(200, body);
  }

  // v3.3 keeps clear messages fully local. This makes title, description,
  // deadline and assignee generation free for high-confidence tasks. Unknown,
  // ambiguous or compound language still receives exactly one AI fallback.
  if (engine.route === "local_skip" && engine.decision) {
    return await store(engine.decision, "taskly-local-nlu-v33", engine.route, 0, zeroUsage, engine.reason);
  }
  if ((engine.route === "local_create" || engine.route === "local_update") && engine.decision) {
    const localDeadline = parseDeadline(asString(message.body), asString(message.created_at), timezoneOffset);
    const guarded = guardTaskDecision(engine.decision, asString(message.body), engine.candidate, localDeadline);
    return await store(guarded, "taskly-local-nlu-v33", engine.route, 0, zeroUsage, engine.reason);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!apiKey) {
    if (engine.decision && (engine.route === "local_create" || engine.route === "local_update")) {
      const localDeadline = parseDeadline(asString(message.body), asString(message.created_at), timezoneOffset);
      const guarded = guardTaskDecision(engine.decision, asString(message.body), engine.candidate, localDeadline);
      return await store(guarded, "taskly-statistical-nlu-v31", "local_fallback_no_api", 0, zeroUsage, "openai_not_configured");
    }
    await supabase.rpc("taskly_ai_fail_v30", { p_message_id: messageId, p_error: "openai_not_configured" });
    return responseJson(200, { message_id: messageId, analysed: false, suggestion: null, skipped: "openai_not_configured" });
  }

  const route: "ai_nano" | "ai_mini" = engine.route === "ai_mini" ? "ai_mini" : "ai_nano";
  const model = route === "ai_mini"
    ? (Deno.env.get("OPENAI_TASK_COMPLEX_MODEL") ?? "gpt-5-mini")
    : (Deno.env.get("OPENAI_TASK_NANO_MODEL") ?? "gpt-5-nano");

  try {
    const modelResult = await callOpenAI(apiKey, model, route, compactModelContext(rawContext, engine, timezoneOffset, route));
    const validatedModelDecision = validateModelDecision(
      modelResult.decision,
      members,
      openTasks,
      asString(message.body),
      engine,
      asString(message.created_at),
      timezoneOffset,
    );
    const decision = recoverWithConfidentLocalDecision(
      validatedModelDecision,
      engine,
      asString(message.body),
      asString(message.created_at),
      timezoneOffset,
    );
    console.info("Taskly v3.3 decision", JSON.stringify({
      message_id: messageId,
      model,
      route,
      is_task: decision.t,
      confidence: decision.c,
      action: decision.a,
      title_length: decision.ttl.length,
      reason: decision.r,
      local_route: engine.route,
      local_intent: engine.intentConfidence,
      local_canonical: engine.canonicalConfidence,
    }));
    return await store(decision, model, route, modelResult.latencyMs, modelResult.usage, "");
  } catch (error) {
    if (error instanceof BilledModelOutputError) {
      return await store(
        noTaskDecision(engine.intentConfidence, error.code, engine.languageHint),
        model, route, error.latencyMs, error.usage, error.code,
      );
    }
    const errorMessage = error instanceof Error ? error.message : "unknown_openai_error";
    console.error("Taskly v3.3 model call failed", errorMessage);
    await supabase.rpc("taskly_ai_fail_v30", { p_message_id: messageId, p_error: errorMessage.slice(0, 500) });
    return responseJson(200, {
      message_id: messageId,
      analysed: false,
      suggestion: null,
      skipped: "model_unavailable",
      error: errorMessage,
    });
  }
});
