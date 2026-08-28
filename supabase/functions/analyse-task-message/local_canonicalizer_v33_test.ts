import { canonicalizeTask } from "./canonicalizer.ts";
import { parseDeadline } from "./datetime_parser.ts";
import type { CompactMember } from "./types.ts";

const members: CompactMember[] = [
  { id: 1, name: "Adhvaidh" },
  { id: 2, name: "Mathi" },
  { id: 3, name: "Ravi" },
  { id: 4, name: "Kumar" },
];
const createdAt = "2026-08-05T12:00:00.000Z"; // 5:30 PM IST
const offset = 330;

interface Case {
  text: string;
  title: string;
  descriptionIncludes?: string[];
}

const cases: Case[] = [
  { text: "hey bro get me the milk today at 7", title: "Buy milk", descriptionIncludes: ["Adhvaidh", "7:00 PM today"] },
  { text: "get the milk from Kumar today at 5", title: "Collect milk from Kumar" },
  { text: "get me milk from supermarket today at 5", title: "Buy milk from supermarket" },
  { text: "get the report from email", title: "Download report from email" },
  { text: "get approval from client tomorrow", title: "Obtain approval from client" },
  { text: "please make a call to Ravi tomorrow at 10", title: "Call Ravi" },
  { text: "give me an update on campaign by 6 pm", title: "Update campaign", descriptionIncludes: ["Adhvaidh", "6:00 PM"] },
  { text: "do the payment for electricity bill today", title: "Pay electricity bill" },
  { text: "take a print of final agreement", title: "Print final agreement" },
  { text: "take a screenshot of payment page", title: "Capture screenshot payment page" },
  { text: "take backup of production database", title: "Back up production database" },
  { text: "make a booking for dentist tomorrow", title: "Book dentist" },
  { text: "fix meeting with client tomorrow at 3", title: "Schedule meeting with client" },
  { text: "save a copy of final contract in Drive", title: "Save final contract in Drive" },
  { text: "attach invoice to client email", title: "Attach invoice to client email" },
  { text: "rename the final presentation", title: "Rename final presentation" },
  { text: "compare vendor quotations", title: "Compare vendor quotations" },
  { text: "summarize weekly performance report", title: "Summarise weekly performance report" },
  { text: "proofread urgent client proposal", title: "Proofread urgent client proposal" },
  { text: "calculate total campaign spend", title: "Calculate total campaign spend" },
  { text: "organize project files", title: "Organise project files" },
  { text: "archive old invoices", title: "Archive old invoices" },
  { text: "delete duplicate customer file", title: "Delete duplicate customer file" },
  { text: "restore deleted quotation", title: "Restore deleted quotation" },
  { text: "convert brochure to PDF", title: "Convert brochure to PDF" },
  { text: "export customer list", title: "Export customer list" },
  { text: "pack customer order", title: "Pack customer order" },
  { text: "clean meeting room", title: "Clean meeting room" },
  { text: "recharge office phone", title: "Recharge office phone" },
  { text: "return damaged product", title: "Return damaged product" },

  // Tanglish
  { text: "invoice anupidu nalaiku 5 manikku", title: "Send invoice" },
  { text: "client ku invoice anuppu", title: "Send invoice to client" },
  { text: "client kitta follow up pannu", title: "Follow up with client" },
  { text: "electricity bill payment pannidu", title: "Pay electricity bill" },
  { text: "report ready pannu", title: "Prepare report" },
  { text: "urgent poster design pannu", title: "Create urgent poster" },
  { text: "paal vangidu", title: "Buy milk" },
  { text: "production database backup eduthu vechidu", title: "Back up production database" },
  { text: "client ku update kudunga", title: "Update client" },
  { text: "meeting fix pannu nalaiku 4 manikku", title: "Schedule meeting" },

  // Hinglish
  { text: "client ko invoice bhej do", title: "Send invoice to client" },
  { text: "bijli ka bill payment kar do", title: "Pay electricity bill" },
  { text: "kal 5 baje report bhej dena", title: "Send report" },
  { text: "client se follow up kar lo", title: "Follow up with client" },
  { text: "doodh kharid lo", title: "Buy milk" },
  { text: "meeting fix kar do kal 4 baje", title: "Schedule meeting" },
  { text: "weekly report summary bana do", title: "Summarise weekly report" },
  { text: "final file ka naam badal do", title: "Rename final file" },
  { text: "production database backup le lo", title: "Back up production database" },
  { text: "client ko update de do", title: "Update client" },
];

let failed = 0;
for (const item of cases) {
  const deadline = parseDeadline(item.text, createdAt, offset);
  const result = canonicalizeTask(item.text, members, [], [], deadline, "Adhvaidh");
  const titleOk = result.title === item.title;
  const descriptionOk = (item.descriptionIncludes ?? []).every((part) => result.description.includes(part));
  const ok = titleOk && descriptionOk;
  console.log(`${ok ? "PASS" : "FAIL"} ${item.text} -> ${result.title} | ${result.description} | ${result.confidence.toFixed(2)} ${result.issues.join(",")}`);
  if (!ok) failed += 1;
}

if (failed > 0) {
  console.error(`${failed} local canonicalizer cases failed.`);
  process.exit(1);
}
console.log(`Taskly v3.3 local canonicalizer passed ${cases.length} cases.`);
