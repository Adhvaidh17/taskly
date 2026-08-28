export interface LocalPhraseResult {
  text: string;
  changed: boolean;
  confidenceBoost: number;
}

interface PhraseRule {
  pattern: RegExp;
  replacement: string;
  boost?: number;
}

// These rules normalize frequent human "light verb" constructions where the
// grammatical verb (do/make/give/take/put/pannu/karo) carries little meaning.
// The noun beside it carries the actual task action.
const PHRASE_RULES: PhraseRule[] = [
  { pattern: /\bgive\s+(?:me|us)\s+(?:an?\s+)?update(?:\s+on)?\b/giu, replacement: "update", boost: 0.04 },
  { pattern: /\b(?:give|share)\s+(?:an?\s+)?update(?:\s+on)?\b/giu, replacement: "update", boost: 0.03 },
  { pattern: /\b(?:make|give)\s+(?:me\s+|us\s+)?(?:an?\s+)?call(?:\s+to)?\b/giu, replacement: "call", boost: 0.04 },
  { pattern: /\b(?:do|make)\s+(?:the\s+|a\s+)?payment(?:\s+(?:for|of))?\b/giu, replacement: "pay", boost: 0.04 },
  { pattern: /\b(?:do|make)\s+(?:a\s+)?(?:follow[ -]?up)(?:\s+with)?\b/giu, replacement: "follow up", boost: 0.04 },
  { pattern: /\b(?:take|get)\s+(?:a\s+|the\s+)?print(?:out)?(?:\s+of)?\b/giu, replacement: "print", boost: 0.04 },
  { pattern: /\b(?:take|get)\s+(?:a\s+|the\s+)?screen\s*shot(?:\s+of)?\b/giu, replacement: "capture screenshot", boost: 0.04 },
  { pattern: /\b(?:take|create|make)\s+(?:a\s+|the\s+)?back[ -]?up(?:\s+of)?\b/giu, replacement: "back up", boost: 0.04 },
  { pattern: /\b(?:put|set|add)\s+(?:a\s+|the\s+)?reminder(?:\s+(?:for|to))?\b/giu, replacement: "remind", boost: 0.03 },
  { pattern: /\b(?:put|set|fix|arrange)\s+(?:a\s+|the\s+)?meeting(?:\s+with)?\b/giu, replacement: "schedule meeting with", boost: 0.03 },
  { pattern: /\b(?:make|do)\s+(?:a\s+|the\s+)?booking(?:\s+for)?\b/giu, replacement: "book", boost: 0.03 },
  { pattern: /\b(?:give|provide)\s+(?:the\s+|an?\s+)?approval(?:\s+for)?\b/giu, replacement: "approve", boost: 0.03 },
  { pattern: /\b(?:make|create)\s+(?:a\s+|the\s+)?copy(?:\s+of)?\b/giu, replacement: "copy", boost: 0.03 },
  { pattern: /\b(?:keep|save|store)\s+(?:a\s+|the\s+)?copy(?:\s+of)?\b/giu, replacement: "save", boost: 0.03 },
  { pattern: /\b(?:make|prepare)\s+(?:a\s+|the\s+)?summary(?:\s+of)?\b/giu, replacement: "summarise", boost: 0.04 },
  { pattern: /\b(?:change|edit)\s+(?:the\s+)?name(?:\s+of)?\b/giu, replacement: "rename", boost: 0.03 },

  // Tanglish light-verb constructions.
  { pattern: /\bupdate\s+(?:kudu|kudunga|kuduthu|thaa|thaanga)\b/giu, replacement: "update", boost: 0.04 },
  { pattern: /\bpayment\s+(?:pannu|pannidu|pannunga|senjidu|seyyunga)\b/giu, replacement: "pay", boost: 0.04 },
  { pattern: /\b(?:oru\s+)?call\s+(?:pannu|pannidu|pannunga)\b/giu, replacement: "call", boost: 0.04 },
  { pattern: /\bfollow[ -]?up\s+(?:pannu|pannidu|pannunga)\b/giu, replacement: "follow up", boost: 0.04 },
  { pattern: /\bprint\s+(?:eduthu|eduthudu|edunga|pannu)\b/giu, replacement: "print", boost: 0.04 },
  { pattern: /\bbackup\s+(?:eduthu|eduthudu|vechu|vechidu|pannu)\b/giu, replacement: "back up", boost: 0.04 },
  { pattern: /\bmeeting\s+(?:fix|schedule)\s+(?:pannu|pannidu|pannunga)\b/giu, replacement: "schedule meeting", boost: 0.04 },
  { pattern: /\bmeeting\s+(?:fix|schedule)\b/giu, replacement: "schedule meeting", boost: 0.03 },
  { pattern: /\breminder\s+(?:podu|vechu|set\s+pannu)\b/giu, replacement: "remind", boost: 0.03 },
  { pattern: /\bsummary\s+(?:pannu|ready\s+pannu|senjidu)\b/giu, replacement: "summarise", boost: 0.04 },
  { pattern: /\bname\s+(?:maathu|mathu|change\s+pannu)\b/giu, replacement: "rename", boost: 0.03 },

  // Hinglish light-verb constructions.
  { pattern: /\bupdate\s+(?:de\s*do|de\s*dena|kar\s*do)\b/giu, replacement: "update", boost: 0.04 },
  { pattern: /\bpayment\s+(?:kar\s*do|karna|karo)\b/giu, replacement: "pay", boost: 0.04 },
  { pattern: /\bcall\s+(?:kar\s*do|karna|karo)\b/giu, replacement: "call", boost: 0.04 },
  { pattern: /\bfollow[ -]?up\s+(?:kar\s*do|kar\s*lo|karo)\b/giu, replacement: "follow up", boost: 0.04 },
  { pattern: /\bprint\s+(?:nikal\s*do|kar\s*do)\b/giu, replacement: "print", boost: 0.04 },
  { pattern: /\bbackup\s+(?:le\s*lo|bana\s*do|kar\s*do)\b/giu, replacement: "back up", boost: 0.04 },
  { pattern: /\bmeeting\s+(?:fix|schedule)\s+(?:kar\s*do|karo)\b/giu, replacement: "schedule meeting", boost: 0.04 },
  { pattern: /\bmeeting\s+(?:fix|schedule)\b/giu, replacement: "schedule meeting", boost: 0.03 },
  { pattern: /\breminder\s+(?:laga\s*do|set\s*kar\s*do)\b/giu, replacement: "remind", boost: 0.03 },
  { pattern: /\bsummary\s+(?:bana\s*do|taiyar\s*karo)\b/giu, replacement: "summarise", boost: 0.04 },
  { pattern: /\bnaam\s+(?:badal\s*do|badlo)\b/giu, replacement: "rename", boost: 0.03 },
];

