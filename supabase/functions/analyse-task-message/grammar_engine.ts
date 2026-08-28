import { canonicalizeTask } from "./canonicalizer.ts";
import { parseDeadline } from "./datetime_parser.ts";
import { classifyTaskIntent } from "./intent_model.ts";
import {
  ACK_ONLY,
  FUTURE_COMMITMENT,
  GREETING_ONLY,
  PAST_STATEMENT,
  QUESTION_START,
  REQUEST_MARKER,
  SELF_REMINDER,
  URGENCY,
  actionByKey,
  findAction,
  languageHint,
  normaliseText,
} from "./language_pack.ts";
import type {
  CompactMember,
  CompactTask,
  EngineContext,
  EngineResult,
  TaskDecision,
  TaskPriority,
  TaskStatus,
} from "./types.ts";

const STATUS_WORDS = /\b(?:mark|set|change|move|update|close|reopen|complete|completed|done|finish|finished|in\s*progress|started|cancel|cancelled|canceled|hold|blocked|pending|todo|mudichachu|mudichiten|start\s+panniten|ho\s*gaya|முடிந்தது|शुरू|पूरा)\b/iu;
const STATUS_TARGET = /\b(?:todo|to\s*do|pending|open|reopen|in\s*progress|doing|started|done|completed|complete|finished|closed|cancelled|canceled|blocked|hold|mudichachu|ho\s*gaya|முடிந்தது|पूरा)\b/iu;
const REQUEST_QUESTION = /^(?:can|could|would|will)\s+you\b/iu;
const CONNECTOR_COMPLEX = /\b(?:and\s+then|after\s+that|once\s+done|depending\s+on|if\s+.+\s+then|unless|apram|appuram|phir|பிறகு|फिर)\b/iu;
const CLEAR_STATEMENT_SHAPE = /^(?:(?:i|we|you|he|she|they|it|this|that|there|naan|na|main|hum|நான்|நாங்கள்|मैं|हम)\s+(?:am|is|are|was|were|have|has|had|like|love|want|know|think|feel|went|came|said|told|finished|completed|sent|shared|did|do|does|will\s+be)|[\p{L}][\p{L} .'-]{1,50}\s+(?:is|are|was|were|has|have|had|went|came|said|told|looks|seems|will\s+be))\b/iu;

function clamp(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function onlyNoise(text: string): boolean {
  if (!text) return true;
  const withoutMentions = text.replace(/@[\p{L}\p{N}_.-]+/gu, "");
  const withoutUrls = withoutMentions.replace(/\bURL\b/giu, "");
  return withoutUrls.replace(/[\p{P}\p{S}\p{N}\s_]/gu, "").length === 0;
}

function memberFromText(text: string, members: CompactMember[]): number | null {
  const lower = text.toLocaleLowerCase().trimStart();
  const matches: number[] = [];
  const statementStart = /^(?:is|are|was|were|has|have|had|went|came|said|told|finished|completed|sent|shared|did|does|looks|seems|will\s+be)\b/iu;
  for (const member of members) {
    const full = member.name.trim().toLocaleLowerCase();
    if (!full) continue;
    const first = full.split(/\s+/u)[0] ?? full;
    for (const name of new Set([full, first])) {
      if (lower.includes(`@${name}`) || lower.includes(`@${name.replace(/\s+/g, "")}`)) matches.push(member.id);
      if (lower.startsWith(`${name},`) || lower.startsWith(`${name}:`)) matches.push(member.id);
      else if (lower.startsWith(`${name} `)) {
        const rest = lower.slice(name.length).trimStart();
        if (rest && !statementStart.test(rest)) matches.push(member.id);
      }
    }
  }
  const unique = [...new Set(matches)];
  return unique.length === 1 ? unique[0]! : null;
}

function resolveAssignee(text: string, context: EngineContext, commitment: boolean, selfReminder: boolean): number | null {
  const mentions = [...new Set(context.mentionedProfileIds.filter((id) => Number.isFinite(id) && id > 0))];
  if (mentions.length === 1) return mentions[0]!;
  const named = memberFromText(text, context.members);
  if (named !== null) return named;
  if (commitment || selfReminder) return context.profileId;
  if (context.workspaceKind === "direct" && context.directKey === `self:${context.profileId}`) return context.profileId;
  if (context.workspaceKind === "direct") {
    const others = context.members.filter((member) => member.id !== context.profileId);
    if (others.length === 1) return others[0]!.id;
  }
  return null;
}

function priority(text: string): TaskPriority {
  if (URGENCY.test(text)) return "high";
  if (/\b(?:low\s+priority|whenever|no\s+rush|when\s+free|time\s+irundha|free\s+ah\s+irundha)\b/iu.test(text)) return "low";
  return "medium";
}

function statusFromText(text: string): TaskStatus {
  if (/\b(?:done|completed|complete|finished|closed|mudichachu|mudichiten|ho\s*gaya|முடிந்தது|पूरा)\b/iu.test(text)) return "done";
  if (/\b(?:in\s*progress|doing|started|start\s+panniten|working\s+on|தொடங்கிவிட்டது|शुरू)\b/iu.test(text)) return "in-progress";
  if (/\b(?:todo|to\s*do|pending|reopen|open|hold|blocked)\b/iu.test(text)) return "todo";
  return "";
}

function tokens(value: string): Set<string> {
  return new Set(value.toLocaleLowerCase().split(/[^\p{L}\p{N}]+/u).filter((word) => word.length >= 3));
}

function taskMatch(text: string, tasks: CompactTask[]): { task: CompactTask | null; score: number } {
  const messageWords = tokens(text);
  let best: CompactTask | null = null;
  let bestScore = 0;
  for (const task of tasks) {
    const taskWords = tokens(task.title);
    if (taskWords.size === 0) continue;
    let hits = 0;
    for (const word of taskWords) if (messageWords.has(word)) hits += 1;
    const score = hits / taskWords.size;
    if (score > bestScore) {
      bestScore = score;
      best = task;
    }
  }
  return { task: best, score: bestScore };
}

function feedbackSignal(context: EngineContext): { accepted: number; rejected: number } {
  let accepted = 0;
  let rejected = 0;
  for (const example of context.feedbackExamples) {
    if (example.similarity < 0.70) continue;
    if (example.outcome === "accepted") accepted = Math.max(accepted, example.similarity);
    if (example.outcome === "rejected") rejected = Math.max(rejected, example.similarity);
  }
  return { accepted, rejected };
}

function noTask(confidence: number, reason: string, lang: string): TaskDecision {
  return {
    t: false,
    c: clamp(confidence),
    a: "none",
    ttl: "",
    d: "",
    as: null,
    due: "",
    p: "medium",
    tid: null,
    st: "",
    r: reason.slice(0, 160),
    l: lang.slice(0, 24),
  };
}

export function analyseLocally(rawText: string, context: EngineContext): EngineResult {
  const text = normaliseText(rawText);
  const lang = languageHint(text);
  const statistical = classifyTaskIntent(text);
  const modelTask = statistical.taskProbability;

  if (!text || text.length < 2 || onlyNoise(text)) {
    return { route: "local_skip", reason: "empty_or_non_text", languageHint: lang, intentConfidence: 0, canonicalConfidence: 0, fallbackReason: "", decision: noTask(0, "No task text detected.", lang) };
  }
  const conversationalGreeting = /^(?:(?:h+i+|h+e+y+|hello+|hola|vanakkam+|namaste+|yo+|dei+|arey+|oye+)[\s,!.-]*(?:bro+|brother|sis+|machi+|machan+|anna+|akka+|da+|di+|ji+|boss+)?)?[\s!?.…]*$/iu.test(text) && text.length >= 2;
  const conversationalAck = /^(?:(?:haan\s+(?:theek|thik)\s+hai)|(?:(?:seri|sari|aama|ama|haan|ha|acha|accha|theek|thik|okay|ok)[\s,!.-]*(?:bro+|machi+|machan+|anna+|akka+|da+|di+|ji+|hai+)*))[\s!?.…]*$/iu.test(text);
  if (GREETING_ONLY.test(text) || ACK_ONLY.test(text) || conversationalGreeting || conversationalAck) {
    return { route: "local_skip", reason: "greeting_or_acknowledgement", languageHint: lang, intentConfidence: 0.02, canonicalConfidence: 0, fallbackReason: "", decision: noTask(0.02, "Greeting or acknowledgement.", lang), modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }
  if (/^(?:URL\s*)+$/iu.test(text)) {
    return { route: "local_skip", reason: "link_only", languageHint: lang, intentConfidence: 0.01, canonicalConfidence: 0, fallbackReason: "", decision: noTask(0.01, "Link-only message.", lang) };
  }

  const request = REQUEST_MARKER.test(text) || REQUEST_QUESTION.test(text);
  const reminder = SELF_REMINDER.test(text);
  const commitment = FUTURE_COMMITMENT.test(text);
  const strongPastMorphology = /\b(?:anupiten|anuppiten|panniten|senjiten|mudichiten|vangiten|bhej\s*diya|kar\s*diya|ho\s*gaya)\b[\s.!?]*$/iu.test(text);
  const thirdPersonPast = /^(?:[\p{L}][\p{L} .'-]{0,60})\s+(?:completed|finished|sent|shared|submitted|called|updated|uploaded|downloaded|printed|saved|received|bought|collected)\b/iu.test(text);
  const past = PAST_STATEMENT.test(text) || strongPastMorphology || thirdPersonPast;
  const whQuestion = /^(?:what|why|when|where|who|which|how|enna|yen|eppo|enga|yaar|epdi|epadi|kya|kyu|kyun|kab|kahan|kaun|kaise|என்ன|ஏன்|எப்போது|எங்கே|யார்|எப்படி|क्या|क्यों|कब|कहाँ|कौन|कैसे)\b/iu.test(text);
  const auxiliaryQuestion = /^(?:is|are|am|was|were|do|does|did|can|could|would|will|should|have|has|had)\s+(?:i|we|you|he|she|they|it|this|that|there)\b/iu.test(text);
  const question = text.endsWith("?") || whQuestion || auxiliaryQuestion;
  const informationQuestion = /^(?:what|why|when|where|who|which|how|enna|yen|eppo|enga|yaar|epdi|epadi|kya|kyu|kyun|kab|kahan|kaun|kaise|என்ன|ஏன்|எப்போது|எங்கே|யார்|எப்படி|क्या|क्यों|कब|कहाँ|कौन|कैसे)\b/iu.test(text);
  const action = findAction(text, context.learnedAliases);
  const named = memberFromText(text, context.members);
  const hasAddressee = named !== null || context.mentionedProfileIds.length > 0 || /@[\p{L}\p{N}_.-]+/u.test(text);
  const status = statusFromText(text);
  const statusLanguage = STATUS_WORDS.test(text) || STATUS_TARGET.test(text);
  const matchingTask = taskMatch(text, context.openTasks);
  const feedback = feedbackSignal(context);
  const earlyDeadline = parseDeadline(text, context.createdAt, context.timezoneOffsetMinutes);
  const hasFutureTimeSignal = earlyDeadline.found || /\b(?:today|tomorrow|tonight|later|eod|tmr|tmrw|aaj|kal|nalaiku|naalaiku|innaiku|manikku|baje|இன்று|நாளை|आज|कल)\b/iu.test(text);
  const calendarStatement = /^(?:(?:kal|aaj|nalaiku|naalaiku|innaiku|today|tomorrow|நாளை|இன்று)\s+(?:meeting|leave|holiday|off|விடுமுறை|மீட்டிங்|hai|irukku)|(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)?|morning|evening)\s+(?:is|was)\s+)/iu.test(text);
  const copulaStatusStatement = /\b(?:is|are|was|were)\s+(?:complete|completed|done|finished|closed|pending|blocked)\b/iu.test(text);
  if (copulaStatusStatement && !request && !reminder && !commitment && !hasAddressee && context.openTasks.length === 0) {
    return { route: "local_skip", reason: "status_statement_without_task_target", languageHint: lang, intentConfidence: Math.min(modelTask, 0.18), canonicalConfidence: 0, fallbackReason: "", decision: noTask(Math.min(modelTask, 0.18), "Status statement, not a task command.", lang), modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }
  if (calendarStatement && modelTask <= 0.08 && !request && !reminder && !commitment && !action && !hasAddressee) {
    return { route: "local_skip", reason: "calendar_or_time_statement", languageHint: lang, intentConfidence: Math.min(modelTask, 0.18), canonicalConfidence: 0, fallbackReason: "", decision: noTask(Math.min(modelTask, 0.18), "Calendar or time statement, not a task request.", lang), modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }

  // Strong declarative grammar is safe to skip even when a statistical feature
  // overlaps a task phrase. This prevents normal chat from spending API tokens.
  const pastCopulaStatement = /\b(?:was|were|irundhuchu|irundhadhu|tha|thi|थे|था|இருந்தது)\b/iu.test(text);
  if (CLEAR_STATEMENT_SHAPE.test(text) && (!hasFutureTimeSignal || pastCopulaStatement) && !request && !reminder && !commitment && (!action || action.start > 0) && !hasAddressee && !statusLanguage) {
    return { route: "local_skip", reason: "clear_declarative_statement", languageHint: lang, intentConfidence: Math.min(modelTask, 0.18), canonicalConfidence: 0, fallbackReason: "", decision: noTask(Math.min(modelTask, 0.18), "Declarative conversation, not a task request.", lang), modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }

  if (statusLanguage && status && matchingTask.task && matchingTask.score >= 0.72) {
    const task = matchingTask.task;
    const decision: TaskDecision = {
      t: true,
      c: Math.min(0.98, 0.82 + matchingTask.score * 0.14),
      a: "status_change",
      ttl: task.title,
      d: "",
      as: task.assignee_id ?? null,
      due: task.deadline ?? "",
      p: "medium",
      tid: task.id,
      st: status,
      r: "Matched an existing task and status locally.",
      l: lang,
    };
    return { route: "local_update", reason: "clear_existing_task_status", languageHint: lang, intentConfidence: decision.c, canonicalConfidence: matchingTask.score, fallbackReason: "", decision };
  }

  if (statusLanguage && (matchingTask.score >= 0.30 || context.openTasks.length > 0)) {
    return { route: "ai_mini", reason: "existing_task_reference_needs_resolution", languageHint: lang, intentConfidence: Math.max(0.58, matchingTask.score), canonicalConfidence: matchingTask.score, fallbackReason: "task_reference_ambiguous" };
  }

  if (past && !request && !reminder && !commitment) {
    if (strongPastMorphology || modelTask <= 0.08) {
      return { route: "local_skip", reason: "past_statement", languageHint: lang, intentConfidence: modelTask, canonicalConfidence: 0, fallbackReason: "", decision: noTask(modelTask, "Past statement, not a new task.", lang), modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
    }
    return { route: "ai_nano", reason: "past_or_task_meaning_uncertain", languageHint: lang, intentConfidence: modelTask, canonicalConfidence: 0, fallbackReason: "statistical_model_disagreed_with_past_rule", modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }

  if (question && (informationQuestion || (!request && !reminder && !commitment))) {
    if (modelTask <= 0.08) {
      return { route: "local_skip", reason: "information_question", languageHint: lang, intentConfidence: modelTask, canonicalConfidence: 0, fallbackReason: "", decision: noTask(modelTask, "Information question, not a task request.", lang), modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
    }
    return { route: "ai_nano", reason: "question_or_request_uncertain", languageHint: lang, intentConfidence: modelTask, canonicalConfidence: 0, fallbackReason: "statistical_model_disagreed_with_question_rule", modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }

  const deadline = earlyDeadline;
  let ruleIntent = 0;
  if (action) ruleIntent += 0.38;
  if (request) ruleIntent += 0.28;
  if (reminder) ruleIntent += 0.34;
  if (commitment) ruleIntent += 0.34;
  if (hasAddressee) ruleIntent += 0.16;
  if (deadline.found) ruleIntent += 0.10;
  if (text.split(/\s+/u).length >= 3) ruleIntent += 0.04;
  if (feedback.accepted >= 0.75) ruleIntent += 0.08;
  if (feedback.rejected >= 0.75) ruleIntent -= 0.16;
  if (question && !request) ruleIntent -= 0.14;
  ruleIntent = clamp(ruleIntent);
  // The trained character/word n-gram model carries most of the intent score.
  // Grammar signals improve precision and personal feedback can adjust it.
  let intent = clamp(modelTask * 0.62 + ruleIntent * 0.38);

  const possibleUnknownRequest = request || reminder || commitment || hasAddressee || hasFutureTimeSignal || modelTask >= 0.08;
  if (!possibleUnknownRequest) {
    const wordCount = text.split(/\s+/u).filter(Boolean).length;
    const compactScriptText = text.replace(/[\p{P}\p{S}\s]/gu, "");
    const isShortLatinChat = /\p{Script=Latin}/u.test(text) && wordCount <= 2;
    const strongNonTask = modelTask <= 0.075 && (CLEAR_STATEMENT_SHAPE.test(text) || isShortLatinChat || compactScriptText.length < 4);
    if (strongNonTask) {
      return { route: "local_skip", reason: "statistical_non_task", languageHint: lang, intentConfidence: intent, canonicalConfidence: 0, fallbackReason: "", decision: noTask(intent, "Local NLU classified this as normal conversation.", lang), modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
    }
    // Do not discard unfamiliar languages or grammar. Ambiguous text gets one
    // compact fallback call instead of becoming a silent false negative.
    return { route: "ai_nano", reason: "nlu_uncertain", languageHint: lang, intentConfidence: intent, canonicalConfidence: 0, fallbackReason: "local_model_not_confident_enough_to_skip", modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }

  const assignee = resolveAssignee(text, context, commitment, reminder);
  const candidate = canonicalizeTask(
    text,
    context.members,
    context.learnedAliases,
    context.feedbackExamples,
    deadline,
    context.profileName,
  );
  if (candidate.actionKey) intent = clamp(intent + (action ? 0.18 : 0.26));
  const complex = CONNECTOR_COMPLEX.test(text) || candidate.issues.includes("multiple_actions") || text.length > 420;

  if (complex) {
    return { route: "ai_mini", reason: "compound_or_complex_task", languageHint: lang, intentConfidence: intent, canonicalConfidence: candidate.confidence, fallbackReason: "multiple_actions_or_conditions", candidate };
  }
  const canonicalActionKnown = actionByKey(candidate.actionKey) !== null;
  const trustedKnownAction = (action?.confidence ?? (canonicalActionKnown ? 0.94 : 0)) >= 0.90
    && candidate.confidence >= 0.86
    && candidate.issues.length === 0;
  const trustedLocalSignal = commitment
    || reminder
    || action?.learned === true
    || feedback.accepted >= 0.82
    || trustedKnownAction;
  if ((intent < 0.60 || modelTask < 0.48) && !trustedLocalSignal) {
    return { route: "ai_nano", reason: "task_intent_uncertain", languageHint: lang, intentConfidence: intent, canonicalConfidence: candidate.confidence, fallbackReason: "intent_below_local_threshold", candidate, modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }
  if (assignee === null) {
    return { route: "ai_nano", reason: "assignee_requires_resolution", languageHint: lang, intentConfidence: intent, canonicalConfidence: candidate.confidence, fallbackReason: "assignee_unresolved", candidate };
  }
  if (deadline.found && deadline.confidence < 0.78) {
    return { route: "ai_nano", reason: "deadline_requires_resolution", languageHint: lang, intentConfidence: intent, canonicalConfidence: candidate.confidence, fallbackReason: "deadline_low_confidence", candidate };
  }
  const safeUnknownAction = !action
    && (request || canonicalActionKnown)
    && modelTask >= 0.80
    && candidate.confidence >= 0.82
    && candidate.issues.length === 0
    && /^[\p{L}][\p{L}_-]{1,39}$/u.test(candidate.actionKey);
  if ((!action && !safeUnknownAction) || candidate.confidence < 0.82 || candidate.issues.length > 0) {
    return { route: "ai_nano", reason: "canonical_title_or_description_uncertain", languageHint: lang, intentConfidence: intent, canonicalConfidence: candidate.confidence, fallbackReason: candidate.issues.join(",") || "canonical_low_confidence", candidate, modelTaskProbability: modelTask, modelVersion: statistical.modelVersion };
  }

  const confidence = Math.min(0.98, Math.max(0.78, intent * 0.48 + candidate.confidence * 0.52));
  const decision: TaskDecision = {
    t: true,
    c: confidence,
    a: "create",
    ttl: candidate.title,
    d: candidate.description,
    as: assignee,
    due: deadline.iso,
    p: priority(text),
    tid: null,
    st: "",
    r: "Detected and canonicalized by Taskly's local multilingual engine.",
    l: lang,
  };
  return {
    route: "local_create",
    reason: "clear_task_and_canonicalization",
    languageHint: lang,
    intentConfidence: intent,
    canonicalConfidence: candidate.confidence,
    fallbackReason: "",
    decision,
    candidate,
    modelTaskProbability: modelTask,
    modelVersion: statistical.modelVersion,
  };
}
