import { analyseLocally } from "./grammar_engine.ts";
import type { EngineContext } from "./types.ts";

const direct: EngineContext = {
  profileId: 10,
  profileName: "Arun",
  workspaceKind: "direct",
  directKey: "10:20",
  members: [
    { id: 10, name: "Arun" },
    { id: 20, name: "Mathi" },
  ],
  mentionedProfileIds: [],
  openTasks: [],
  createdAt: "2026-08-05T07:30:00.000Z",
  timezoneOffsetMinutes: 330,
  learnedAliases: [],
  feedbackExamples: [],
};

const self: EngineContext = {
  ...direct,
  directKey: "self:10",
  members: [{ id: 10, name: "Arun" }],
};

const group: EngineContext = {
  ...direct,
  workspaceKind: "group",
  directKey: null,
  members: [
    { id: 10, name: "Arun" },
    { id: 20, name: "Mathi" },
    { id: 30, name: "Kumar" },
  ],
};

const withTask: EngineContext = {
  ...direct,
  openTasks: [{ id: 901, title: "August performance report", status: "todo", assignee_id: 20 }],
};

const withLearnedAlias: EngineContext = {
  ...direct,
  learnedAliases: [{ source_phrase: "zap", canonical_action: "send", accepted_count: 3, rejected_count: 0 }],
};

interface TestCase {
  message: string;
  context: EngineContext;
  route: string;
  title?: string;
  descriptionIncludes?: string;
  dueIncludes?: string;
  dueEmpty?: boolean;
  assignee?: number | null;
}

const cases: TestCase[] = [
  { message: "hello bro", context: direct, route: "local_skip" },
  { message: "okay thanks", context: direct, route: "local_skip" },
  { message: "Mathi is in the office", context: group, route: "local_skip" },
  { message: "Lunch was good today", context: direct, route: "local_skip" },
  { message: "envía el informe mañana", context: direct, route: "ai_nano" },
  { message: "明天把报告发给我", context: direct, route: "ai_nano" },
  { message: "I finished the quotation yesterday", context: direct, route: "local_skip" },
  { message: "When will you send the invoice?", context: direct, route: "local_skip" },
  { message: "hey bro get me the milk today at 5", context: direct, route: "local_create", title: "Buy milk", descriptionIncludes: "Buy milk for Arun by 5:00 PM today", dueIncludes: "T17:00:00+05:30", assignee: 20 },
  { message: "get the milk from Kumar today at 5", context: direct, route: "local_create", title: "Collect milk from Kumar", descriptionIncludes: "Collect milk from Kumar", dueIncludes: "T17:00:00+05:30", assignee: 20 },
  { message: "get me milk from supermarket today at 5", context: direct, route: "local_create", title: "Buy milk from supermarket", descriptionIncludes: "Buy milk from supermarket for Arun", dueIncludes: "T17:00:00+05:30", assignee: 20 },
  { message: "get the report from email", context: direct, route: "local_create", title: "Download report from email", assignee: 20 },
  { message: "please send me the invoice", context: direct, route: "local_create", title: "Send invoice", descriptionIncludes: "Send invoice to Arun", assignee: 20 },
  { message: "buy 2 milk packets", context: direct, route: "local_create", title: "Buy 2 milk packets", dueEmpty: true, assignee: 20 },
  { message: "submit report by 10/08/2026", context: direct, route: "local_create", title: "Submit report", dueIncludes: "2026-08-10T18:00:00+05:30", assignee: 20 },
  { message: "submit report on 1 January", context: direct, route: "local_create", title: "Submit report", dueIncludes: "2027-01-01T18:00:00+05:30", assignee: 20 },
  { message: "pay invoice at 12 pm", context: direct, route: "local_create", title: "Pay invoice", dueIncludes: "T12:00:00+05:30", assignee: 20 },
  { message: "invoice anupidu", context: direct, route: "local_create", title: "Send invoice", assignee: 20 },
  { message: "Mathi nalaiku 10 manikku invoice anupidu", context: group, route: "local_create", title: "Send invoice", dueIncludes: "T10:00:00+05:30", assignee: 20 },
  { message: "kal 5 baje report bhej dena", context: direct, route: "local_create", title: "Send report", dueIncludes: "T17:00:00+05:30", assignee: 20 },
  { message: "rember me tmrw 8 call Mathi", context: self, route: "local_create", title: "Call Mathi", dueIncludes: "T08:00:00+05:30", assignee: 10 },
  { message: "I'll finish the quotation", context: self, route: "local_create", title: "Complete quotation", assignee: 10 },
  { message: "please reconcile the ledger", context: direct, route: "local_create", title: "Reconcile ledger", assignee: 20 },
  { message: "please notarize the agreement", context: direct, route: "local_create", title: "Notarize agreement", assignee: 20 },
  { message: "zap the invoice", context: withLearnedAlias, route: "local_create", title: "Send invoice", assignee: 20 },
  { message: "please get the report", context: direct, route: "ai_nano" },
  { message: "send the invoice and call the client", context: direct, route: "ai_mini" },
  { message: "mark August performance report done", context: withTask, route: "local_update" },
  { message: "mark that report done", context: withTask, route: "ai_mini" },
  { message: "Mathi தயவு செய்து invoice அனுப்பு நாளை 5 மணிக்கு", context: group, route: "local_create", title: "Send invoice", dueIncludes: "T17:00:00+05:30", assignee: 20 },
];

let failures = 0;
for (const item of cases) {
  const result = analyseLocally(item.message, item.context);
  const decision = result.decision;
  const problems: string[] = [];
  if (result.route !== item.route) problems.push(`route expected ${item.route}, got ${result.route}`);
  if (item.title !== undefined && decision?.ttl !== item.title) problems.push(`title expected ${JSON.stringify(item.title)}, got ${JSON.stringify(decision?.ttl)}`);
  if (item.descriptionIncludes && !decision?.d.includes(item.descriptionIncludes)) problems.push(`description missing ${JSON.stringify(item.descriptionIncludes)}; got ${JSON.stringify(decision?.d)}`);
  if (item.dueIncludes && !decision?.due.includes(item.dueIncludes)) problems.push(`due missing ${item.dueIncludes}; got ${decision?.due}`);
  if (item.dueEmpty && decision?.due !== "") problems.push(`due expected empty, got ${decision?.due}`);
  if (item.assignee !== undefined && decision?.as !== item.assignee) problems.push(`assignee expected ${item.assignee}, got ${decision?.as}`);

  if (problems.length > 0) {
    failures += 1;
    console.error(`FAIL ${item.message}\n  ${problems.join("\n  ")}\n  reason=${result.reason}, intent=${result.intentConfidence}, canonical=${result.canonicalConfidence}, issues=${result.candidate?.issues.join(",") ?? ""}`);
  } else {
    console.log(`PASS ${result.route.padEnd(12)} ${item.message}${decision?.ttl ? ` -> ${decision.ttl}` : ""}`);
  }
}

if (failures > 0) throw new Error(`${failures} test(s) failed`);
