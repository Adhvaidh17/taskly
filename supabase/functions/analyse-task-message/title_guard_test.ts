import { guardTaskDecision, isUnsafeTaskTitle, removeTemporalTitleNoise } from "./title_guard.ts";
import type { CanonicalCandidate, DeadlineResult, TaskDecision } from "./types.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const deadline: DeadlineResult = {
  found: true,
  iso: "2026-08-05T17:00:00+05:30",
  human: "5:00 PM today",
  confidence: 0.98,
  matched: ["today at 5"],
  dateKind: "relative",
};

const candidate: CanonicalCandidate = {
  actionKey: "buy",
  actionTitle: "Buy",
  object: "milk",
  source: "",
  recipient: "requester",
  title: "Buy milk",
  description: "Buy milk for the requester by 5:00 PM today.",
  confidence: 0.94,
  issues: [],
};

const base: TaskDecision = {
  t: true,
  c: 0.91,
  a: "create",
  ttl: "Today at 5",
  d: "hey bro get me the milk today at 5",
  as: 2,
  due: "",
  p: "medium",
  tid: null,
  st: "",
  r: "task",
  l: "en",
};

const fixed = guardTaskDecision(base, "hey bro get me the milk today at 5", candidate, deadline);
assert(fixed.t, "valid candidate must remain a task");
assert(fixed.ttl === "Buy milk", `expected Buy milk, got ${fixed.ttl}`);
assert(fixed.due === deadline.iso, "deadline must be restored from deterministic parser");
assert(fixed.d !== "hey bro get me the milk today at 5", "description must not copy full message");
assert(!isUnsafeTaskTitle(fixed.ttl), "final title must be safe");
assert(removeTemporalTitleNoise("Send report tomorrow at 10 AM") === "Send report", "time must be removed from title");
assert(removeTemporalTitleNoise("Buy 2 milk packets") === "Buy 2 milk packets", "task quantities must not be removed as clock times");
assert(isUnsafeTaskTitle("Tomorrow 10 AM"), "date/time-only title must be rejected");

const noCandidate = guardTaskDecision({ ...base }, "today at 5", null, deadline);
assert(!noCandidate.t, "date/time-only model result without action fallback must be suppressed");

console.log("PASS title/date guard and description fallback");
