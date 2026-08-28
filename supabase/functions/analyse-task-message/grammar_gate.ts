export type GateRoute = "local_skip" | "local_grammar" | "nano" | "mini";

export interface CompactMember {
  id: number;
  name: string;
  role?: string | null;
}

export interface CompactTask {
  id: number;
  title: string;
  status?: string | null;
  assignee_id?: number | null;
  deadline?: string | null;
}

export interface GateContext {
  profileId: number;
  workspaceKind: string;
  directKey?: string | null;
  members: CompactMember[];
  mentionedProfileIds: number[];
  openTasks: CompactTask[];
}

export interface LocalDecision {
  t: boolean;
  c: number;
  a: "none" | "create" | "update" | "status_change";
  ttl: string;
  d: string;
  as: number | null;
  due: string;
  p: "low" | "medium" | "high";
  tid: number | null;
  st: "" | "todo" | "in-progress" | "done";
  r: string;
  l: string;
}

export interface GateResult {
  route: GateRoute;
  score: number;
  reason: string;
  languageHint: string;
  localDecision?: LocalDecision;
}

const GREETING_ONLY = /^(?:h+i+|h+e+y+|hello+|hola|vanakkam+|namaste+|good\s*(?:morning|afternoon|evening|night)|gm+|ga+|ge+|gn+|yo+|dei+|bro+|sis+|mach[ai]+|machi+|anna+|akka+|arey+|oye+)[\s!?.…]*$/iu;
const ACK_ONLY = /^(?:ok(?:ay)?|kk+|k+|sure+|fine+|done+|noted+|got\s*it|understood+|super+|nice+|great+|awesome+|perfect+|thanks?(?:\s*you)?|thanku+|thx+|ty+|seri+|sari+|aama+|ama+|haan+|ha+|ji+|acha+|accha+|theek+|thik+|cool+|👍+|👌+|🙏+|✅+|😂+|❤️+|❤+)[\s!?.…]*$/iu;
const QUESTION_START = /^(?:what|why|when|where|who|which|how|is|are|am|was|were|do|does|did|can|could|would|will|should|have|has|had|enna|yen|eppo|enga|yaar|epdi|epadi|kya|kyu|kyun|kab|kahan|kaun|kaise|क्या|क्यों|कब|कहाँ|कौन|कैसे)\b/iu;
const PAST_COMPLETION = /\b(?:i\s+(?:already\s+)?(?:did|sent|finished|completed|called|submitted|shared|uploaded|updated)|we\s+(?:already\s+)?(?:did|sent|finished|completed|submitted)|naan\s+(?:already\s+)?(?:panniten|senjiten|mudichiten|anuppiten|anupiten)|na\s+(?:panniten|mudichiten|anupiten)|maine\s+(?:kar\s*diya|bhej\s*diya|complete\s*kar\s*diya)|ho\s*gaya|mudinjiduchu|mudichachu)\b/iu;
const FUTURE_COMMITMENT = /\b(?:i['’]?ll|i\s+will|we['’]?ll|we\s+will|let\s+me|i\s+am\s+going\s+to|i\s+can\s+finish|naan\s+(?:panren|pannuren|seiren|mudikren|anupren|anupuren)|na\s+(?:panren|mudikren|anupren)|main\s+(?:karunga|karungi|bhejunga|bhejungi|complete\s+karunga)|hum\s+(?:karenge|bhejenge))\b/iu;
const REQUEST_FRAME = /\b(?:please|pls|plz|kindly|can\s+you|could\s+you|would\s+you|will\s+you|need\s+you\s+to|you\s+(?:need|have)\s+to|you\s+must|make\s+sure|don['’]?t\s+forget|remember\s+to|remind\s+me|rember\s+me|remndr\s+me|nyabagam|gnabagam|ninaivu|yaad\s+dila|kripya|zara|konjam|pleaseu?)\b/iu;
const DIRECTIVE_VERB = /\b(?:send|share|submit|call|email|mail|upload|download|prepare|create|make|design|write|check|review|verify|confirm|collect|bring|get|go|come|meet|attend|visit|take|print|scan|sign|fill|return|handover|hand\s*over|finish|complete|update|change|fix|schedule|book|pay|buy|order|follow\s*up|followup|reply|respond|remind|notify|tell|ask|deliver|approve|reject|close|start|stop|assign|move|mark|anupu|anuppu|anupidu|anupunga|pannu|pannidu|pannunga|seyyu|seiyu|senjidu|mudichidu|mudinga|konduva|eduthu\s+va|call\s+pannu|check\s+pannu|bhej|bhejo|bhejna|bhej\s+dena|kar|karo|karna|kar\s+dena|de|do|dena|bata|batao|bata\s+dena|jama\s+kar|le\s+aao|banado|banao|likho|dekho|check\s+karo)\b/iu;
const IMPERATIVE_SUFFIX = /\b[\p{L}]{2,}(?:idu|unga|inga|anum|anumnga|dena|do|karo|na)\b/iu;
const DATE_TIME = /\b(?:today|tomorrow|tonight|this\s+(?:morning|afternoon|evening|week)|next\s+(?:week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|before\s+(?:lunch|eod|end\s+of\s+day)|by\s+(?:eod|noon|midnight)|at\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?|\d{1,2}(?::\d{2})?\s*(?:am|pm)|innaiku|indru|nalaiku|naalaiku|marunaal|kaalai|malai|saayankaalam|raathiri|manikku|mani|aaj|kal|parso|subah|shaam|raat|baje|आज|कल|परसों|सुबह|शाम|रात|बजे)\b/iu;
const UPDATE_STATUS = /\b(?:mark|set|change|move|update|close|reopen|complete|completed|done|finish|finished|in\s*progress|started|cancel|cancelled|hold|blocked|status|priority|deadline|due\s*date|assignee|assign|mudichiten|mudichachu|start\s+panniten|complete\s+kar\s*diya|ho\s*gaya)\b/iu;
const STATUS_TARGET = /\b(?:todo|to\s*do|in\s*progress|doing|done|completed|complete|closed|cancelled|canceled|blocked|hold|pending)\b/iu;
const URGENCY = /\b(?:urgent|urgently|asap|immediately|right\s+now|high\s+priority|romba\s+urgent|seekiram|jaldi|turant)\b/iu;
const SELF_REMINDER = /\b(?:remind\s+me|rember\s+me|remndr\s+me|don['’]?t\s+let\s+me\s+forget|nyabagam\s+paduthu|gnabagam\s+paduthu|yaad\s+dila)\b/iu;
const ACTION_NOUN = /\b(?:report|invoice|quotation|quote|design|creative|file|document|assignment|payment|meeting|call|email|mail|message|reply|order|task|work|video|photo|image|poster|content|caption|copy|website|app|apk|build|code|ticket|issue|bug|client|customer|lead|campaign|ad|ads|budget|proposal|presentation|deck)\b/iu;

function normalise(value: string): string {
  return value
    .normalize("NFKC")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/https?:\/\/\S+/giu, " URL ")
    .replace(/\s+/g, " ")
    .trim();
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function isOnlyNoise(text: string): boolean {
  if (!text) return true;
  const withoutMentions = text.replace(/@[^\s]+/gu, "");
  const withoutUrls = withoutMentions.replace(/\bURL\b/giu, "");
  const withoutNoise = withoutUrls.replace(/[\p{P}\p{S}\p{N}\s_]/gu, "");
  return withoutNoise.length === 0;
}

function languageHint(text: string): string {
  if (/\p{Script=Tamil}/u.test(text)) return "ta";
  if (/\p{Script=Devanagari}/u.test(text)) return "hi";
  if (/\b(?:nalaiku|innaiku|manikku|pannu|anupu|mudich|konjam|seri|naan|na)\b/iu.test(text)) return "ta-Latn";
  if (/\b(?:kal|aaj|baje|bhej|karo|dena|yaad|jaldi|main|maine)\b/iu.test(text)) return "hi-Latn";
  return "und";
}

function memberFromMentionText(text: string, members: CompactMember[]): number | null {
  const lower = text.toLocaleLowerCase();
  const matches = members.filter((member) => {
    const name = member.name.trim().toLocaleLowerCase();
    if (!name) return false;
    return lower.includes(`@${name}`) || lower.includes(`@${name.replace(/\s+/g, "")}`);
  });
  return matches.length === 1 ? matches[0]!.id : null;
}


function memberNamedAtStart(text: string, members: CompactMember[]): number | null {
  const lower = text.toLocaleLowerCase().trimStart();
  const ids: number[] = [];
  const statementStart = /^(?:is|are|was|were|has|have|had|went|came|said|told|finished|completed|sent|shared|did|does|looks|seems|will\s+be)\b/iu;

  for (const member of members) {
    const name = member.name.trim().toLocaleLowerCase();
    if (!name) continue;
    const first = name.split(/\s+/u)[0] ?? name;
    for (const prefix of new Set([name, first])) {
      if (lower.startsWith(`${prefix},`)) {
        ids.push(member.id);
        break;
      }
      if (lower.startsWith(`${prefix} `)) {
        const rest = lower.slice(prefix.length).trimStart();
        if (rest && !statementStart.test(rest)) ids.push(member.id);
        break;
      }
    }
  }

  const unique = [...new Set(ids)];
  return unique.length === 1 ? unique[0]! : null;
}

function inferredAssignee(text: string, context: GateContext): number | null {
  const explicitIds = [...new Set(context.mentionedProfileIds.filter(Number.isFinite))];
  if (explicitIds.length === 1) return explicitIds[0]!;
  const byText = memberFromMentionText(text, context.members);
  if (byText !== null) return byText;
  const byName = memberNamedAtStart(text, context.members);
  if (byName !== null) return byName;

  const isSelf = context.workspaceKind === "direct" && context.directKey === `self:${context.profileId}`;
  if (isSelf) return context.profileId;

  if (context.workspaceKind === "direct") {
    const others = context.members.filter((member) => member.id !== context.profileId);
    if (others.length === 1) return others[0]!.id;
  }
  return null;
}

function stripRequestPrefix(text: string): string {
  return text
    .replace(/^\s*@[^\s]+\s*/u, "")
    .replace(/^\s*(?:please|pls|plz|kindly|can\s+you|could\s+you|would\s+you|will\s+you|need\s+you\s+to|konjam|zara|kripya)\s+/iu, "")
    .replace(/^\s*(?:hey|hi|hello|dei|bro|machi|anna|akka|arey|oye)\s*[,!-]*\s*/iu, "")
    .trim();
}

function titleFromText(text: string): string {
  let title = stripRequestPrefix(text)
    .replace(/\b(?:please|pls|plz|kindly)\b/giu, "")
    .replace(/\b(?:today|tomorrow|tonight|innaiku|nalaiku|naalaiku|aaj|kal|parso)\b.*$/iu, "")
    .replace(/\b(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm|baje|manikku|mani)\b.*$/iu, "")
    .replace(/\s+/g, " ")
    .replace(/^[,;:!?.\-\s]+|[,;:!?.\-\s]+$/g, "")
    .trim();

  if (title.length < 3) title = stripRequestPrefix(text).trim();
  if (title.length > 180) title = `${title.slice(0, 177).trimEnd()}…`;
  return title;
}

function priorityFromText(text: string): "low" | "medium" | "high" {
  if (URGENCY.test(text)) return "high";
  if (/\b(?:low\s+priority|whenever|no\s+rush|time\s+irundha|free\s+ah\s+irundha)\b/iu.test(text)) return "low";
  return "medium";
}

function matchOpenTask(text: string, tasks: CompactTask[]): CompactTask | null {
  if (tasks.length === 0) return null;
  const lower = text.toLocaleLowerCase();
  let best: CompactTask | null = null;
  let bestScore = 0;

  for (const task of tasks) {
    const words = task.title
      .toLocaleLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter((word) => word.length >= 3);
    if (words.length === 0) continue;
    const hits = words.filter((word) => lower.includes(word)).length;
    const score = hits / Math.min(words.length, 4);
    if (score > bestScore) {
      bestScore = score;
      best = task;
    }
  }
  return bestScore >= 0.5 ? best : null;
}

function statusFromText(text: string): "" | "todo" | "in-progress" | "done" {
  if (/\b(?:done|completed|complete|finished|closed|mudichachu|mudichiten|ho\s*gaya|complete\s+kar\s*diya)\b/iu.test(text)) return "done";
  if (/\b(?:in\s*progress|doing|started|start\s+panniten|working\s+on)\b/iu.test(text)) return "in-progress";
  if (/\b(?:todo|to\s*do|pending|reopen|open)\b/iu.test(text)) return "todo";
  return "";
}

export function evaluateGrammarGate(rawText: string, context: GateContext): GateResult {
  const text = normalise(rawText);
  const lang = languageHint(text);

  if (!text || text.length < 2 || isOnlyNoise(text)) {
    return { route: "local_skip", score: 0, reason: "empty_or_non_text", languageHint: lang };
  }
  if (GREETING_ONLY.test(text) || ACK_ONLY.test(text)) {
    return { route: "local_skip", score: 0.02, reason: "greeting_or_acknowledgement", languageHint: lang };
  }
  if (/^(?:URL\s*)+$/iu.test(text)) {
    return { route: "local_skip", score: 0.01, reason: "link_only", languageHint: lang };
  }

  const hasRequestFrame = REQUEST_FRAME.test(text);
  const hasDirective = DIRECTIVE_VERB.test(text) || IMPERATIVE_SUFFIX.test(text);
  const hasCommitment = FUTURE_COMMITMENT.test(text);
  const hasTime = DATE_TIME.test(text);
  const hasUpdate = UPDATE_STATUS.test(text);
  const hasStatus = STATUS_TARGET.test(text);
  const hasActionNoun = ACTION_NOUN.test(text);
  const namedAddressee = memberNamedAtStart(text, context.members);
  const hasMention = context.mentionedProfileIds.length > 0
    || /@[\p{L}\p{N}_-]+/u.test(text)
    || namedAddressee !== null;
  const isQuestion = text.endsWith("?") || QUESTION_START.test(text);
  const isPast = PAST_COMPLETION.test(text);
  const selfReminder = SELF_REMINDER.test(text);
  const targetTask = matchOpenTask(text, context.openTasks);

  if (isPast && !hasRequestFrame && !(hasUpdate && targetTask)) {
    return { route: "local_skip", score: 0.08, reason: "past_statement", languageHint: lang };
  }

  if (isQuestion && !hasRequestFrame && !hasCommitment && !selfReminder) {
    if (hasUpdate && targetTask) {
      return { route: "mini", score: 0.58, reason: "question_about_existing_task", languageHint: lang };
    }
    return { route: "local_skip", score: 0.12, reason: "information_question", languageHint: lang };
  }

  let score = 0;
  if (hasDirective) score += 0.34;
  if (hasRequestFrame) score += 0.24;
  if (hasCommitment) score += 0.34;
  if (hasMention) score += 0.14;
  if (hasTime) score += 0.14;
  if (hasActionNoun) score += 0.10;
  if (selfReminder) score += 0.28;
  if (hasUpdate && targetTask) score += 0.24;
  if (text.length >= 10) score += 0.04;
  if (isQuestion) score -= 0.12;
  score = clamp01(score);

  if (hasUpdate && (targetTask || hasStatus) && (hasDirective || hasRequestFrame || isPast)) {
    return { route: "mini", score: Math.max(score, 0.64), reason: "existing_task_update_or_status", languageHint: lang };
  }

  const wordCount = text.split(/\s+/u).filter(Boolean).length;
  const candidateFloor = hasRequestFrame ? 0.20 : (hasMention ? 0.16 : 0.30);
  if (score < candidateFloor
      || (!hasDirective && !hasCommitment && !selfReminder && !hasRequestFrame && !hasMention)
      || ((hasRequestFrame || hasMention) && wordCount < 2)) {
    return { route: "local_skip", score, reason: "no_task_grammar", languageHint: lang };
  }

  const assignee = hasCommitment && !hasRequestFrame
    ? context.profileId
    : inferredAssignee(text, context);
  const clearDirective = hasDirective && (hasActionNoun || hasMention || hasRequestFrame);
  const needsModel = hasTime
    || selfReminder
    || assignee === null
    || text.length > 260
    || (clearDirective ? score < 0.45 : score < 0.70);
  if (needsModel) {
    return { route: "nano", score, reason: hasTime ? "date_or_time_interpretation" : "ambiguous_task_structure", languageHint: lang };
  }

  const title = titleFromText(text);
  if (title.length < 3) {
    return { route: "nano", score, reason: "title_requires_interpretation", languageHint: lang };
  }

  return {
    route: "local_grammar",
    score,
    reason: "clear_structural_task",
    languageHint: lang,
    localDecision: {
      t: true,
      c: Math.max(0.76, score),
      a: "create",
      ttl: title,
      d: "",
      as: assignee,
      due: "",
      p: priorityFromText(text),
      tid: null,
      st: "",
      r: "Detected by Taskly's local multilingual grammar gate.",
      l: lang,
    },
  };
}
