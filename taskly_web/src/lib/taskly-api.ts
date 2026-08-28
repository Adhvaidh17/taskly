'use client';

import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import { TASKLY_CONTRACT } from '@/generated/taskly-contract';
import type {
  Conversation,
  GroupAdminState,
  Message,
  Profile,
  TaskAttachment,
  TaskItem,
  TasklyNotification,
} from './taskly-types';

const TASK_LIST_SELECT = `
  id,workspace_id,title,status,priority,deadline,version,created_at,updated_at,
  workspace:workspaces!tasks_workspace_id_fkey(id,name,kind),
  creator:profiles!tasks_creator_profile_id_fkey(id,name,email,phone,avatar_url,about),
  assignee:profiles!tasks_assignee_id_fkey(id,name,email,phone,avatar_url,about),
  client:clients!tasks_client_id_fkey(id,name,colour,icon),
  channel:channels!tasks_channel_id_fkey(id,name,icon,workspace_id),
  subtasks(id,title,is_done,position,version)
`;

const TASK_DETAIL_SELECT = `
  id,workspace_id,title,description,status,priority,deadline,origin_text,source_type,
  reminder_enabled,reminder_minutes_before,version,created_at,updated_at,
  workspace:workspaces!tasks_workspace_id_fkey(id,name,kind),
  creator:profiles!tasks_creator_profile_id_fkey(id,name,email,phone,avatar_url,about),
  assignee:profiles!tasks_assignee_id_fkey(id,name,email,phone,avatar_url,about),
  client:clients!tasks_client_id_fkey(id,name,colour,icon),
  channel:channels!tasks_channel_id_fkey(id,name,icon,workspace_id),
  subtasks(id,title,is_done,position,version,created_at),
  task_comments(id,body,created_at,user:profiles!task_comments_profile_id_fkey(id,name,email,phone,avatar_url,about)),
  task_status_histories(id,from_status,to_status,created_at,user:profiles!task_status_histories_changed_by_profile_id_fkey(id,name,email,phone,avatar_url,about)),
  attachments(id,bucket,path,original_name,mime_type,size_bytes,created_at,uploaded_by_profile_id,removed_at,removed_by_profile_id),
  task_tags(tags(name))
`;

const MESSAGE_BASE_SELECT = `
  id,workspace_id,channel_id,body,type,created_at,edited_at,deleted_at,
  mentioned_profile_ids,attachment_bucket,attachment_path,attachment_name,
  attachment_mime_type,attachment_size_bytes,is_pinned,reply_to_message_id,
  forwarded_from_message_id,shared_contact_profile_id,shared_contact_name,
  shared_contact_phone,shared_contact_email
`;

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

function normalizeTask(row: Record<string, any>): TaskItem {
  const workspace = row.workspace && typeof row.workspace === 'object' ? row.workspace : {};
  const links = Array.isArray(row.task_tags) ? row.task_tags : [];
  return {
    ...(row as TaskItem),
    workspace_name: row.workspace_name ?? workspace.name ?? null,
    workspace_kind: row.workspace_kind ?? workspace.kind ?? null,
    comments: asArray(row.task_comments),
    status_history: asArray(row.task_status_histories),
    tags: links
      .map((item: any) => item?.tags?.name)
      .filter((value: unknown): value is string => typeof value === 'string' && value.length > 0),
  };
}

async function throwIf<T>(result: { data: T; error: any }): Promise<T> {
  if (result.error) throw result.error;
  return result.data;
}

export class TasklyApi {
  constructor(readonly supabase: SupabaseClient) {}

  async profile(): Promise<Profile> {
    const user = this.supabase.auth.getUser();
    const { data: authData, error: authError } = await user;
    if (authError) throw authError;
    if (!authData.user) throw new Error('Not signed in');
    return throwIf(
      await this.supabase
        .from('profiles')
        .select('id,name,email,phone,phone_country_iso,avatar_url,about,last_seen_at')
        .eq('auth_user_id', authData.user.id)
        .single(),
    ) as Promise<Profile>;
  }

  async updateProfile(values: Partial<Profile>): Promise<Profile> {
    const { data: authData, error: authError } = await this.supabase.auth.getUser();
    if (authError) throw authError;
    if (!authData.user) throw new Error('Not signed in');
    return throwIf(
      await this.supabase
        .from('profiles')
        .update({
          name: values.name?.trim(),
          phone: values.phone?.trim() || null,
          about: values.about?.trim() || null,
          last_seen_at: new Date().toISOString(),
        })
        .eq('auth_user_id', authData.user.id)
        .select('id,name,email,phone,phone_country_iso,avatar_url,about,last_seen_at')
        .single(),
    ) as Promise<Profile>;
  }

