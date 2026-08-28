import type { CanonicalCandidate, DeadlineResult, TaskDecision } from "./types.ts";

const TEMPORAL_WORDS = /\b(?:today|tomorrow|tonight|yesterday|now|later|morning|afternoon|evening|night|noon|midnight|eod|end\s+of\s+day|tmr|tmrw|tdy|aaj|kal|parso|subah|shaam|raat|baje|nalaiku|naalaiku|innaiku|indru|naalai|manikku|kaalai|maalai|iravu|இன்று|நாளை|காலை|மாலை|இரவு|आज|कल|परसों|सुबह|शाम|रात|बजे)\b/giu;
const WEEKDAY_MONTH = /\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b/giu;
const NUMERIC_DATE = /\b(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}(?:[-/.]\d{2,4})?)\b/gu;
const CLOCK_TIME = /\b(?:[01]?\d|2[0-3])(?:(?::[0-5]\d)\s*(?:a\.?m\.?|p\.?m\.?)?|\s*(?:a\.?m\.?|p\.?m\.?))\b/giu;
const TIME_WITH_MARKER = /\b(?:at|by|before|after|on|around|within|till|until)\s+(?:(?:[01]?\d|2[0-3])(?::[0-5]\d)?\s*(?:a\.?m\.?|p\.?m\.?)?|today|tomorrow|tonight|morning|afternoon|evening|night|noon|midnight|eod|aaj|kal|subah|shaam|raat|nalaiku|naalaiku|innaiku|manikku|baje|இன்று|நாளை|காலை|மாலை|இரவு|आज|कल|सुबह|शाम|रात)(?:\s+at\s+(?:[01]?\d|2[0-3])(?::[0-5]\d)?\s*(?:a\.?m\.?|p\.?m\.?)?)?/giu;
const LEADING_TRAILING_JOINERS = /^(?:at|by|before|after|on|for|to|from|and|then|please|pls|plz|kindly|hey|hi|bro|brother|machi|machan|da|di|ji|anna|akka)\b|\b(?:at|by|before|after|on|and|then|please|pls|plz|kindly)$/giu;
const DATE_TIME_ONLY = /^(?:(?:at|by|before|after|on|for)\s+)*(?:(?:today|tomorrow|tonight|morning|afternoon|evening|night|noon|midnight|eod|aaj|kal|subah|shaam|raat|baje|nalaiku|naalaiku|innaiku|manikku|இன்று|நாளை|காலை|மாலை|இரவு|आज|कल|सुबह|शाम|रात|monday|tuesday|wednesday|thursday|friday|saturday|sunday|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|\d{1,4}[-/.:]\d{1,2}(?:[-/.:]\d{1,4})?|\d{1,2}\s*(?:am|pm))\s*)+$/iu;
const REQUEST_NOISE = /\b(?:please|pls|plz|kindly|can\s+you|could\s+you|would\s+you|will\s+you|hey|hi|hello|bro|brother|machi|machan|anna|akka|da|di|ji)\b/giu;

