import { analyseLocally } from "./grammar_engine.ts";
import type { EngineContext } from "./types.ts";

const context: EngineContext = {
  profileId: 1,
  profileName: "Adhvaidh",
  workspaceKind: "direct",
  directKey: "1:2",
  members: [{ id: 1, name: "Adhvaidh" }, { id: 2, name: "Mathi" }],
  mentionedProfileIds: [],
  openTasks: [],
  createdAt: "2026-08-05T12:00:00.000Z",
  timezoneOffsetMinutes: 330,
  learnedAliases: [],
  feedbackExamples: [],
};

const cases = [
  ["hey bro get me the milk today at 7", "Buy milk"],
  ["give me an update on campaign by 6 pm", "Update campaign"],
  ["do the payment for electricity bill today", "Pay electricity bill"],
  ["take a print of final agreement", "Print final agreement"],
  ["take backup of production database", "Back up production database"],
  ["fix meeting with client tomorrow at 3", "Schedule meeting with client"],
  ["save a copy of final contract in Drive", "Save final contract in Drive"],
  ["rename the final presentation", "Rename final presentation"],
  ["summarize weekly performance report", "Summarise weekly performance report"],
  ["proofread urgent client proposal", "Proofread urgent client proposal"],
  ["compare vendor quotations", "Compare vendor quotations"],
  ["archive old invoices", "Archive old invoices"],
  ["invoice anupidu nalaiku 5 manikku", "Send invoice"],
  ["client ku invoice anuppu", "Send invoice to client"],
  ["client kitta follow up pannu", "Follow up with client"],
  ["electricity bill payment pannidu", "Pay electricity bill"],
  ["production database backup eduthu vechidu", "Back up production database"],
  ["client ko invoice bhej do", "Send invoice to client"],
  ["bijli ka bill payment kar do", "Pay electricity bill"],
  ["weekly report summary bana do", "Summarise weekly report"],
  ["final file ka naam badal do", "Rename final file"],
] as const;

let failures = 0;
for (const [message, title] of cases) {
  const result = analyseLocally(message, context);
  const ok = result.route === "local_create" && result.decision?.ttl === title && result.decision.d.length > 0;
  console.log(`${ok ? "PASS" : "FAIL"} ${result.route.padEnd(12)} ${message} -> ${result.decision?.ttl ?? result.candidate?.title ?? ""} | reason=${result.reason} intent=${result.intentConfidence.toFixed(3)} canonical=${result.canonicalConfidence.toFixed(3)} issues=${result.candidate?.issues.join(",") ?? ""}`);
  if (!ok) failures += 1;
}
if (failures) throw new Error(`${failures} local pipeline cases failed`);
console.log(`Taskly v3.3 local pipeline passed ${cases.length} cases.`);
