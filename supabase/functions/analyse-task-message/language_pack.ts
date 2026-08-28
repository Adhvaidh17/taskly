import type { LearnedAlias } from "./types.ts";

export interface ActionDefinition {
  key: string;
  title: string;
  aliases: string[];
}

export interface ActionMatch {
  key: string;
  title: string;
  alias: string;
  start: number;
  end: number;
  confidence: number;
  learned: boolean;
}

export const ACTIONS: ActionDefinition[] = [
  // Communication and coordination
  { key: "send", title: "Send", aliases: ["send", "share", "forward", "email", "mail", "send over", "pass on", "drop a message with", "anuppu", "anupu", "anupidu", "anuppidu", "anupunga", "anuppunga", "அனுப்பு", "பகிர்", "bhej", "bhejo", "bhejna", "bhej dena", "bhej do", "भेज", "भेजो"] },
  { key: "submit", title: "Submit", aliases: ["submit", "hand in", "turn in", "lodge", "jama kar", "jama karo", "ஜமா பண்ணு", "சமர்ப்பி", "जमा कर"] },
  { key: "call", title: "Call", aliases: ["call", "phone", "ring", "make a call", "give a call", "call up", "call pannu", "oru call pannu", "phone pannu", "கால் பண்ணு", "அழை", "call karo", "call kar do", "phone karo", "फोन करो"] },
  { key: "message", title: "Message", aliases: ["message", "text", "ping", "whatsapp", "msg", "drop a message", "send a message", "message pannu", "மெசேஜ் பண்ணு", "message karo", "message kar do"] },
  { key: "reply", title: "Reply to", aliases: ["reply", "respond", "answer", "reply back", "reply pannu", "பதில் அனுப்பு", "jawab do", "reply karo", "जवाब दो"] },
  { key: "follow_up", title: "Follow up with", aliases: ["follow up", "followup", "check with", "connect with", "touch base with", "chase", "follow up pannu", "followup pannu", "check pannu", "followup karo", "follow up kar lo", "follow up kar do"] },
  { key: "notify", title: "Notify", aliases: ["notify", "inform", "alert", "let know", "keep informed", "therivikka", "தெரிவி", "bata dena", "suchit karo", "सूचित करो"] },
  { key: "remind", title: "Remind", aliases: ["remind", "set a reminder", "put a reminder", "add a reminder", "reminder podu", "reminder vechu", "நினைவூட்டு", "reminder laga do", "yaad dila", "याद दिला"] },
  { key: "confirm", title: "Confirm", aliases: ["confirm", "double confirm", "get confirmation", "confirm pannu", "uruthi pannu", "உறுதி செய்", "confirm karo", "pakka karo", "पक्का करो"] },
  { key: "coordinate", title: "Coordinate with", aliases: ["coordinate", "coordinate with", "sync with", "align with", "coordinate pannu", "ஒருங்கிணை", "coordinate karo"] },
  { key: "invite", title: "Invite", aliases: ["invite", "send invite", "add to meeting", "invite pannu", "அழைப்பு அனுப்பு", "invite karo", "बुलाओ"] },
  { key: "ask", title: "Ask", aliases: ["ask", "request", "enquire", "inquire", "check with", "kelu", "கேள்", "pucho", "poochho", "पूछो"] },
  { key: "tell", title: "Tell", aliases: ["tell", "let them know", "batao", "சொல்", "தெரிவி", "बताओ"] },

  // Review, content and knowledge work
  { key: "check", title: "Check", aliases: ["check", "verify", "inspect", "review", "cross check", "cross-check", "validate", "have a look at", "take a look at", "check pannu", "paaru", "பார்", "சரிபார்", "check karo", "check kar do", "dekho", "जाँच करो"] },
  { key: "prepare", title: "Prepare", aliases: ["prepare", "draft", "compile", "put together", "get ready", "ready pannu", "prepare pannu", "தயார் பண்ணு", "தயாரி", "taiyar karo", "tayyar karo", "तैयार करो"] },
  { key: "create", title: "Create", aliases: ["create", "design", "develop", "build", "generate", "produce", "create pannu", "design pannu", "உருவாக்கு", "செய்", "banao", "bana do", "बनाओ"] },
  { key: "write", title: "Write", aliases: ["write", "type", "compose", "write up", "ezhuthu", "எழுது", "likho", "likh do", "लिखो"] },
  { key: "update", title: "Update", aliases: ["update", "edit", "modify", "revise", "change", "give update", "give an update", "share update", "update pannu", "update kudunga", "maathu", "மாற்று", "திருத்து", "update karo", "update de do", "badlo", "बदलो"] },
  { key: "fix", title: "Fix", aliases: ["fix", "correct", "repair", "resolve", "solve", "debug", "rectify", "fix pannu", "சரி பண்ணு", "திருத்து", "theek karo", "theek kar do", "ठीक करो"] },
  { key: "complete", title: "Complete", aliases: ["complete", "finish", "close", "wrap up", "get done", "mudichidu", "mudinga", "முடி", "முடிச்சிடு", "poora karo", "khatam karo", "पूरा करो"] },
  { key: "start", title: "Start", aliases: ["start", "begin", "kick off", "initiate", "start pannu", "ஆரம்பி", "shuru karo", "शुरू करो"] },
  { key: "analyse", title: "Analyse", aliases: ["analyse", "analyze", "assess", "evaluate", "study", "ஆய்வு செய்", "विश्लेषण करो"] },
  { key: "research", title: "Research", aliases: ["research", "find out", "look into", "investigate", "explore", "ஆராய்ச்சி செய்", "जाँच पड़ताल करो"] },
  { key: "summarise", title: "Summarise", aliases: ["summarise", "summarize", "make a summary", "prepare summary", "summary pannu", "சுருக்கம் செய்", "summary bana do", "saaransh banao", "सारांश बनाओ"] },
  { key: "translate", title: "Translate", aliases: ["translate", "convert language", "mozhi peyar", "மொழிபெயர்", "anuvad karo", "अनुवाद करो"] },
  { key: "proofread", title: "Proofread", aliases: ["proofread", "proof read", "check grammar", "grammar check", "spell check", "பிழை திருத்து", "proofread karo"] },
  { key: "compare", title: "Compare", aliases: ["compare", "contrast", "compare with", "oppidu", "ஒப்பிடு", "tulana karo", "तुलना करो"] },
  { key: "calculate", title: "Calculate", aliases: ["calculate", "compute", "work out", "total", "add up", "kanakku podu", "கணக்கிடு", "hisaab karo", "गणना करो"] },
  { key: "record", title: "Record", aliases: ["record", "note down", "write down", "log this", "document this", "kurichu vechu", "குறித்துக்கொள்", "note kar lo", "लिख लो"] },
  { key: "organise", title: "Organise", aliases: ["organise", "organize", "arrange", "sort", "categorise", "categorize", "ozhungu pannu", "ஒழுங்குபடுத்து", " व्यवस्थित करो", "arrange karo"] },
  { key: "test", title: "Test", aliases: ["test", "try", "qa", "quality check", "test pannu", "சோதனை செய்", "test karo"] },
  { key: "monitor", title: "Monitor", aliases: ["monitor", "track", "watch", "keep track of", "monitor pannu", "கண்காணி", "nazar rakho", "नज़र रखो"] },

  // Planning and meetings
  { key: "schedule", title: "Schedule", aliases: ["schedule", "plan", "set up", "set a time", "arrange meeting", "fix meeting", "set meeting", "schedule pannu", "meeting fix pannu", "திட்டமிடு", "meeting fix karo", "schedule karo"] },
  { key: "reschedule", title: "Reschedule", aliases: ["reschedule", "move meeting", "change meeting time", "postpone meeting", "reschedule pannu", "நேரம் மாற்று", "reschedule karo"] },
  { key: "cancel", title: "Cancel", aliases: ["cancel", "call off", "drop the meeting", "cancel pannu", "ரத்து செய்", "cancel karo", "रद्द करो"] },
  { key: "book", title: "Book", aliases: ["book", "reserve", "make a booking", "appointment book", "ticket book", "book pannu", "booking pannu", "புக் பண்ணு", "book karo", "booking kar do", "बुक करो"] },
  { key: "meet", title: "Meet", aliases: ["meet", "meet with", "meet pannu", "சந்தி", "milo", "मिलो"] },
  { key: "visit", title: "Visit", aliases: ["visit", "go to", "come to", "visit pannu", "போ", "வா", "jao", "aao", "जाओ"] },
  { key: "attend", title: "Attend", aliases: ["attend", "join", "participate", "attend pannu", "கலந்து கொள்", "join karo"] },

  // Commerce, finance and administration
  { key: "pay", title: "Pay", aliases: ["pay", "make payment", "do payment", "settle", "pay bill", "payment pannu", "payment pannidu", "கட்டு", "பணம் செலுத்து", "payment karo", "payment kar do", "bhugtan karo", "भुगतान करो"] },
  { key: "invoice", title: "Create invoice for", aliases: ["raise invoice", "create invoice", "generate invoice", "prepare invoice", "invoice podu", "invoice create pannu", "invoice banao"] },
  { key: "reimburse", title: "Reimburse", aliases: ["reimburse", "refund expense", "pay back", "expense settle", "செலவு திருப்பிச் செலுத்து", "reimburse karo"] },
  { key: "deposit", title: "Deposit", aliases: ["deposit", "bank deposit", "deposit pannu", "வைப்பு செய்", "jama karo"] },
  { key: "withdraw", title: "Withdraw", aliases: ["withdraw", "take out cash", "cash eduthu", "பணம் எடு", "paise nikalo"] },
  { key: "transfer", title: "Transfer", aliases: ["transfer", "send money", "bank transfer", "upi transfer", "transfer pannu", "பணம் மாற்று", "paise bhejo"] },
  { key: "approve", title: "Approve", aliases: ["approve", "accept", "give approval", "approve pannu", "ஒப்புதல் கொடு", "approve karo"] },
  { key: "reject", title: "Reject", aliases: ["reject", "decline", "deny", "reject pannu", "நிராகரி", "reject karo"] },
  { key: "sign", title: "Sign", aliases: ["sign", "approve and sign", "signature podu", "கையெழுத்திடு", "sign karo"] },
  { key: "fill", title: "Fill", aliases: ["fill", "fill in", "fill out", "complete form", "fill pannu", "நிரப்பு", "bhar do", "भर दो"] },
  { key: "reconcile", title: "Reconcile", aliases: ["reconcile", "match accounts", "balance ledger", "reconcile pannu", "hisaab milao"] },

  // Files and digital operations
  { key: "upload", title: "Upload", aliases: ["upload", "post", "publish", "upload pannu", "பதிவேற்று", "upload karo", "अपलोड करो"] },
  { key: "download", title: "Download", aliases: ["download", "download pannu", "பதிவிறக்கு", "download karo", "डाउनलोड करो"] },
  { key: "save", title: "Save", aliases: ["save", "keep a copy", "store a copy", "save pannu", "vechu", "சேமி", "save karo", "सेव करो"] },
  { key: "store", title: "Store", aliases: ["store", "keep", "put away", "store pannu", "சேமித்து வை", "rakh do", "रख दो"] },
  { key: "backup", title: "Back up", aliases: ["backup", "back up", "take backup", "create backup", "backup eduthu", "backup vechu", "காப்புப்பிரதி எடு", "backup le lo"] },
  { key: "archive", title: "Archive", aliases: ["archive", "move to archive", "archive pannu", "காப்பகப்படுத்து", "archive karo"] },
  { key: "delete", title: "Delete", aliases: ["delete", "remove permanently", "trash", "delete pannu", "அழி", "delete karo", "हटा दो"] },
  { key: "restore", title: "Restore", aliases: ["restore", "recover", "bring back", "restore pannu", "மீட்டெடு", "restore karo"] },
  { key: "rename", title: "Rename", aliases: ["rename", "change name", "rename pannu", "பெயர் மாற்று", "naam badlo", "naam badal do", "नाम बदलो"] },
  { key: "move", title: "Move", aliases: ["move", "shift", "relocate", "move pannu", "நகர்த்து", "shift karo"] },
  { key: "copy", title: "Copy", aliases: ["copy", "duplicate", "make a copy", "copy pannu", "நகலெடு", "copy karo"] },
  { key: "attach", title: "Attach", aliases: ["attach", "add attachment", "enclose", "attach pannu", "இணை", "attach karo"] },
  { key: "merge", title: "Merge", aliases: ["merge", "combine", "join files", "merge pannu", "ஒன்றிணை", "merge karo"] },
  { key: "split", title: "Split", aliases: ["split", "separate", "divide", "split pannu", "பிரி", "alag karo"] },
  { key: "convert", title: "Convert", aliases: ["convert", "change format", "convert pannu", "மாற்று", "convert karo"] },
  { key: "export", title: "Export", aliases: ["export", "export pannu", "ஏற்றுமதி செய்", "export karo"] },
  { key: "import", title: "Import", aliases: ["import", "bring in", "import pannu", "இறக்குமதி செய்", "import karo"] },
  { key: "print", title: "Print", aliases: ["print", "take print", "take a print", "print out", "print pannu", "print eduthu", "அச்சிடு", "print karo", "print nikal do"] },
  { key: "scan", title: "Scan", aliases: ["scan", "digitise", "digitize", "scan pannu", "ஸ்கேன் பண்ணு", "scan karo"] },
  { key: "capture", title: "Capture", aliases: ["capture", "take screenshot", "take a screenshot", "screenshot eduthu", "ஸ்கிரீன்ஷாட் எடு", "screenshot le lo"] },

  // Purchases, logistics and physical work
  { key: "buy", title: "Buy", aliases: ["buy", "purchase", "shop for", "vaangu", "vangidu", "வாங்கு", "kharido", "kharid lo", "खरीदो"] },
  { key: "collect", title: "Collect", aliases: ["collect", "pick up", "pickup", "receive from", "eduthu va", "eduthutu va", "எடுத்து வா", "பெறு", "utha lao"] },
  { key: "bring", title: "Bring", aliases: ["bring", "carry", "bring along", "konduva", "kondu va", "கொண்டு வா", "lao", "le aao", "लाओ"] },
  { key: "deliver", title: "Deliver", aliases: ["deliver", "drop", "drop off", "handover", "hand over", "give to", "deliver pannu", "கொடுத்து வா", "pahuncha do", "de do", "पहुंचा दो"] },
  { key: "get", title: "Get", aliases: ["get", "fetch", "obtain", "retrieve", "eduthu", "எடு", "le", "ले"] },
  { key: "obtain", title: "Obtain", aliases: ["obtain approval", "get approval", "get permission", "get confirmation", "secure approval", "approval vaangu", "permission vaangu", "approval lo"] },
  { key: "order", title: "Order", aliases: ["order", "place order", "order pannu", "ஆர்டர் பண்ணு", "order karo", "ऑर्डर करो"] },
  { key: "pack", title: "Pack", aliases: ["pack", "package", "wrap", "pack pannu", "பேக் பண்ணு", "pack karo"] },
  { key: "unpack", title: "Unpack", aliases: ["unpack", "open package", "unpack pannu", "பிரித்து எடு", "unpack karo"] },
  { key: "clean", title: "Clean", aliases: ["clean", "wipe", "sanitize", "tidy", "clean pannu", "சுத்தம் செய்", "saaf karo", "साफ करो"] },
  { key: "wash", title: "Wash", aliases: ["wash", "rinse", "wash pannu", "கழுவு", "dho do", "धो दो"] },
  { key: "cook", title: "Cook", aliases: ["cook", "prepare food", "samayal pannu", "சமை", "pakao", "पकाओ"] },
  { key: "install", title: "Install", aliases: ["install", "set up software", "install pannu", "நிறுவு", "install karo"] },
  { key: "remove", title: "Remove", aliases: ["remove", "take out", "detach", "remove pannu", "நீக்கு", "hata do", "हटा दो"] },
  { key: "replace", title: "Replace", aliases: ["replace", "swap", "change with", "replace pannu", "மாற்றி வை", "badal do"] },
  { key: "charge", title: "Charge", aliases: ["charge", "recharge battery", "charge pannu", "சார்ஜ் பண்ணு", "charge karo"] },
  { key: "recharge", title: "Recharge", aliases: ["recharge", "top up", "mobile recharge", "recharge pannu", "ரீசார்ஜ் பண்ணு", "recharge karo"] },
  { key: "refill", title: "Refill", aliases: ["refill", "fill again", "refill pannu", "மீண்டும் நிரப்பு", "refill karo"] },
  { key: "return", title: "Return", aliases: ["return", "send back", "give back", "return pannu", "திருப்பி கொடு", "wapas karo"] },
  { key: "exchange", title: "Exchange", aliases: ["exchange", "swap item", "exchange pannu", "மாற்றிக்கொள்", "exchange karo"] },
];
const ACTION_BY_KEY = new Map(ACTIONS.map((item) => [item.key, item]));
const SORTED_ALIASES = ACTIONS.flatMap((action) => action.aliases.map((alias) => ({ action, alias })))
  .sort((a, b) => b.alias.length - a.alias.length);

