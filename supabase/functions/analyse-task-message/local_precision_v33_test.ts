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

const normalChat = [
  "The payment was successful",
  "The update looks good",
  "The print quality is bad",
  "The backup is complete",
  "The client call was useful",
  "I like the final design",
  "Ravi is preparing the report",
  "I received the invoice",
  "The report was sent yesterday",
  "This archive is empty",
  "The meeting is tomorrow",
  "When is the client meeting?",
  "Did you save the file?",
  "The milk is in the fridge",
  "Mathi completed the task",
];

let failures = 0;
for (const message of normalChat) {
  const result = analyseLocally(message, context);
  const ok = result.route !== "local_create" && result.route !== "local_update";
  console.log(`${ok ? "PASS" : "FAIL"} ${result.route.padEnd(12)} ${message}`);
  if (!ok) failures += 1;
}
if (failures) throw new Error(`${failures} precision cases failed`);
console.log(`Taskly v3.3 local precision passed ${normalChat.length} cases.`);
