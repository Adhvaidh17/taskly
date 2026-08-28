import { evaluateGrammarGate, type GateContext } from "./grammar_gate.ts";

const direct: GateContext = {
  profileId: 10,
  workspaceKind: "direct",
  directKey: "10:20",
  members: [
    { id: 10, name: "Me" },
    { id: 20, name: "Mathi" },
  ],
  mentionedProfileIds: [],
  openTasks: [],
};

const self: GateContext = {
  ...direct,
  directKey: "self:10",
  members: [{ id: 10, name: "Me" }],
};

const withTask: GateContext = {
  ...direct,
  openTasks: [{ id: 901, title: "August performance report", status: "todo", assignee_id: 20 }],
};

const cases: Array<[string, GateContext, string]> = [
  ["hello bro", direct, "local_skip"],
  ["okay thanks", direct, "local_skip"],
  ["I finished the quotation yesterday", direct, "local_skip"],
  ["Did you send the quotation?", direct, "local_skip"],
  ["please send the invoice", direct, "local_grammar"],
  ["please reconcile the ledger", direct, "nano"],
  ["Mathi reconcile the ledger", direct, "nano"],
  ["Mathi is in the office", direct, "local_skip"],
  ["invoice anupidu", direct, "local_grammar"],
  ["kal 5 baje report bhej dena", direct, "nano"],
  ["mathi nalaiku 10 manikku invoice anupidu", direct, "nano"],
  ["rember me tmrw 8 call arun", self, "nano"],
  ["I'll finish the quotation", self, "local_grammar"],
  ["I will send the invoice", direct, "local_grammar"],
  ["mark August performance report done", withTask, "mini"],
];

let failed = 0;
for (const [message, context, expected] of cases) {
  const result = evaluateGrammarGate(message, context);
  if (result.route !== expected) {
    failed += 1;
    console.error(`FAIL ${JSON.stringify(message)}: expected ${expected}, got ${result.route} (${result.reason}, ${result.score})`);
  } else {
    console.log(`PASS ${expected.padEnd(13)} ${message}`);
  }
}

if (failed > 0) {
  throw new Error(`${failed} grammar gate test(s) failed`);
}
