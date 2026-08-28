export type Profile = {
  id: number;
  name: string;
  email: string;
  phone?: string | null;
  phone_country_iso?: string | null;
  avatar_url?: string | null;
  about?: string | null;
  role?: string | null;
};

export type Conversation = {
  channel_id: number;
  workspace_id: number;
  kind: 'direct' | 'group' | string;
  name: string;
  description?: string | null;
  avatar_url?: string | null;
  join_code?: string | null;
  member_count?: number;
  last_message?: string | null;
  last_sender_name?: string | null;
  last_message_at?: string | null;
  unread_count?: number;
  is_muted?: boolean;
  is_archived?: boolean;
  current_role?: string;
  only_admins_can_send?: boolean;
  only_admins_can_edit?: boolean;
  approve_new_members?: boolean;
  pending_join_requests?: number;
  is_self_chat?: boolean;
};

export type TaskSuggestion = {
  id: number;
  title: string;
  description?: string | null;
  deadline?: string | null;
  priority?: string;
  status?: string;
  confidence?: number | null;
  action_type?: string;
  target_task_id?: number | null;
  ai_reason?: string | null;
  assignee?: Profile | null;
};

export type MessageReactionRow = { emoji: string; profile_id: number };

export type Message = {
  id: number;
  workspace_id: number;
  channel_id: number;
  body: string;
  type: string;
  created_at: string;
  edited_at?: string | null;
  deleted_at?: string | null;
  mentioned_profile_ids?: number[];
  attachment_bucket?: string | null;
  attachment_path?: string | null;
  attachment_name?: string | null;
  attachment_mime_type?: string | null;
  attachment_size_bytes?: number | null;
  is_pinned?: boolean;
  reply_to_message_id?: number | null;
  forwarded_from_message_id?: number | null;
  shared_contact_profile_id?: number | null;
  shared_contact_name?: string | null;
  shared_contact_phone?: string | null;
  shared_contact_email?: string | null;
  sender: Profile;
  reply_to?: Partial<Message> | null;
  suggestion?: TaskSuggestion | null;
  message_reactions?: MessageReactionRow[];
  client_preview_url?: string | null;
  optimistic?: boolean;
  sending_failed?: boolean;
};

export type Subtask = {
  id: number;
  title: string;
  is_done: boolean;
  position: number;
  version: number;
  created_at?: string;
};

export type TaskComment = {
  id: number;
  body: string;
  created_at?: string;
  user: Profile;
};

export type TaskHistory = {
  id: number;
  from_status?: string | null;
  to_status: string;
  created_at?: string;
  user?: Profile | null;
};

export type TaskAttachment = {
  id: number;
  bucket: string;
  path: string;
  original_name: string;
  mime_type?: string | null;
  size_bytes?: number | null;
  created_at?: string;
  uploaded_by_profile_id?: number | null;
  removed_at?: string | null;
  removed_by_profile_id?: number | null;
};

export type TaskItem = {
  id: number;
  workspace_id: number;
  workspace_name?: string | null;
  workspace_kind?: string | null;
  title: string;
  description?: string | null;
  status: 'todo' | 'in_progress' | 'done' | string;
  priority: 'low' | 'medium' | 'high' | string;
  deadline?: string | null;
  version: number;
  origin_text?: string | null;
  source_type?: string | null;
  reminder_enabled?: boolean;
  reminder_minutes_before?: number;
  created_at?: string;
  updated_at?: string;
  workspace?: { id: number; name: string; kind: string } | null;
  creator: Profile;
  assignee?: Profile | null;
  client?: { id: number; name: string; colour?: string; icon?: string | null } | null;
  channel?: { id: number; name: string; icon?: string | null; workspace_id?: number } | null;
  subtasks?: Subtask[];
  comments?: TaskComment[];
  attachments?: TaskAttachment[];
  status_history?: TaskHistory[];
  tags?: string[];
};

export type TasklyNotification = {
  id: number;
  type: string;
  title: string;
  body: string;
  is_read: boolean;
  created_at: string;
  task_id?: number | null;
  workspace_id?: number | null;
  channel_id?: number | null;
  message_id?: number | null;
  actor?: Profile | null;
};

export type GroupAdminState = {
  workspace?: Record<string, unknown>;
  members?: Array<Record<string, unknown>>;
  join_requests?: Array<Record<string, unknown>>;
  [key: string]: unknown;
};

export type ViewKey = 'chats' | 'tasks' | 'notifications' | 'settings';
export type ThemeChoice = 'system' | 'light' | 'dark';