  async conversations(): Promise<Conversation[]> {
    const data = await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.listConversations));
    return asArray<Conversation>(data);
  }

  async ensureSelfChat(): Promise<Conversation | null> {
    const { data, error } = await this.supabase.rpc(TASKLY_CONTRACT.rpc.ensureSelfChat);
    if (error) return null;
    return data && typeof data === 'object' ? (data as Conversation) : null;
  }

  async members(channelId: number): Promise<Profile[]> {
    const data = await throwIf(
      await this.supabase.rpc(TASKLY_CONTRACT.rpc.conversationMembers, { p_channel_id: channelId }),
    );
    return asArray<Profile>(data);
  }

  async startDirectChat(profileId: number): Promise<Conversation> {
    const data = await throwIf(
      await this.supabase.rpc(TASKLY_CONTRACT.rpc.getOrCreateDirectChat, { p_other_profile_id: profileId }),
    );
    return data as Conversation;
  }

  async messages(channelId: number, beforeId?: number, limit = 80): Promise<Message[]> {
    const data = await throwIf(
      await this.supabase.rpc(TASKLY_CONTRACT.rpc.channelMessages, {
        p_channel_id: channelId,
        p_before_id: beforeId ?? null,
        p_limit: Math.max(20, Math.min(120, limit)),
      }),
    );
    return asArray<Message>(data);
  }

  async message(messageId: number): Promise<Message | null> {
    const data = await throwIf(
      await this.supabase.rpc(TASKLY_CONTRACT.rpc.oneMessage, { p_message_id: messageId }),
    );
    return data && typeof data === 'object' ? (data as Message) : null;
  }

  async sendMessage(input: {
    workspaceId: number;
    channelId: number;
    profile: Profile;
    body: string;
    replyToMessageId?: number | null;
  }): Promise<Message> {
    const inserted = await throwIf(
      await this.supabase
        .from('messages')
        .insert({
          workspace_id: input.workspaceId,
          channel_id: input.channelId,
          sender_profile_id: input.profile.id,
          body: input.body.trim(),
          type: 'text',
          mentioned_profile_ids: [],
          reply_to_message_id: input.replyToMessageId ?? null,
          client_mutation_id: crypto.randomUUID(),
        })
        .select(MESSAGE_BASE_SELECT)
        .single(),
    );
    return {
      ...(inserted as Record<string, any>),
      sender: input.profile,
      reply_to: null,
      suggestion: null,
      message_reactions: [],
    } as Message;
  }

  async analyseMessage(messageId: number) {
    const { data, error } = await this.supabase.functions.invoke(TASKLY_CONTRACT.functions.analyseTaskMessage, {
      body: {
        message_id: messageId,
        timezone_offset_minutes: -new Date().getTimezoneOffset(),
      },
    });
    if (error) throw error;
    return data as Record<string, unknown> | null;
  }

  async confirmSuggestion(id: number) {
    return throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.confirmSuggestion, { p_suggestion_id: id }));
  }

  async dismissSuggestion(id: number) {
    return throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.dismissSuggestion, { p_suggestion_id: id }));
  }

  async editMessage(id: number, body: string) {
    await throwIf(
      await this.supabase.from('messages').update({ body: body.trim(), edited_at: new Date().toISOString() }).eq('id', id),
    );
  }

  async deleteMessage(id: number) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.deleteMessage, { p_message_id: id }));
  }

  async togglePin(id: number, pinned: boolean) {
    await throwIf(await this.supabase.from('messages').update({ is_pinned: pinned }).eq('id', id));
  }

  async toggleReaction(id: number, emoji: string) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.toggleReaction, { p_message_id: id, p_emoji: emoji }));
  }

  async markRead(channelId: number) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.markChannelRead, { p_channel_id: channelId }));
  }

  async uploadMessageAttachment(input: {
    conversation: Conversation;
    profile: Profile;
    file: File;
    replyToMessageId?: number | null;
  }): Promise<Message> {
    const path = `${input.conversation.workspace_id}/messages/${input.conversation.channel_id}/${crypto.randomUUID()}-${input.file.name}`;
    await throwIf(
      await this.supabase.storage.from(TASKLY_CONTRACT.storageBucket).upload(path, input.file, {
        contentType: input.file.type || 'application/octet-stream',
        upsert: false,
      }),
    );
    const inserted = await throwIf(
      await this.supabase
        .from('messages')
        .insert({
          workspace_id: input.conversation.workspace_id,
          channel_id: input.conversation.channel_id,
          sender_profile_id: input.profile.id,
          body: input.file.name,
          type: input.file.type.startsWith('image/') ? 'image' : input.file.type.startsWith('video/') ? 'video' : 'file',
          reply_to_message_id: input.replyToMessageId ?? null,
          attachment_bucket: TASKLY_CONTRACT.storageBucket,
          attachment_path: path,
          attachment_name: input.file.name,
          attachment_mime_type: input.file.type || 'application/octet-stream',
          attachment_size_bytes: input.file.size,
          client_mutation_id: crypto.randomUUID(),
        })
        .select(MESSAGE_BASE_SELECT)
        .single(),
    );
    return {
      ...(inserted as Record<string, any>),
      sender: input.profile,
      reply_to: null,
      suggestion: null,
      message_reactions: [],
    } as Message;
  }

  async signedUrl(bucket: string, path: string, expiresIn = 3600) {
    const { data, error } = await this.supabase.storage.from(bucket).createSignedUrl(path, expiresIn);
    if (error) throw error;
    return data.signedUrl;
  }

  async groupSharedContent(channelId: number, kind: 'media' | 'documents' | 'links', limit = 100) {
    const data = await throwIf(
      await this.supabase.rpc(TASKLY_CONTRACT.rpc.groupSharedContent, {
        p_channel_id: channelId,
        p_kind: kind,
        p_before_id: null,
        p_limit: Math.max(7, Math.min(100, limit)),
      }),
    );
    return asArray<Message>(data);
  }

  async groupAdminState(workspaceId: number): Promise<GroupAdminState> {
    const data = await throwIf(
      await this.supabase.rpc(TASKLY_CONTRACT.rpc.groupAdminState, { p_workspace_id: workspaceId }),
    );
    return (data ?? {}) as GroupAdminState;
  }

  async setConversationPreferences(channelId: number, muted?: boolean, archived?: boolean) {
    await throwIf(
      await this.supabase.rpc(TASKLY_CONTRACT.rpc.setConversationPreferences, {
        p_channel_id: channelId,
        p_is_muted: muted ?? null,
        p_is_archived: archived ?? null,
      }),
    );
  }

  async clearChat(channelId: number) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.clearChat, { p_channel_id: channelId }));
  }

  async deleteChat(channelId: number) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.deleteChat, { p_channel_id: channelId }));
  }

  async leaveGroup(workspaceId: number) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.leaveGroup, { p_workspace_id: workspaceId }));
  }

  async deleteGroup(workspaceId: number) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.deleteGroup, { p_workspace_id: workspaceId }));
  }

  async tasks(): Promise<TaskItem[]> {
    const data = await throwIf(
      await this.supabase
        .from('tasks')
        .select(TASK_LIST_SELECT)
        .is('deleted_at', null)
        .order('deadline', { ascending: true, nullsFirst: false })
        .order('created_at', { ascending: false })
        .limit(200),
    );
    return asArray<Record<string, any>>(data).map(normalizeTask);
  }

  async task(id: number): Promise<TaskItem> {
    const data = await throwIf(await this.supabase.from('tasks').select(TASK_DETAIL_SELECT).eq('id', id).single());
    return normalizeTask(data as Record<string, any>);
  }

  async createTask(values: {
    title: string;
    description?: string;
    priority: string;
    deadline?: string | null;
    assigneeId: number;
    channelId: number;
  }): Promise<TaskItem> {
    const channel = await throwIf(
      await this.supabase.from('channels').select('workspace_id').eq('id', values.channelId).single(),
    );
    const me = await this.profile();
    const row = await throwIf(
      await this.supabase
        .from('tasks')
        .insert({
          workspace_id: (channel as any).workspace_id,
          title: values.title.trim(),
          description: values.description?.trim() || null,
          status: 'todo',
          priority: values.priority,
          deadline: values.deadline ?? null,
          assignee_id: values.assigneeId,
          channel_id: values.channelId,
          creator_profile_id: me.id,
          source_type: 'manual',
          reminder_enabled: Boolean(values.deadline),
          reminder_minutes_before: 15,
          client_mutation_id: crypto.randomUUID(),
        })
        .select('id')
        .single(),
    );
    return this.task(Number((row as any).id));
  }

  async updateTaskStatus(id: number, status: string) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.changeTaskStatus, { p_task_id: id, p_status: status }));
    return this.task(id);
  }

  async addComment(taskId: number, body: string) {
    const me = await this.profile();
    await throwIf(
      await this.supabase.from('task_comments').insert({
        task_id: taskId,
        profile_id: me.id,
        body: body.trim(),
        client_mutation_id: crypto.randomUUID(),
      }),
    );
    return this.task(taskId);
  }

  async addSubtask(taskId: number, title: string) {
    const { data: positions, error } = await this.supabase
      .from('subtasks')
      .select('position')
      .eq('task_id', taskId)
      .order('position', { ascending: false })
      .limit(1);
    if (error) throw error;
    const position = positions?.length ? Number(positions[0].position) + 1 : 0;
    await throwIf(
      await this.supabase.from('subtasks').insert({
        task_id: taskId,
        title: title.trim(),
        position,
        client_mutation_id: crypto.randomUUID(),
      }),
    );
    return this.task(taskId);
  }

  async toggleSubtask(taskId: number, subtaskId: number, done: boolean, version: number) {
    await throwIf(
      await this.supabase
        .from('subtasks')
        .update({ is_done: done, version: version + 1, completed_at: done ? new Date().toISOString() : null })
        .eq('id', subtaskId),
    );
    return this.task(taskId);
  }

  async uploadTaskAttachment(task: TaskItem, file: File) {
    const path = `${task.workspace_id}/tasks/${task.id}/${crypto.randomUUID()}-${file.name}`;
    await throwIf(
      await this.supabase.storage.from(TASKLY_CONTRACT.storageBucket).upload(path, file, {
        contentType: file.type || 'application/octet-stream',
        upsert: false,
      }),
    );
    const me = await this.profile();
    await throwIf(
      await this.supabase.from('attachments').insert({
        workspace_id: task.workspace_id,
        task_id: task.id,
        uploaded_by_profile_id: me.id,
        bucket: TASKLY_CONTRACT.storageBucket,
        path,
        original_name: file.name,
        mime_type: file.type || 'application/octet-stream',
        size_bytes: file.size,
      }),
    );
    return this.task(task.id);
  }

  async removeTaskAttachment(taskId: number, attachment: TaskAttachment) {
    const { error } = await this.supabase.functions.invoke(TASKLY_CONTRACT.functions.removeTaskAttachment, {
      body: { attachment_id: attachment.id },
    });
    if (error) throw error;
    return this.task(taskId);
  }

  async notifications(): Promise<TasklyNotification[]> {
    const data = await throwIf(
      await this.supabase
        .from('notifications')
        .select(`id,type,title,body,is_read,created_at,task_id,workspace_id,channel_id,message_id,
          actor:profiles!notifications_actor_profile_id_fkey(id,name,email,phone,avatar_url,about)`)
        .order('created_at', { ascending: false })
        .limit(100),
    );
    return asArray<TasklyNotification>(data);
  }

  async markNotificationRead(id: number) {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.markNotificationRead, { p_notification_id: id }));
  }

  async markAllNotificationsRead() {
    await throwIf(await this.supabase.rpc(TASKLY_CONTRACT.rpc.markAllNotificationsRead));
  }

  subscribeMessages(onChange: (messageId: number, channelId: number) => void): RealtimeChannel {
    return this.supabase
      .channel(`taskly-web-messages-${crypto.randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'messages' }, (payload) => {
        const row = (Object.keys(payload.new ?? {}).length ? payload.new : payload.old) as Record<string, any>;
        onChange(Number(row.id || 0), Number(row.channel_id || 0));
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'task_suggestions' }, (payload) => {
        const row = (Object.keys(payload.new ?? {}).length ? payload.new : payload.old) as Record<string, any>;
        onChange(Number(row.message_id || 0), 0);
      })
      .subscribe();
  }

  subscribeTasks(onChange: () => void): RealtimeChannel {
    return this.supabase
      .channel(`taskly-web-tasks-${crypto.randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks' }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'subtasks' }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'task_comments' }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'attachments' }, onChange)
      .subscribe();
  }

  subscribeNotifications(profileId: number, onChange: () => void): RealtimeChannel {
    return this.supabase
      .channel(`taskly-web-notifications-${profileId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'notifications', filter: `profile_id=eq.${profileId}` },
        onChange,
      )
      .subscribe();
  }
}
