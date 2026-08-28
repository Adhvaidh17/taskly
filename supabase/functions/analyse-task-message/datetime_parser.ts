import type { DeadlineResult } from "./types.ts";
import { normaliseText } from "./language_pack.ts";

interface LocalParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
}

const DAY_MS = 86_400_000;
const WEEKDAYS: Record<string, number> = {
  sunday: 0, sun: 0, ஞாயிறு: 0, ravivar: 0, रविवार: 0,
  monday: 1, mon: 1, திங்கள்: 1, somvar: 1, सोमवार: 1,
  tuesday: 2, tue: 2, செவ்வாய்: 2, mangalvar: 2, मंगलवार: 2,
  wednesday: 3, wed: 3, புதன்: 3, budhvar: 3, बुधवार: 3,
  thursday: 4, thu: 4, வியாழன்: 4, guruwar: 4, गुरुवार: 4,
  friday: 5, fri: 5, வெள்ளி: 5, shukravar: 5, शुक्रवार: 5,
  saturday: 6, sat: 6, சனி: 6, shanivar: 6, शनिवार: 6,
};

const MONTHS: Record<string, number> = {
  january: 1, jan: 1, february: 2, feb: 2, march: 3, mar: 3, april: 4, apr: 4,
  may: 5, june: 6, jun: 6, july: 7, jul: 7, august: 8, aug: 8, september: 9, sep: 9,
  october: 10, oct: 10, november: 11, nov: 11, december: 12, dec: 12,
};

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

function offsetText(minutes: number): string {
  const sign = minutes >= 0 ? "+" : "-";
  const abs = Math.abs(minutes);
  return `${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)}`;
}

function localParts(date: Date, offsetMinutes: number): LocalParts {
  const shifted = new Date(date.getTime() + offsetMinutes * 60_000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
  };
}

function dateFromLocal(parts: LocalParts): Date {
  return new Date(Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, 0, 0));
}

function addLocalDays(parts: LocalParts, days: number): LocalParts {
  const result = new Date(dateFromLocal(parts).getTime() + days * DAY_MS);
  return {
    year: result.getUTCFullYear(),
    month: result.getUTCMonth() + 1,
    day: result.getUTCDate(),
    hour: parts.hour,
    minute: parts.minute,
  };
}

function validDate(year: number, month: number, day: number): boolean {
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() + 1 === month && date.getUTCDate() === day;
}

function formatIso(parts: LocalParts, offsetMinutes: number): string {
  return `${parts.year}-${pad2(parts.month)}-${pad2(parts.day)}T${pad2(parts.hour)}:${pad2(parts.minute)}:00${offsetText(offsetMinutes)}`;
}

function formatTime(hour: number, minute: number): string {
  const suffix = hour >= 12 ? "PM" : "AM";
  const displayHour = hour % 12 || 12;
  return `${displayHour}:${pad2(minute)} ${suffix}`;
}

function monthName(month: number): string {
  return ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"][month] ?? "";
}

function inferBareHour(hour: number, cue: string): { hour: number; confidence: number } {
  if (/\b(?:morning|kaalai|subah|காலை|सुबह)\b/iu.test(cue)) return { hour: hour % 12, confidence: 0.95 };
  if (/\b(?:afternoon|evening|night|malai|maalai|saayankaalam|raathiri|shaam|raat|மாலை|இரவு|शाम|रात)\b/iu.test(cue)) {
    return { hour: hour < 12 ? hour + 12 : hour, confidence: 0.95 };
  }
  if (hour >= 1 && hour <= 7) return { hour: hour + 12, confidence: 0.84 };
  if (hour >= 8 && hour <= 11) return { hour, confidence: 0.82 };
  return { hour, confidence: 0.88 };
}