export const REQUEST_MARKER = /\b(?:please|pls|plz|kindly|can\s+you|could\s+you|would\s+you|will\s+you|need\s+you\s+to|you\s+(?:need|have)\s+to|you\s+must|make\s+sure|don['’]?t\s+forget|remember\s+to|remind\s+me|rember\s+me|remndr\s+me|konjam|pleaseu?|kripya|zara|dayavu\s+seithu|தயவு\s*செய்து|कृपया)\b/iu;
export const SELF_REMINDER = /\b(?:remind\s+me|rember\s+me|remndr\s+me|don['’]?t\s+let\s+me\s+forget|nyabagam\s+paduthu|gnabagam\s+paduthu|yaad\s+dila|நினைவூட்டு|याद\s+दिला)\b/iu;
export const FUTURE_COMMITMENT = /\b(?:i['’]?ll|i\s+will|we['’]?ll|we\s+will|let\s+me|i\s+am\s+going\s+to|naan\s+(?:panren|pannuren|seiren|mudikren|anupren|anupuren)|na\s+(?:panren|mudikren|anupren)|main\s+(?:karunga|karungi|bhejunga|bhejungi)|hum\s+(?:karenge|bhejenge)|நான்\s+செய்கிறேன்|मैं\s+करूँगा|मैं\s+करूंगी)\b/iu;
export const PAST_STATEMENT = /\b(?:i\s+(?:already\s+)?(?:did|sent|finished|completed|called|submitted|shared|uploaded|updated|bought|collected|received|downloaded|printed|saved)|we\s+(?:already\s+)?(?:did|sent|finished|completed|submitted)|naan\s+(?:already\s+)?(?:panniten|senjiten|mudichiten|anuppiten|vangiten)|maine\s+(?:kar\s*diya|bhej\s*diya|complete\s+kar\s*diya)|ho\s*gaya|mudinjiduchu|mudichachu|முடிச்சிட்டேன்|कर\s+दिया)\b/iu;
export const GREETING_ONLY = /^(?:h+i+|h+e+y+|hello+|hola|vanakkam+|namaste+|good\s*(?:morning|afternoon|evening|night)|gm+|ga+|ge+|gn+|yo+|dei+|bro+|sis+|mach[ai]+|machi+|anna+|akka+|arey+|oye+|வணக்கம்|नमस्ते)[\s!?.…]*$/iu;
export const ACK_ONLY = /^(?:ok(?:ay)?\s+thanks?|ok(?:ay)?|kk+|k+|sure+|fine+|done+|noted+|got\s*it|understood+|super+|nice+|great+|awesome+|perfect+|thanks?(?:\s*you)?|thanku+|thx+|ty+|seri+|sari+|aama+|ama+|haan+|ha+|ji+|acha+|accha+|theek+|thik+|cool+|சரி|நன்றி|ठीक|धन्यवाद|👍+|👌+|🙏+|✅+|😂+|❤️+|❤+)[\s!?.…]*$/iu;
export const QUESTION_START = /^(?:what|why|when|where|who|which|how|is|are|am|was|were|do|does|did|can|could|would|will|should|have|has|had|enna|yen|eppo|enga|yaar|epdi|epadi|kya|kyu|kyun|kab|kahan|kaun|kaise|என்ன|ஏன்|எப்போது|எங்கே|யார்|எப்படி|क्या|क्यों|कब|कहाँ|कौन|कैसे)\b/iu;
export const URGENCY = /\b(?:urgent|urgently|asap|immediately|right\s+now|high\s+priority|romba\s+urgent|seekiram|udane|jaldi|turant|அவசரம்|உடனே|जल्दी|तुरंत)\b/iu;

export const VOCATIVE_PREFIX = /^(?:(?:hey|hi|hello|dei|bro|brother|sis|sister|machi|machan|anna|akka|arey|oye|da|di|ji|boss|buddy|mate|sir|madam|mam|dude)\s*[,!:\-]*\s*)+/iu;
export const REQUEST_PREFIX = /^(?:(?:please|pls|plz|kindly|konjam|zara|kripya|தயவு\s*செய்து|कृपया|can\s+you|could\s+you|would\s+you|will\s+you|need\s+you\s+to|you\s+need\s+to|make\s+sure\s+to|remember\s+to)\s+)+/iu;

export const PURCHASE_NOUNS = new Set([
  "milk", "bread", "eggs", "egg", "rice", "water", "groceries", "grocery", "vegetables", "vegetable",
  "fruits", "fruit", "medicine", "medicines", "tablet", "tablets", "food", "snacks", "coffee", "tea",
  "chicken", "fish", "mutton", "petrol", "diesel", "stationery", "pen", "pens", "paper", "battery", "batteries",
  "பால்", "ரொட்டி", "முட்டை", "மருந்து", "காய்கறி", "चावल", "दूध", "रोटी", "अंडे", "दवा", "सब्जी",
]);

export const ARTICLE_WORDS = new Set(["a", "an", "the", "this", "that", "these", "those", "oru", "intha", "andha", "ek", "ye", "woh"]);
export const RECIPIENT_WORDS = new Set(["me", "my", "us", "our", "enakku", "ennaku", "enga", "mujhe", "mere", "hamare", "எனக்கு", "என்னை", "मुझे"]);
export const POLITE_WORDS = new Set(["please", "pls", "plz", "kindly", "just", "once", "actually", "maybe", "konjam", "zara", "kripya", "dayavu", "தயவு", "कृपया"]);

export function normaliseText(value: string): string {
  return value
    .normalize("NFKC")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/[’‘`]/g, "'")
    .replace(/https?:\/\/\S+/giu, " URL ")
    .replace(/\s+/g, " ")
    .trim();
}

export function languageHint(text: string): string {
  if (/\p{Script=Tamil}/u.test(text)) return "ta";
  if (/\p{Script=Devanagari}/u.test(text)) return "hi";
  if (/\b(?:nalaiku|naalaiku|innaiku|manikku|pannu|anupu|mudich|konjam|seri|naan|vangidu|konduva)\b/iu.test(text)) return "ta-Latn";
  if (/\b(?:kal|aaj|baje|bhej|karo|dena|yaad|jaldi|main|maine|kharido)\b/iu.test(text)) return "hi-Latn";
  if (/\p{Script=Latin}/u.test(text)) return "en-or-Latn";
  return "und";
}

function boundaryRegex(alias: string): RegExp {
  const escaped = alias.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\s+/g, "\\s+");
  return new RegExp(`(^|[^\\p{L}\\p{N}])(${escaped})(?=$|[^\\p{L}\\p{N}])`, "iu");
}

export function findAction(text: string, learnedAliases: LearnedAlias[]): ActionMatch | null {
  const candidates: ActionMatch[] = [];
  const learned = learnedAliases
    .filter((row) => row.source_phrase && row.canonical_action && row.accepted_count > row.rejected_count)
    .sort((a, b) => b.source_phrase.length - a.source_phrase.length);

  for (const row of learned) {
    const regex = boundaryRegex(row.source_phrase);
    const match = regex.exec(text);
    if (!match) continue;
    const canonical = ACTION_BY_KEY.get(row.canonical_action);
    const matched = match[2] ?? row.source_phrase;
    const start = (match.index ?? 0) + (match[1]?.length ?? 0);
    candidates.push({
      key: canonical?.key ?? row.canonical_action,
      title: canonical?.title ?? sentenceCase(row.canonical_action),
      alias: matched,
      start,
      end: start + matched.length,
      confidence: Math.min(0.98, 0.86 + Math.min(0.10, row.accepted_count * 0.02)),
      learned: true,
    });
  }

  for (const item of SORTED_ALIASES) {
    const regex = boundaryRegex(item.alias);
    const match = regex.exec(text);
    if (!match) continue;
    const matched = match[2] ?? item.alias;
    const start = (match.index ?? 0) + (match[1]?.length ?? 0);
    candidates.push({
      key: item.action.key,
      title: item.action.title,
      alias: matched,
      start,
      end: start + matched.length,
      confidence: 0.94,
      learned: false,
    });
  }

  candidates.sort((a, b) => a.start - b.start || Number(b.learned) - Number(a.learned) || b.alias.length - a.alias.length);
  return candidates[0] ?? null;
}

export function actionByKey(key: string): ActionDefinition | null {
  return ACTION_BY_KEY.get(key) ?? null;
}

export function sentenceCase(value: string): string {
  const text = value.trim();
  if (!text) return "";
  return `${text.charAt(0).toLocaleUpperCase()}${text.slice(1)}`;
}

export function firstLexicalToken(value: string): string {
  const match = value.toLocaleLowerCase().match(/[\p{L}\p{N}][\p{L}\p{N}'_-]*/u);
  return match?.[0] ?? "";
}