const NOUN_REPLACEMENTS: Array<[RegExp, string]> = [
  [/\bpaal\b/giu, "milk"],
  [/\bdoodh\b/giu, "milk"],
  [/\bthanni\b/giu, "water"],
  [/\bpaani\b/giu, "water"],
  [/\bmarundhu\b/giu, "medicine"],
  [/\bdawai\b/giu, "medicine"],
  [/\bbijli\s+ka\s+bill\b/giu, "electricity bill"],
  [/\bcurrent\s+bill\b/giu, "electricity bill"],
  [/\bphone\s+recharge\b/giu, "mobile recharge"],
  [/\bppt\b/giu, "presentation"],
  [/\bdoc\b/giu, "document"],
  [/\bquotation\b/giu, "quotation"],
];

const FILLER_WORDS = /\b(?:hey|hi|hello|bro|brother|sis|sister|buddy|mate|dude|boss|sir|madam|mam|dei|machi|machan|anna|akka|arey|oye|da|di|ji|actually|basically|just|once|maybe|somehow|please|pls|plz|kindly|konjam|zara|kripya)\b/giu;

export function normaliseLocalTaskPhrase(value: string): LocalPhraseResult {
  let text = value;
  let changed = false;
  let confidenceBoost = 0;

  for (const [pattern, replacement] of NOUN_REPLACEMENTS) {
    const next = text.replace(pattern, replacement);
    if (next !== text) changed = true;
    text = next;
  }

  for (const rule of PHRASE_RULES) {
    const next = text.replace(rule.pattern, rule.replacement);
    if (next !== text) {
      changed = true;
      confidenceBoost = Math.max(confidenceBoost, rule.boost ?? 0.02);
    }
    text = next;
  }

  // Remove conversational fillers only at the request shell. Object adjectives,
  // quantities, product names and proper names are intentionally preserved.
  text = text.replace(FILLER_WORDS, " ")
    .replace(/\s+/g, " ")
    .replace(/^[,;:!?.\-\s]+|[,;:!?.\-\s]+$/g, "")
    .trim();

  return { text, changed, confidenceBoost };
}