function findTime(text: string, defaultHour: number): { found: boolean; hour: number; minute: number; confidence: number; matched: string[] } {
  const matched: string[] = [];
  // A bare number is not normally treated as a time. This avoids reading
  // quantities, calendar dates and task IDs as clock times. Bare hours are
  // accepted only directly after a relative-day phrase such as “tomorrow 8”.
  const timeMarker = "am|pm|a\\.m\\.|p\\.m\\.|manikku|mani|baje|மணிக்கு|மணி|बजे";
  const prefixed = new RegExp(
    `(?<![\\p{L}\\p{N}])(?:at|by|around|before)\\s+(\\d{1,2})(?::(\\d{2}))?\\s*(${timeMarker})?(?=$|[^\\p{L}\\p{N}/-])`,
    "iu",
  ).exec(text);
  const marked = new RegExp(
    `(?<![\\p{L}\\p{N}])(\\d{1,2})(?::(\\d{2}))?\\s*(${timeMarker})(?=$|[^\\p{L}\\p{N}])`,
    "iu",
  ).exec(text);
  const relativeBare = /(?:day\s+after\s+tomorrow|tomorrow|tmrw|tmr|today|tdy|nalaiku|naalaiku|innaiku|indru|aaj|kal|parso|நாளை\s+மறுநாள்|நாளை|இன்று|परसों|कल|आज)\s+(\d{1,2})(?::(\d{2}))?(?=$|[^\p{L}\p{N}/-])/iu.exec(text);
  const explicit = prefixed ?? marked ?? relativeBare;
  if (explicit) {
    let hour = Number(explicit[1]);
    const minute = Number(explicit[2] ?? 0);
    const marker = (explicit[3] ?? "").toLocaleLowerCase();
    if (hour <= 24 && minute <= 59) {
      let confidence = 0.96;
      if (/^p/.test(marker) && hour < 12) hour += 12;
      else if (/^a/.test(marker) && hour === 12) hour = 0;
      else if (marker && !/^(?:am|pm|a\.m\.|p\.m\.)$/iu.test(marker)) {
        const inferred = inferBareHour(hour, text);
        hour = inferred.hour;
        confidence = inferred.confidence;
      } else if (!marker) {
        const inferred = inferBareHour(hour, text);
        hour = inferred.hour;
        confidence = inferred.confidence;
      }
      if (hour <= 23) {
        matched.push(explicit[0]);
        return { found: true, hour, minute, confidence, matched };
      }
    }
  }

  const namedTimes: Array<[RegExp, number, number, number]> = [
    [/\b(?:noon|midday|மதியம்|dopahar|दोपहर)\b/iu, 12, 0, 0.96],
    [/\b(?:midnight|நள்ளிரவு|aadhi\s+raat|आधी\s+रात)\b/iu, 23, 59, 0.94],
    [/\b(?:before\s+lunch|lunch\s+time|மதிய\s+உணவுக்கு\s+முன்)\b/iu, 13, 0, 0.90],
    [/\b(?:eod|end\s+of\s+day|day\s+end|வேலை\s+முடிவதற்குள்)\b/iu, 18, 0, 0.94],
    [/\b(?:morning|kaalai|subah|காலை|सुबह)\b/iu, 9, 0, 0.84],
    [/\b(?:afternoon|மதியம்|dopahar|दोपहर)\b/iu, 15, 0, 0.84],
    [/\b(?:evening|malai|maalai|shaam|மாலை|शाम)\b/iu, 18, 0, 0.84],
    [/\b(?:tonight|night|raathiri|raat|இரவு|रात)\b/iu, 20, 0, 0.86],
  ];
  for (const [regex, hour, minute, confidence] of namedTimes) {
    const match = regex.exec(text);
    if (match) return { found: true, hour, minute, confidence, matched: [match[0]] };
  }
  return { found: false, hour: defaultHour, minute: 0, confidence: 0, matched };
}

