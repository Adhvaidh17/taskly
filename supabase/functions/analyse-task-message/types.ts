export type TaskAction = "none" | "create" | "update" | "status_change";
export type TaskStatus = "" | "todo" | "in-progress" | "done";
export type TaskPriority = "low" | "medium" | "high";
export type EngineRoute = "local_skip" | "local_create" | "local_update" | "ai_nano" | "ai_mini";

export interface CompactMember {
  id: number;
  name: string;
  role?: string | null;
}

export interface CompactTask {
  id: number;
  title: string;
  status?: string | null;
  assignee_id?: number | null;
  deadline?: string | null;
}

export interface LearnedAlias {
  source_phrase: string;
  canonical_action: string;
  accepted_count: number;
  rejected_count: number;
}

export interface FeedbackExample {
  message_text: string;
  outcome: "accepted" | "rejected" | string;
  similarity: number;
  final_task?: Record<string, unknown> | null;
}

export interface EngineContext {
  profileId: number;
  profileName: string;
  workspaceKind: string;
  directKey?: string | null;
  members: CompactMember[];
  mentionedProfileIds: number[];
  openTasks: CompactTask[];
  createdAt: string;
  timezoneOffsetMinutes: number;
  learnedAliases: LearnedAlias[];
  feedbackExamples: FeedbackExample[];
}

export interface TaskDecision {
  t: boolean;
  c: number;
  a: TaskAction;
  ttl: string;
  d: string;
  as: number | null;
  due: string;
  p: TaskPriority;
  tid: number | null;
  st: TaskStatus;
  r: string;
  l: string;
}

export interface DeadlineResult {
  found: boolean;
  iso: string;
  human: string;
  confidence: number;
  matched: string[];
  dateKind: string;
}

export interface CanonicalCandidate {
  actionKey: string;
  actionTitle: string;
  object: string;
  source: string;
  recipient: "" | "requester";
  title: string;
  description: string;
  confidence: number;
  issues: string[];
}

export interface EngineResult {
  route: EngineRoute;
  reason: string;
  languageHint: string;
  intentConfidence: number;
  canonicalConfidence: number;
  fallbackReason: string;
  decision?: TaskDecision;
  candidate?: CanonicalCandidate;
  modelTaskProbability?: number;
  modelVersion?: string;
}