function normaliseSpaces(value: string): string {
  return value
    .replace(/[\u200B-\u200D\uFEFF]/gu, "")
    .replace(/\s+/gu, " ")
    .replace(/^[,;:!?.\-–—\s]+|[,;:!?.\-–—\s]+$/gu, "")
    .trim();
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function removeTemporalTitleNoise(value: string, deadline?: DeadlineResult | null): string {
  let result = value;
  if (deadline) {
    for (const matched of deadline.matched) {
      const phrase = normaliseSpaces(matched);
      if (!phrase) continue;
      result = result.replace(new RegExp(`(^|[^\\p{L}\\p{N}])${escapeRegex(phrase).replace(/\\ /g, "\\s+")}(?=$|[^\\p{L}\\p{N}])`, "giu"), "$1 ");
    }
  }
  result = result
    .replace(TIME_WITH_MARKER, " ")
    .replace(NUMERIC_DATE, " ")
    .replace(WEEKDAY_MONTH, " ")
    .replace(TEMPORAL_WORDS, " ")
    .replace(CLOCK_TIME, " ")
    .replace(REQUEST_NOISE, " ");
  for (let i = 0; i < 3; i += 1) {
    const before = result;
    result = result.replace(LEADING_TRAILING_JOINERS, " ");
    if (before === result) break;
  }
  return normaliseSpaces(result);
}

export function isUnsafeTaskTitle(value: string): boolean {
  const title = normaliseSpaces(value);
  if (title.length < 3) return true;
  if (DATE_TIME_ONLY.test(title)) return true;
  const lexical = title.match(/[\p{L}\p{N}]+/gu) ?? [];
  if (lexical.length === 0) return true;
  const temporalStripped = removeTemporalTitleNoise(title);
  if (temporalStripped.length < 3) return true;
  return false;
}

function sentenceCase(value: string): string {
  const clean = normaliseSpaces(value);
  if (!clean) return "";
  return `${clean.charAt(0).toLocaleUpperCase()}${clean.slice(1)}`;
}

function safeCandidateTitle(candidate?: CanonicalCandidate | null, deadline?: DeadlineResult | null): string {
  if (!candidate?.title) return "";
  const clean = sentenceCase(removeTemporalTitleNoise(candidate.title, deadline));
  return isUnsafeTaskTitle(clean) ? "" : clean.slice(0, 90);
}

function descriptionFromTitle(title: string, candidate?: CanonicalCandidate | null, deadline?: DeadlineResult | null): string {
  let description = candidate?.description?.trim() ?? "";
  if (!description || isUnsafeTaskTitle(removeTemporalTitleNoise(description, deadline))) {
    description = title;
  }
  if (deadline?.found && deadline.human && !description.toLocaleLowerCase().includes(deadline.human.toLocaleLowerCase())) {
    description = `${description.replace(/[.!?]+$/u, "")} by ${deadline.human}`;
  }
  description = normaliseSpaces(description);
  if (description && !/[.!?]$/u.test(description)) description += ".";
  return description.slice(0, 260);
}

export function guardTaskDecision(
  decision: TaskDecision,
  originalMessage: string,
  candidate?: CanonicalCandidate | null,
  deadline?: DeadlineResult | null,
): TaskDecision {
  const output = { ...decision };
  if (!output.t || output.a !== "create") return output;

  const modelTitle = sentenceCase(removeTemporalTitleNoise(output.ttl, deadline));
  const fallbackTitle = safeCandidateTitle(candidate, deadline);
  output.ttl = !isUnsafeTaskTitle(modelTitle) ? modelTitle.slice(0, 90) : fallbackTitle;

  // A title that is only a date/time is never allowed to become a suggestion.
  if (!output.ttl || isUnsafeTaskTitle(output.ttl)) {
    output.t = false;
    output.a = "none";
    output.ttl = "";
    output.d = "";
    output.as = null;
    output.due = "";
    output.tid = null;
    output.st = "";
    output.c = Math.min(output.c, 0.42);
    output.r = "Task meaning was plausible, but a safe action title could not be produced.";
    return output;
  }

  const compactOriginal = normaliseSpaces(originalMessage).toLocaleLowerCase();
  const compactDescription = normaliseSpaces(output.d).toLocaleLowerCase();
  const copiedWholeMessage = compactOriginal.length >= 18 && compactDescription === compactOriginal;
  if (!output.d || copiedWholeMessage) {
    output.d = descriptionFromTitle(output.ttl, candidate, deadline);
  } else {
    output.d = normaliseSpaces(output.d).slice(0, 260);
    if (output.d && !/[.!?]$/u.test(output.d)) output.d += ".";
  }

  if ((!output.d || isUnsafeTaskTitle(removeTemporalTitleNoise(output.d, deadline))) && output.ttl) {
    output.d = descriptionFromTitle(output.ttl, candidate, deadline);
  }
  if ((!output.due || !/^\d{4}-\d{2}-\d{2}T/iu.test(output.due)) && deadline?.found) {
    output.due = deadline.iso;
  }
  return output;
}