export function parseDeadline(rawText: string, createdAt: string, timezoneOffsetMinutes: number, defaultDueHour = 18): DeadlineResult {
  const text = normaliseText(rawText);
  const baseDate = new Date(createdAt);
  if (!Number.isFinite(baseDate.getTime())) {
    return { found: false, iso: "", human: "", confidence: 0, matched: [], dateKind: "invalid_message_time" };
  }

  const base = localParts(baseDate, timezoneOffsetMinutes);
  let target = { ...base, hour: defaultDueHour, minute: 0 };
  let foundDate = false;
  let dateKind = "";
  let dateConfidence = 0;
  const matched: string[] = [];

  const absoluteNumeric = /\b(\d{1,2})[\/-](\d{1,2})(?:[\/-](\d{2,4}))?\b/u.exec(text);
  if (absoluteNumeric) {
    const day = Number(absoluteNumeric[1]);
    const month = Number(absoluteNumeric[2]);
    const yearWasExplicit = Boolean(absoluteNumeric[3]);
    let year = absoluteNumeric[3] ? Number(absoluteNumeric[3]) : base.year;
    if (year < 100) year += 2000;
    if (!yearWasExplicit && validDate(year, month, day)) {
      const candidateDay = Date.UTC(year, month - 1, day);
      const baseDay = Date.UTC(base.year, base.month - 1, base.day);
      if (candidateDay < baseDay) year += 1;
    }
    if (validDate(year, month, day)) {
      target = { year, month, day, hour: defaultDueHour, minute: 0 };
      foundDate = true;
      dateKind = "absolute_numeric";
      dateConfidence = 0.97;
      matched.push(absoluteNumeric[0]);
    }
  }

  if (!foundDate) {
    const absoluteNamed = /\b(\d{1,2})(?:st|nd|rd|th)?\s+(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|october|oct|november|nov|december|dec)(?:\s+(\d{4}))?\b/iu.exec(text);
    if (absoluteNamed) {
      const day = Number(absoluteNamed[1]);
      const month = MONTHS[(absoluteNamed[2] ?? "").toLocaleLowerCase()] ?? 0;
      let year = absoluteNamed[3] ? Number(absoluteNamed[3]) : base.year;
      if (!absoluteNamed[3] && validDate(year, month, day)) {
        const candidateDay = Date.UTC(year, month - 1, day);
        const baseDay = Date.UTC(base.year, base.month - 1, base.day);
        if (candidateDay < baseDay) year += 1;
      }
      if (validDate(year, month, day)) {
        target = { year, month, day, hour: defaultDueHour, minute: 0 };
        foundDate = true;
        dateKind = "absolute_named";
        dateConfidence = 0.97;
        matched.push(absoluteNamed[0]);
      }
    }
  }

  if (!foundDate) {
    const relativeRules: Array<[RegExp, number, string, number]> = [
      [/\b(?:day\s+after\s+tomorrow|marunaal|naalanniku|parso|நாளை\s+மறுநாள்|परसों)\b/iu, 2, "day_after_tomorrow", 0.91],
      [/\b(?:tomorrow|tmrw|tmr|nalaiku|naalaiku|kal|நாளை|कल)\b/iu, 1, "tomorrow", 0.88],
      [/\b(?:today|tdy|innaiku|indru|aaj|இன்று|आज)\b/iu, 0, "today", 0.97],
    ];
    for (const [regex, days, kind, confidence] of relativeRules) {
      const match = regex.exec(text);
      if (!match) continue;
      target = addLocalDays(target, days);
      foundDate = true;
      dateKind = kind;
      dateConfidence = confidence;
      matched.push(match[0]);
      break;
    }
  }

  if (!foundDate) {
    const weekdayMatch = /\b(?:next\s+)?(sunday|sun|monday|mon|tuesday|tue|wednesday|wed|thursday|thu|friday|fri|saturday|sat|ஞாயிறு|திங்கள்|செவ்வாய்|புதன்|வியாழன்|வெள்ளி|சனி|ravivar|somvar|mangalvar|budhvar|guruwar|shukravar|shanivar|रविवार|सोमवार|मंगलवार|बुधवार|गुरुवार|शुक्रवार|शनिवार)\b/iu.exec(text);
    if (weekdayMatch) {
      const key = (weekdayMatch[1] ?? "").toLocaleLowerCase();
      const targetWeekday = WEEKDAYS[key];
      if (targetWeekday !== undefined) {
        const baseWeekday = dateFromLocal(base).getUTCDay();
        let days = (targetWeekday - baseWeekday + 7) % 7;
        if (days === 0 || /^next\s+/iu.test(weekdayMatch[0])) days += 7;
        target = addLocalDays(target, days);
        foundDate = true;
        dateKind = "weekday";
        dateConfidence = 0.92;
        matched.push(weekdayMatch[0]);
      }
    }
  }

  const time = findTime(text, defaultDueHour);
  if (time.found) {
    target.hour = time.hour;
    target.minute = time.minute;
    matched.push(...time.matched);
  }

  if (!foundDate && time.found) {
    target = { ...base, hour: time.hour, minute: time.minute };
    const baseMinutes = base.hour * 60 + base.minute;
    const targetMinutes = target.hour * 60 + target.minute;
    if (targetMinutes <= baseMinutes + 5) target = addLocalDays(target, 1);
    foundDate = true;
    dateKind = target.day === base.day ? "time_today" : "time_next_day";
    dateConfidence = Math.min(0.90, time.confidence);
  }

  if (!foundDate) {
    return { found: false, iso: "", human: "", confidence: 1, matched: [], dateKind: "none" };
  }

  const confidence = Math.min(dateConfidence || 0.80, time.found ? time.confidence : 0.82);
  const sameDay = target.year === base.year && target.month === base.month && target.day === base.day;
  const tomorrow = dateFromLocal(target).getTime() - dateFromLocal({ ...base, hour: target.hour, minute: target.minute }).getTime() === DAY_MS;
  const dayLabel = sameDay ? "today" : tomorrow ? "tomorrow" : `on ${target.day} ${monthName(target.month)} ${target.year}`;
  return {
    found: true,
    iso: formatIso(target, timezoneOffsetMinutes),
    human: `${formatTime(target.hour, target.minute)} ${dayLabel}`,
    confidence,
    matched: [...new Set(matched.map((item) => item.trim()).filter(Boolean))],
    dateKind,
  };
}

export function removeDeadlineText(text: string, deadline: DeadlineResult): string {
  let result = text;
  for (const item of [...deadline.matched].sort((a, b) => b.length - a.length)) {
    if (!item) continue;
    const escaped = item.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    result = result.replace(new RegExp(escaped, "giu"), " ");
  }
  return result
    .replace(/\b(?:today|tomorrow|tonight|tmrw|tmr|tdy|innaiku|nalaiku|naalaiku|aaj|kal|parso|manikku|mani|baje|at|by|before|around)\b/giu, " ")
    .replace(/(?:இன்று|நாளை|இரவு|மணிக்கு|மணி|आज|कल|परसों|बजे)/gu, " ")
    .replace(/\b(?:on|at|by|before|around)\s*$/iu, " ")
    .replace(/\s+/g, " ")
    .trim();
}
