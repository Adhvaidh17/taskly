import { analyseLocally } from "./grammar_engine.ts";
import type { EngineContext } from "./types.ts";

const direct: EngineContext = {
  profileId: 10,
  profileName: "Arun",
  workspaceKind: "direct",
  directKey: "10:20",
  members: [{ id: 10, name: "Arun" }, { id: 20, name: "Mathi" }],
  mentionedProfileIds: [],
  openTasks: [],
  createdAt: "2026-08-05T09:00:00.000Z",
  timezoneOffsetMinutes: 330,
  learnedAliases: [],
  feedbackExamples: [],
};

const group: EngineContext = {
  ...direct,
  workspaceKind: "group",
  directKey: null,
  members: [...direct.members, { id: 30, name: "Kumar" }],
};

const taskMessages: Array<[string, EngineContext]> = [
  ["send the report tomorrow", direct],
  ["please call the client at 4 pm", direct],
  ["Mathi submit the quotation today", group],
  ["buy milk on the way home", direct],
  ["get milk from Kumar at 5", direct],
  ["remind me tomorrow to pay rent", { ...direct, directKey: "self:10", members: [{ id: 10, name: "Arun" }] }],
  ["I will complete the deck tonight", { ...direct, directKey: "self:10", members: [{ id: 10, name: "Arun" }] }],
  ["kindly reconcile the ledger", direct],
  ["please notarize this agreement", direct],
  ["could you upload the files", direct],
  ["invoice anupidu", direct],
  ["nalaiku 5 manikku report anupidu", direct],
  ["Mathi client ah call pannu", group],
  ["bro groceries vangidu", direct],
  ["quotation evening kulla mudichidu", direct],
  ["kal 5 baje report bhej dena", direct],
  ["client ko call kar dena", direct],
  ["zara invoice pay kar dena", direct],
  ["agreement submit karna kal", direct],
  ["Mathi ko files bhejo", group],
  ["நாளைக்கு ரிப்போர்ட் அனுப்பு", direct],
  ["Mathi தயவு செய்து client-ஐ call பண்ணு", group],
  ["कल रिपोर्ट भेज देना", direct],
  ["क्लाइंट को शाम तक कॉल करना", direct],
  ["envía el informe mañana", direct],
  ["envoie le rapport demain", direct],
  ["schick den bericht morgen", direct],
  ["明天把报告发给我", direct],
  ["أرسل التقرير غدًا", direct],
  ["send invoice and then call client", direct],
];

const nonTaskMessages: Array<[string, EngineContext]> = [
  ["hello bro", direct],
  ["okay thanks", direct],
  ["Mathi is in the office", group],
  ["Lunch was good today", direct],
  ["I sent the report yesterday", direct],
  ["I finished the quotation", direct],
  ["When will you send the invoice?", direct],
  ["Did you call the client?", direct],
  ["What is the deadline?", direct],
  ["Tomorrow is a holiday", direct],
  ["5 pm is too late", direct],
  ["report anupiten", direct],
  ["kal meeting hai", direct],
  ["seri bro", direct],
  ["haan theek hai", direct],
  ["நாளை விடுமுறை", direct],
];

let failures = 0;
for (const [message, context] of taskMessages) {
  const result = analyseLocally(message, context);
  if (result.route === "local_skip") {
    failures += 1;
    console.error(`FALSE NEGATIVE: ${message} -> ${result.reason}`);
  } else {
    console.log(`TASK OK ${result.route.padEnd(12)} ${message}`);
  }
}

for (const [message, context] of nonTaskMessages) {
  const result = analyseLocally(message, context);
  if (result.route === "local_create" || result.route === "local_update") {
    failures += 1;
    console.error(`FALSE POSITIVE: ${message} -> ${result.decision?.ttl ?? result.reason}`);
  } else {
    console.log(`CHAT OK ${result.route.padEnd(12)} ${message}`);
  }
}

if (failures > 0) throw new Error(`${failures} recall/precision guard test(s) failed`);
