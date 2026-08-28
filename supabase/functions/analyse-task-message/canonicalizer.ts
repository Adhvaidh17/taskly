import {
  ACTIONS,
  ARTICLE_WORDS,
  POLITE_WORDS,
  PURCHASE_NOUNS,
  RECIPIENT_WORDS,
  REQUEST_PREFIX,
  SELF_REMINDER,
  VOCATIVE_PREFIX,
  findAction,
  firstLexicalToken,
  normaliseText,
  sentenceCase,
} from "./language_pack.ts";
import { removeDeadlineText } from "./datetime_parser.ts";
import { normaliseLocalTaskPhrase } from "./local_phrase_normalizer.ts";
import type {
  CanonicalCandidate,
  CompactMember,
  DeadlineResult,
  FeedbackExample,
  LearnedAlias,
} from "./types.ts";

const AUXILIARY_PREFIX = /^(?:(?:i['’]?ll|i\s+will|we['’]?ll|we\s+will|let\s+me|i\s+am\s+going\s+to|you\s+should|you\s+must|need\s+to|have\s+to|remember\s+to|don['’]?t\s+forget\s+to|naan|na|main|hum)\s+)+/iu;
const TRAILING_FILLER = /\b(?:okay|ok|please|pls|plz|kindly|just|once|actually|maybe|bro|brother|buddy|mate|dude|boss|sir|madam|mam|da|di|ji|thanks|thank\s+you|seri|sari)\b/giu;
const GENERIC_STOP = new Set([
  "can", "could", "would", "will", "should", "need", "needs", "must", "have", "has", "do", "does",
  "did", "is", "are", "was", "were", "be", "been", "being", "just", "also", "then", "please", "kindly",
  "me", "my", "us", "our", "you", "your", "it", "this", "that", "bro", "da", "di", "ji",
]);
const ALL_ALIASES = ACTIONS.flatMap((action) => action.aliases).sort((a, b) => b.length - a.length);

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function stripMemberAddress(text: string, members: CompactMember[]): string {
  let result = text.replace(/^\s*@[\p{L}\p{N}_.-]+\s*[,!:\-]*\s*/u, "");
  const lower = result.toLocaleLowerCase();
  const matches: string[] = [];
  for (const member of members) {
    const full = member.name.trim().toLocaleLowerCase();
    const first = full.split(/\s+/u)[0] ?? full;
    for (const name of new Set([full, first])) {
      if (name && (lower.startsWith(`${name} `) || lower.startsWith(`${name},`) || lower.startsWith(`${name}:`))) matches.push(name);
    }
  }
  matches.sort((a, b) => b.length - a.length);
  if (matches[0]) result = result.slice(matches[0].length).replace(/^\s*[,!:\-]*\s*/u, "");
  return result;
}

function cleanRequestShell(text: string, members: CompactMember[]): string {
  let result = stripMemberAddress(normaliseText(text), members);
  for (let index = 0; index < 4; index += 1) {
    const before = result;
    result = result.replace(VOCATIVE_PREFIX, "").replace(REQUEST_PREFIX, "").replace(AUXILIARY_PREFIX, "").trim();
    if (result === before) break;
  }
  result = result.replace(SELF_REMINDER, "").replace(TRAILING_FILLER, " ");
  return result.replace(/\s+/g, " ").replace(/^[,;:!?.\-\s]+|[,;:!?.\-\s]+$/g, "").trim();
}

function sourceFromText(text: string): string {
  const match = /\bfrom\s+([\p{L}\p{N}][\p{L}\p{N} .'_-]{0,70}?)(?=\s+(?:to|for|at|by|before|after|today|tomorrow|aaj|kal|innaiku|nalaiku)\b|$)/iu.exec(text);
  return cleanObject(match?.[1] ?? "");
}

function hasRequesterRecipient(text: string): boolean {
  return /\b(?:me|for\s+me|to\s+me|my|us|for\s+us|enakku|ennaku|mujhe|mere\s+liye|எனக்கு|என்னை|मुझे)\b/iu.test(text);
}

function removePhraseOnce(text: string, phrase: string): string {
  if (!phrase) return text;
  const regex = new RegExp(`(^|[^\\p{L}\\p{N}])${escapeRegex(phrase).replace(/\\ /g, "\\s+")}(?=$|[^\\p{L}\\p{N}])`, "iu");
  return text.replace(regex, "$1 ");
}

function cleanObject(value: string): string {
  const tokens = value
    .replace(/\b(?:for|to)\s+(?:me|us|enakku|ennaku|mujhe|எனக்கு|மुझे)\b/giu, " ")
    .replace(/\b(?:me|my|us|our|enakku|ennaku|mujhe|எனக்கு|मुझे)\b/giu, " ")
    .replace(/\s+/g, " ")
    .replace(/^[,;:!?.\-\s]+|[,;:!?.\-\s]+$/g, "")
    .trim()
    .split(/\s+/u)
    .filter((token) => {
      const lower = token.toLocaleLowerCase().replace(/[^\p{L}\p{N}'_-]/gu, "");
      return lower && !ARTICLE_WORDS.has(lower) && !POLITE_WORDS.has(lower);
    });
  return tokens.join(" ").replace(/\s+/g, " ").trim();
}

function firstObjectToken(value: string): string {
  return value.toLocaleLowerCase().split(/[^\p{L}\p{N}]+/u).find((token) => token.length > 0) ?? "";
}


const DIGITAL_RETRIEVAL_NOUNS = /\b(?:file|document|report|invoice|attachment|photo|image|video|sheet|spreadsheet|presentation|pdf|data|backup|link|copy)\b/iu;
const APPROVAL_NOUNS = /\b(?:approval|permission|confirmation|consent|authorisation|authorization|quote|quotation|estimate|details|information|access)\b/iu;
const COMMUNICATION_ACTIONS = new Set(["send", "deliver", "message", "reply", "tell", "notify", "invite"]);
const PERSON_ACTIONS = new Set(["call", "follow_up", "meet", "ask", "coordinate"]);

function normaliseObjectGrammar(value: string, actionKey: string): string {
  let result = value
    .replace(/\b(?:enakku|ennaku|mujhe|mere\s+liye|எனக்கு|मुझे)\b/giu, " ")
    .replace(/\b(?:pannidu|pannunga|pannu|vechidu|vechu|vechuko|kar\s*do|karo|karna|dena|do)\b[.!?]*$/giu, " ")
    .replace(/\s+/g, " ")
    .trim();

  // Tamil/Hindi postpositions place the recipient before the object:
  // "client ku invoice" / "client ko invoice" -> "invoice to client".
  if (COMMUNICATION_ACTIONS.has(actionKey)) {
    const recipientFirst = /^(.{1,64}?)\s+(?:ku|kku|ko)\s+(.+)$/iu.exec(result);
    if (recipientFirst?.[1] && recipientFirst[2]) {
      result = `${recipientFirst[2]} to ${recipientFirst[1]}`;
    }
  }

  if (PERSON_ACTIONS.has(actionKey)) {
    result = result
      .replace(/^(.{1,80}?)\s+(?:kitta|kitte|kooda|se|ke\s+saath)$/iu, "$1")
      .replace(/^(?:with|to)\s+/iu, "");
  }

  if (actionKey === "pay") {
    result = result.replace(/^(?:for|of)\s+/iu, "");
  }
  if (actionKey === "print" || actionKey === "backup" || actionKey === "capture" || actionKey === "copy" || actionKey === "summarise") {
    result = result.replace(/^(?:of|for)\s+/iu, "");
  }
  if (actionKey === "call" || actionKey === "message" || actionKey === "meet" || actionKey === "visit") {
    result = result.replace(/^(?:to|with)\s+/iu, "");
  }

  // Common possessive/postposition endings that do not belong in a concise title.
  result = result
    .replace(/\b(?:ka|ki|ke)\s*$/iu, "")
    .replace(/\b(?:ku|kku|ko|kitta|kitte)\b(?=$)/giu, "")
    .replace(/\s+/g, " ")
    .trim();

  return cleanObject(result);
}

function restoreSemanticObject(actionKey: string, alias: string, remainder: string): string {
  const lowerAlias = alias.toLocaleLowerCase();
  let result = remainder;
  if (actionKey === "obtain" && /\bapproval\b/u.test(lowerAlias) && !/\bapproval\b/iu.test(result)) result = `approval ${result}`;
  if (actionKey === "obtain" && /\bpermission\b/u.test(lowerAlias) && !/\bpermission\b/iu.test(result)) result = `permission ${result}`;
  if (actionKey === "obtain" && /\bconfirmation\b/u.test(lowerAlias) && !/\bconfirmation\b/iu.test(result)) result = `confirmation ${result}`;
  if (actionKey === "schedule" && /\bmeeting\b/u.test(lowerAlias) && !/\bmeeting\b/iu.test(result)) result = `meeting ${result}`;
  if (actionKey === "capture" && /screen\s*shot/u.test(lowerAlias) && !/\bscreenshot\b/iu.test(result)) result = `screenshot ${result}`;
  return result.replace(/\s+/g, " ").trim();
}

function sourceLooksLikePerson(source: string, members: CompactMember[]): boolean {
  const lower = source.toLocaleLowerCase();
  if (members.some((member) => {
    const full = member.name.trim().toLocaleLowerCase();
    const first = full.split(/\s+/u)[0] ?? full;
    return lower === full || lower === first;
  })) return true;
  return /^(?:[A-Z][\p{L}'-]{1,30})(?:\s+[A-Z][\p{L}'-]{1,30})?$/u.test(source);
}

function sourceLooksLikeShop(source: string): boolean {
  return /\b(?:shop|store|supermarket|market|mart|pharmacy|bakery|mall|medical|grocery|kadai|angadi|dukaan|दुकान|கடை)\b/iu.test(source);
}

function sourceLooksDigital(source: string): boolean {
  return /\b(?:email|mail|drive|google\s+drive|website|site|portal|server|folder|link|whatsapp|slack|github|dropbox|cloud|dashboard|app)\b/iu.test(source);
}

function genericAction(text: string): { key: string; title: string; alias: string; confidence: number; start: number; end: number } | null {
  const first = firstLexicalToken(text);
  if (!first || first.length < 2 || GENERIC_STOP.has(first)) return null;
  const index = text.toLocaleLowerCase().indexOf(first.toLocaleLowerCase());
  return {
    key: first.toLocaleLowerCase(),
    title: sentenceCase(first),
    alias: first,
    confidence: /\p{Script=Latin}/u.test(first) ? 0.79 : 0.72,
    start: Math.max(0, index),
    end: Math.max(0, index) + first.length,
  };
}

function hasMultipleActions(text: string, firstAlias: string): boolean {
  const afterFirst = removePhraseOnce(text, firstAlias);
  if (!/\b(?:and|then|also|after\s+that|apram|appuram|aur|phir|மற்றும்|பிறகு|और|फिर)\b/iu.test(afterFirst)) return false;
  const connectorIndex = afterFirst.search(/\b(?:and|then|also|after\s+that|apram|appuram|aur|phir|மற்றும்|பிறகு|और|फिर)\b/iu);
  const tail = connectorIndex >= 0 ? afterFirst.slice(connectorIndex) : "";
  return ALL_ALIASES.some((alias) => new RegExp(`\\b${escapeRegex(alias).replace(/\\ /g, "\\s+")}\\b`, "iu").test(tail));
}

function sentenceTitle(actionTitle: string, object: string, source: string): string {
  let title = `${actionTitle}${object ? ` ${object}` : ""}`.replace(/\s+/g, " ").trim();
  if (source && !/\bfrom\b/iu.test(title)) title += ` from ${source}`;
  title = sentenceCase(title.replace(/^[,;:!?.\-\s]+|[,;:!?.\-\s]+$/g, "").trim());
  if (title.length > 90) title = `${title.slice(0, 87).trimEnd()}…`;
  return title;
}

function descriptionFor(
  title: string,
  actionKey: string,
  recipient: "" | "requester",
  deadline: DeadlineResult,
  requesterName: string,
): string {
  let description = title;
  if (recipient === "requester") {
    const requester = requesterName.trim() || "the requester";
    if (actionKey === "send" || actionKey === "message" || actionKey === "reply" || actionKey === "deliver" || actionKey === "notify") {
      description = `${title} to ${requester}`;
    } else if (actionKey === "call") {
      description = new RegExp(`${escapeRegex(requester)}$`, "iu").test(title) ? title : `${title} ${requester}`;
    } else {
      description = `${title} for ${requester}`;
    }
  }
  if (deadline.found) description += ` by ${deadline.human}`;
  description = description.replace(/\s+/g, " ").trim();
  if (!/[.!?]$/u.test(description)) description += ".";
  return description.slice(0, 260);
}

function feedbackAdjustment(examples: FeedbackExample[]): number {
  let adjustment = 0;
  for (const example of examples) {
    if (example.similarity < 0.72) continue;
    if (example.outcome === "accepted") adjustment += Math.min(0.05, example.similarity * 0.05);
    if (example.outcome === "rejected") adjustment -= Math.min(0.12, example.similarity * 0.12);
  }
  return Math.max(-0.16, Math.min(0.08, adjustment));
}

function wordOverlap(a: string, b: string): number {
  const aw = new Set(a.toLocaleLowerCase().split(/[^\p{L}\p{N}]+/u).filter((word) => word.length > 1));
  const bw = new Set(b.toLocaleLowerCase().split(/[^\p{L}\p{N}]+/u).filter((word) => word.length > 1));
  if (aw.size === 0 || bw.size === 0) return 0;
  let hits = 0;
  for (const word of aw) if (bw.has(word)) hits += 1;
  return hits / Math.max(aw.size, bw.size);
}

export function canonicalizeTask(
  rawText: string,
  members: CompactMember[],
  learnedAliases: LearnedAlias[],
  feedbackExamples: FeedbackExample[],
  deadline: DeadlineResult,
  requesterName = "the requester",
): CanonicalCandidate {
  const issues: string[] = [];
  const shellCleaned = cleanRequestShell(rawText, members);
  const requesterRecipient = hasRequesterRecipient(shellCleaned);
  const phraseNormalised = normaliseLocalTaskPhrase(shellCleaned);
  const withoutDeadline = removeDeadlineText(phraseNormalised.text, deadline);
  const action = findAction(withoutDeadline, learnedAliases) ?? genericAction(withoutDeadline);

  if (!action) {
    return {
      actionKey: "",
      actionTitle: "",
      object: "",
      source: "",
      recipient: "",
      title: "",
      description: "",
      confidence: 0.25,
      issues: ["action_not_resolved"],
    };
  }

  let actionKey = action.key;
  let actionTitle = action.title;
  const recipient = requesterRecipient ? "requester" as const : "" as const;
  const source = sourceFromText(withoutDeadline);

  let remainder = `${withoutDeadline.slice(0, action.start)} ${withoutDeadline.slice(action.end)}`.trim();
  if (source) remainder = remainder.replace(new RegExp(`\\bfrom\\s+${escapeRegex(source)}\\b`, "iu"), " ");
  remainder = normaliseObjectGrammar(remainder, actionKey);
  remainder = restoreSemanticObject(actionKey, action.alias, remainder);

  if (actionKey === "get") {
    const purchasable = PURCHASE_NOUNS.has(firstObjectToken(remainder));
    if (source && purchasable && sourceLooksLikeShop(source)) {
      actionKey = "buy";
      actionTitle = "Buy";
    } else if (source && sourceLooksLikePerson(source, members)) {
      actionKey = "collect";
      actionTitle = "Collect";
    } else if (source && sourceLooksDigital(source) && DIGITAL_RETRIEVAL_NOUNS.test(remainder)) {
      actionKey = "download";
      actionTitle = "Download";
    } else if (APPROVAL_NOUNS.test(remainder)) {
      actionKey = "obtain";
      actionTitle = "Obtain";
    } else if (source) {
      issues.push("ambiguous_get_source");
    } else if (purchasable) {
      actionKey = "buy";
      actionTitle = "Buy";
    } else {
      issues.push("ambiguous_get_action");
    }
  }

  remainder = normaliseObjectGrammar(remainder, actionKey);

  if (actionKey === "call" && !remainder && recipient === "requester") remainder = requesterName;
  if ((actionKey === "follow_up" || actionKey === "reply") && /^(?:with|to)\s+/iu.test(remainder)) {
    remainder = remainder.replace(/^(?:with|to)\s+/iu, "");
  }

  if (!remainder && actionKey !== "call") issues.push("task_object_missing");
  if (hasMultipleActions(withoutDeadline, action.alias)) issues.push("multiple_actions");
  if (withoutDeadline.length > 300) issues.push("long_complex_message");

  const title = sentenceTitle(actionTitle, remainder, source);
  const description = descriptionFor(title, actionKey, recipient, deadline, requesterName);

  let confidence = action.confidence + phraseNormalised.confidenceBoost;
  if (remainder.length >= 2) confidence += 0.03;
  else confidence -= 0.20;
  if (source && actionKey === "collect") confidence += 0.04;
  if (deadline.found) confidence = Math.min(confidence, deadline.confidence + 0.06);
  confidence += feedbackAdjustment(feedbackExamples);
  if (issues.some((issue) => issue.startsWith("ambiguous_get"))) confidence = Math.min(confidence, 0.58);
  if (issues.includes("multiple_actions")) confidence = Math.min(confidence, 0.60);
  if (issues.includes("long_complex_message")) confidence = Math.min(confidence, 0.66);
  if (issues.includes("task_object_missing")) confidence = Math.min(confidence, 0.48);

  if (!title || title.length < 3) {
    issues.push("invalid_title");
    confidence = Math.min(confidence, 0.35);
  }
  if (/\b(?:please|pls|plz|kindly|today|tomorrow|nalaiku|aaj|kal|manikku|baje)\b/iu.test(title)) {
    issues.push("title_contains_request_noise");
    confidence = Math.min(confidence, 0.62);
  }
  if (shellCleaned.split(/\s+/u).length >= 7 && wordOverlap(title, shellCleaned) > 0.88) {
    issues.push("title_too_close_to_message");
    confidence = Math.min(confidence, 0.70);
  }

  return {
    actionKey,
    actionTitle,
    object: remainder,
    source,
    recipient,
    title,
    description,
    confidence: Math.max(0, Math.min(0.99, confidence)),
    issues: [...new Set(issues)],
  };
}
