'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import type { Session } from '@supabase/supabase-js';
import { getSupabase } from './supabase';
import { TasklyApi } from './taskly-api';
import { TasklyCache } from './taskly-cache';
import type {
  Conversation,
  Message,
  Profile,
  TaskAttachment,
  TaskItem,
  TasklyNotification,
  ThemeChoice,
  ViewKey,
} from './taskly-types';
import { disableWebPush, enableWebPush, listenForForegroundPush } from './firebase';

const sortMessages = (rows: Message[]) => [...rows].sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at));

function upsertMessage(rows: Message[], message: Message, replaceId?: number) {
  const result = rows.filter((item) => item.id !== message.id && item.id !== replaceId);
  result.push(message);
  return sortMessages(result);
}

type Store = {
  supabase: ReturnType<typeof getSupabase>;
  api: TasklyApi;
  session: Session | null;
  authReady: boolean;
  profile: Profile | null;
  conversations: Conversation[];
  activeConversation: Conversation | null;
  messages: Message[];
  hasOlderMessages: boolean;
  tasks: TaskItem[];
  activeTask: TaskItem | null;
  notifications: TasklyNotification[];
  view: ViewKey;
  theme: ThemeChoice;
  busy: boolean;
  error: string | null;
  toast: string | null;
  setToast: (value: string | null) => void;
  setView: (view: ViewKey) => void;
  setTheme: (value: ThemeChoice) => void;
  refreshConversations: () => Promise<void>;
  openConversation: (conversation: Conversation) => Promise<void>;
  loadOlderMessages: () => Promise<void>;
  sendMessage: (body: string, replyTo?: Message | null) => Promise<void>;
  sendAttachment: (file: File, replyTo?: Message | null) => Promise<void>;
  refreshMessage: (id: number) => Promise<void>;
  reactMessage: (message: Message, emoji: string) => Promise<void>;
  editMessage: (message: Message, body: string) => Promise<void>;
  deleteMessage: (message: Message) => Promise<void>;
  pinMessage: (message: Message, pinned: boolean) => Promise<void>;
  attachmentUrl: (message: Message) => Promise<string | null>;
  refreshTasks: (background?: boolean) => Promise<void>;
  openTask: (taskOrId: TaskItem | number) => Promise<void>;
  createTask: (values: { title: string; description?: string; priority: string; deadline?: string | null; assigneeId: number; channelId: number }) => Promise<TaskItem>;
  changeTaskStatus: (task: TaskItem, status: string) => Promise<void>;
  addTaskComment: (task: TaskItem, body: string) => Promise<void>;
  addSubtask: (task: TaskItem, title: string) => Promise<void>;
  toggleSubtask: (task: TaskItem, subtaskId: number, done: boolean, version: number) => Promise<void>;
  uploadTaskAttachment: (task: TaskItem, file: File) => Promise<void>;
  removeTaskAttachment: (task: TaskItem, attachment: TaskAttachment) => Promise<void>;
  taskAttachmentUrl: (attachment: TaskAttachment) => Promise<string | null>;
  refreshNotifications: () => Promise<void>;
  markNotificationRead: (item: TasklyNotification) => Promise<void>;
  markAllNotificationsRead: () => Promise<void>;
  enablePush: () => Promise<void>;
  disablePush: () => Promise<void>;
  clearLocalCache: () => Promise<void>;
  logout: () => Promise<void>;
};

const Context = createContext<Store | null>(null);

export function TasklyProvider({ children }: { children: ReactNode }) {
  const supabase = useMemo(() => getSupabase(), []);
  const api = useMemo(() => new TasklyApi(supabase), [supabase]);
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [activeConversation, setActiveConversation] = useState<Conversation | null>(null);
  const [messageMap, setMessageMap] = useState<Record<number, Message[]>>({});
  const [hasOlderMessages, setHasOlderMessages] = useState(false);
  const [tasks, setTasks] = useState<TaskItem[]>([]);
  const [activeTask, setActiveTask] = useState<TaskItem | null>(null);
  const [notifications, setNotifications] = useState<TasklyNotification[]>([]);
  const [view, setView] = useState<ViewKey>('chats');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [theme, setThemeState] = useState<ThemeChoice>('system');
  const activeConversationRef = useRef<Conversation | null>(null);
  const namespaceRef = useRef('anonymous');
  const signedUrls = useRef(new Map<string, { url: string; expires: number }>());
  const conversationRefreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const taskRefreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const messages = activeConversation ? messageMap[activeConversation.channel_id] ?? [] : [];

  useEffect(() => {
    activeConversationRef.current = activeConversation;
  }, [activeConversation]);

  useEffect(() => {
    const stored = localStorage.getItem('taskly-theme') as ThemeChoice | null;
    if (stored === 'system' || stored === 'light' || stored === 'dark') setThemeState(stored);
  }, []);

  useEffect(() => {
    const apply = () => {
      const resolved = theme === 'system'
        ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
        : theme;
      document.documentElement.dataset.theme = resolved;
    };
    apply();
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    media.addEventListener('change', apply);
    localStorage.setItem('taskly-theme', theme);
    return () => media.removeEventListener('change', apply);
  }, [theme]);

  const setTheme = useCallback((value: ThemeChoice) => setThemeState(value), []);

  const refreshConversations = useCallback(async () => {
    try {
      const rows = await api.conversations();
      const self = await api.ensureSelfChat();
      const normalized = [...rows];
      if (self && !normalized.some((item) => item.channel_id === self.channel_id)) normalized.unshift(self);
      else if (self) {
        const index = normalized.findIndex((item) => item.channel_id === self.channel_id);
        const [item] = normalized.splice(index, 1);
        normalized.unshift(item);
      }
      setConversations(normalized);
      await TasklyCache.writeConversations(namespaceRef.current, normalized);
      setActiveConversation((current) => current ? normalized.find((item) => item.channel_id === current.channel_id) ?? current : current);
    } catch (e) {
      setError(String(e));
    }
  }, [api]);

  const refreshTasks = useCallback(async (background = false) => {
    if (!background) setBusy(true);
    try {
      const rows = await api.tasks();
      setTasks(rows);
      await TasklyCache.writeTasks(namespaceRef.current, rows);
      setActiveTask((current) => current ? rows.find((item) => item.id === current.id) ?? current : current);
    } catch (e) {
      setError(String(e));
    } finally {
      if (!background) setBusy(false);
    }
  }, [api]);

  const refreshNotifications = useCallback(async () => {
    try {
      setNotifications(await api.notifications());
    } catch (e) {
      setError(String(e));
    }
  }, [api]);

  const refreshMessage = useCallback(async (id: number) => {
    if (id <= 0) return;
    try {
      const row = await api.message(id);
      if (!row) return;
      setMessageMap((current) => {
        const rows = current[row.channel_id] ?? [];
        const next = upsertMessage(rows, row);
        void TasklyCache.writeMessages(namespaceRef.current, row.channel_id, next);
        return { ...current, [row.channel_id]: next };
      });
    } catch (e) {
      console.warn('TASKLY_WEB_MESSAGE_REFRESH', e);
    }
  }, [api]);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return;
      setSession(data.session);
      setAuthReady(true);
    });
    const { data: subscription } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
      setAuthReady(true);
    });
    return () => {
      mounted = false;
      subscription.subscription.unsubscribe();
    };
  }, [supabase]);

  useEffect(() => {
    if (!session?.user.id) {
      namespaceRef.current = 'anonymous';
      setProfile(null);
      setConversations([]);
      setMessageMap({});
      setTasks([]);
      setNotifications([]);
      setActiveConversation(null);
      setActiveTask(null);
      return;
    }
    const ns = session.user.id;
    namespaceRef.current = ns;
    let cancelled = false;

    void (async () => {
      const [cachedProfile, cachedConversations, cachedTasks] = await Promise.all([
        TasklyCache.profile(ns),
        TasklyCache.conversations(ns),
        TasklyCache.tasks(ns),
      ]);
      if (cancelled) return;
      if (cachedProfile) setProfile(cachedProfile);
      if (cachedConversations?.length) setConversations(cachedConversations);
      if (cachedTasks?.length) setTasks(cachedTasks);
      try {
        const freshProfile = await api.profile();
        if (cancelled) return;
        setProfile(freshProfile);
        await TasklyCache.writeProfile(ns, freshProfile);
        await Promise.all([refreshConversations(), refreshTasks(true), refreshNotifications()]);
      } catch (e) {
        if (!cancelled) setError(String(e));
      }
    })();

    return () => { cancelled = true; };
  }, [session?.user.id, api, refreshConversations, refreshTasks, refreshNotifications]);

  useEffect(() => {
    if (!profile) return;
    const messageChannel = api.subscribeMessages((messageId, channelId) => {
      if (messageId > 0) void refreshMessage(messageId);
      if (conversationRefreshTimer.current) clearTimeout(conversationRefreshTimer.current);
      conversationRefreshTimer.current = setTimeout(() => void refreshConversations(), 120);
      if (channelId && activeConversationRef.current?.channel_id === channelId) void api.markRead(channelId);
    });
    const taskChannel = api.subscribeTasks(() => {
      if (taskRefreshTimer.current) clearTimeout(taskRefreshTimer.current);
      taskRefreshTimer.current = setTimeout(() => void refreshTasks(true), 160);
    });
    const notificationChannel = api.subscribeNotifications(profile.id, () => void refreshNotifications());
    void listenForForegroundPush(() => {
      setToast('New Taskly notification');
      void refreshNotifications();
    }).then((unsubscribe) => {
      // Firebase unsubscribe is intentionally scoped to this signed-in effect.
      (window as any).__tasklyPushUnsubscribe = unsubscribe;
    });

    return () => {
      void supabase.removeChannel(messageChannel);
      void supabase.removeChannel(taskChannel);
      void supabase.removeChannel(notificationChannel);
      const unsubscribe = (window as any).__tasklyPushUnsubscribe;
      if (typeof unsubscribe === 'function') unsubscribe();
      delete (window as any).__tasklyPushUnsubscribe;
    };
  }, [profile?.id, api, supabase, refreshConversations, refreshTasks, refreshNotifications, refreshMessage]);

  const openConversation = useCallback(async (conversation: Conversation) => {
    setActiveConversation(conversation);
    setView('chats');
    setError(null);
    const ns = namespaceRef.current;
    const cached = await TasklyCache.messages(ns, conversation.channel_id);
    if (cached?.length) setMessageMap((current) => ({ ...current, [conversation.channel_id]: cached }));
    try {
      const rows = await api.messages(conversation.channel_id);
      setMessageMap((current) => ({ ...current, [conversation.channel_id]: rows }));
      setHasOlderMessages(rows.length >= 80);
      await TasklyCache.writeMessages(ns, conversation.channel_id, rows);
      void api.markRead(conversation.channel_id);
      setConversations((current) => current.map((item) => item.channel_id === conversation.channel_id ? { ...item, unread_count: 0 } : item));
    } catch (e) {
      if (!cached?.length) setError(String(e));
    }
  }, [api]);

  const loadOlderMessages = useCallback(async () => {
    const conversation = activeConversationRef.current;
    if (!conversation) return;
    const current = messageMap[conversation.channel_id] ?? [];
    const ids = current.map((item) => item.id).filter((id) => id > 0);
    if (!ids.length) return;
    const beforeId = Math.min(...ids);
    const older = await api.messages(conversation.channel_id, beforeId, 80);
    setHasOlderMessages(older.length >= 80);
    const known = new Set(current.map((item) => item.id));
    const next = sortMessages([...older.filter((item) => !known.has(item.id)), ...current]);
    setMessageMap((state) => ({ ...state, [conversation.channel_id]: next }));
    await TasklyCache.writeMessages(namespaceRef.current, conversation.channel_id, next);
  }, [api, messageMap]);

  const sendMessage = useCallback(async (body: string, replyTo?: Message | null) => {
    const conversation = activeConversationRef.current;
    const me = profile;
    const clean = body.trim();
    if (!conversation || !me || !clean) return;
    const optimisticId = -Date.now();
    const optimistic: Message = {
      id: optimisticId,
      workspace_id: conversation.workspace_id,
      channel_id: conversation.channel_id,
      body: clean,
      type: 'text',
      created_at: new Date().toISOString(),
      sender: me,
      reply_to_message_id: replyTo?.id ?? null,
      reply_to: replyTo ?? null,
      message_reactions: [],
      optimistic: true,
    };
    setMessageMap((current) => ({
      ...current,
      [conversation.channel_id]: upsertMessage(current[conversation.channel_id] ?? [], optimistic),
    }));
    try {
      const inserted = await api.sendMessage({
        workspaceId: conversation.workspace_id,
        channelId: conversation.channel_id,
        profile: me,
        body: clean,
        replyToMessageId: replyTo?.id,
      });
      setMessageMap((current) => {
        const next = upsertMessage(current[conversation.channel_id] ?? [], inserted, optimisticId);
        void TasklyCache.writeMessages(namespaceRef.current, conversation.channel_id, next);
        return { ...current, [conversation.channel_id]: next };
      });
      setConversations((current) => current.map((item) => item.channel_id === conversation.channel_id ? {
        ...item,
        last_message: clean,
        last_sender_name: me.name,
        last_message_at: inserted.created_at,
      } : item));
      void api.analyseMessage(inserted.id)
        .then(() => new Promise((resolve) => setTimeout(resolve, 200)))
        .then(() => refreshMessage(inserted.id))
        .catch((e) => console.warn('TASKLY_WEB_AI', e));
    } catch (e) {
      setMessageMap((current) => ({
        ...current,
        [conversation.channel_id]: (current[conversation.channel_id] ?? []).map((item) => item.id === optimisticId ? { ...item, optimistic: false, sending_failed: true } : item),
      }));
      setError(String(e));
    }
  }, [api, profile, refreshMessage]);

  const sendAttachment = useCallback(async (file: File, replyTo?: Message | null) => {
    const conversation = activeConversationRef.current;
    const me = profile;
    if (!conversation || !me) return;
    const optimisticId = -Date.now();
    const previewUrl = file.type.startsWith('image/') || file.type.startsWith('video/') ? URL.createObjectURL(file) : null;
    const optimistic: Message = {
      id: optimisticId,
      workspace_id: conversation.workspace_id,
      channel_id: conversation.channel_id,
      body: file.name,
      type: file.type.startsWith('image/') ? 'image' : file.type.startsWith('video/') ? 'video' : 'file',
      created_at: new Date().toISOString(),
      sender: me,
      attachment_name: file.name,
      attachment_mime_type: file.type || 'application/octet-stream',
      attachment_size_bytes: file.size,
      client_preview_url: previewUrl,
      optimistic: true,
      message_reactions: [],
      reply_to: replyTo ?? null,
      reply_to_message_id: replyTo?.id ?? null,
    };
    setMessageMap((current) => ({ ...current, [conversation.channel_id]: upsertMessage(current[conversation.channel_id] ?? [], optimistic) }));
    try {
      const inserted = await api.uploadMessageAttachment({ conversation, profile: me, file, replyToMessageId: replyTo?.id });
      if (previewUrl) URL.revokeObjectURL(previewUrl);
      setMessageMap((current) => {
        const next = upsertMessage(current[conversation.channel_id] ?? [], inserted, optimisticId);
        void TasklyCache.writeMessages(namespaceRef.current, conversation.channel_id, next);
        return { ...current, [conversation.channel_id]: next };
      });
    } catch (e) {
      setMessageMap((current) => ({ ...current, [conversation.channel_id]: (current[conversation.channel_id] ?? []).map((item) => item.id === optimisticId ? { ...item, optimistic: false, sending_failed: true } : item) }));
      setError(String(e));
    }
  }, [api, profile]);

  const reactMessage = useCallback(async (message: Message, emoji: string) => {
    await api.toggleReaction(message.id, emoji);
    await refreshMessage(message.id);
  }, [api, refreshMessage]);

  const editMessage = useCallback(async (message: Message, body: string) => {
    await api.editMessage(message.id, body);
    await refreshMessage(message.id);
  }, [api, refreshMessage]);

  const deleteMessage = useCallback(async (message: Message) => {
    await api.deleteMessage(message.id);
    await refreshMessage(message.id);
  }, [api, refreshMessage]);

  const pinMessage = useCallback(async (message: Message, pinned: boolean) => {
    await api.togglePin(message.id, pinned);
    await refreshMessage(message.id);
  }, [api, refreshMessage]);

  const signedUrlFor = useCallback(async (bucket: string, path: string) => {
    const cacheKey = `${bucket}:${path}`;
    const cached = signedUrls.current.get(cacheKey);
    if (cached && cached.expires > Date.now()) return cached.url;
    const url = await api.signedUrl(bucket, path, 3600);
    signedUrls.current.set(cacheKey, { url, expires: Date.now() + 50 * 60 * 1000 });
    return url;
  }, [api]);

  const attachmentUrl = useCallback(async (message: Message) => {
    if (message.client_preview_url) return message.client_preview_url;
    if (!message.attachment_path) return null;
    return signedUrlFor(message.attachment_bucket || 'task-files', message.attachment_path);
  }, [signedUrlFor]);

  const openTask = useCallback(async (taskOrId: TaskItem | number) => {
    const id = typeof taskOrId === 'number' ? taskOrId : taskOrId.id;
    setView('tasks');
    if (typeof taskOrId !== 'number') setActiveTask(taskOrId);
    try {
      const full = await api.task(id);
      setActiveTask(full);
      setTasks((current) => current.map((item) => item.id === full.id ? { ...item, ...full } : item));
    } catch (e) {
      setError(String(e));
    }
  }, [api]);

  const createTask = useCallback(async (values: { title: string; description?: string; priority: string; deadline?: string | null; assigneeId: number; channelId: number }) => {
    const task = await api.createTask(values);
    setTasks((current) => [task, ...current.filter((item) => item.id !== task.id)]);
    setActiveTask(task);
    return task;
  }, [api]);

  const replaceTask = useCallback((task: TaskItem) => {
    setActiveTask((current) => current?.id === task.id ? task : current);
    setTasks((current) => current.map((item) => item.id === task.id ? { ...item, ...task } : item));
  }, []);

  const changeTaskStatus = useCallback(async (task: TaskItem, status: string) => replaceTask(await api.updateTaskStatus(task.id, status)), [api, replaceTask]);
  const addTaskComment = useCallback(async (task: TaskItem, body: string) => replaceTask(await api.addComment(task.id, body)), [api, replaceTask]);
  const addSubtask = useCallback(async (task: TaskItem, title: string) => replaceTask(await api.addSubtask(task.id, title)), [api, replaceTask]);
  const toggleSubtask = useCallback(async (task: TaskItem, subtaskId: number, done: boolean, version: number) => replaceTask(await api.toggleSubtask(task.id, subtaskId, done, version)), [api, replaceTask]);
  const uploadTaskAttachment = useCallback(async (task: TaskItem, file: File) => replaceTask(await api.uploadTaskAttachment(task, file)), [api, replaceTask]);
  const removeTaskAttachment = useCallback(async (task: TaskItem, attachment: TaskAttachment) => replaceTask(await api.removeTaskAttachment(task.id, attachment)), [api, replaceTask]);
  const taskAttachmentUrl = useCallback(async (attachment: TaskAttachment) => {
    if (attachment.removed_at) return null;
    return signedUrlFor(attachment.bucket || 'task-files', attachment.path);
  }, [signedUrlFor]);

  const markNotificationRead = useCallback(async (item: TasklyNotification) => {
    if (!item.is_read) await api.markNotificationRead(item.id);
    setNotifications((current) => current.map((row) => row.id === item.id ? { ...row, is_read: true } : row));
    if (item.channel_id) {
      const conversation = conversations.find((row) => row.channel_id === item.channel_id);
      if (conversation) await openConversation(conversation);
    }
    if (item.task_id) await openTask(item.task_id);
  }, [api, conversations, openConversation, openTask]);

  const markAllNotificationsRead = useCallback(async () => {
    await api.markAllNotificationsRead();
    setNotifications((current) => current.map((item) => ({ ...item, is_read: true })));
  }, [api]);

  const enablePush = useCallback(async () => {
    await enableWebPush(supabase);
    setToast('Desktop notifications enabled');
  }, [supabase]);

  const disablePush = useCallback(async () => {
    await disableWebPush(supabase);
    setToast('Desktop notifications disabled');
  }, [supabase]);

  const clearLocalCache = useCallback(async () => {
    await TasklyCache.clearNamespace(namespaceRef.current);
    setMessageMap({});
    signedUrls.current.clear();
    setToast('Local Taskly cache cleared. Server data was not deleted.');
  }, []);

  const logout = useCallback(async () => {
    try { await disableWebPush(supabase); } catch {}
    await supabase.auth.signOut();
  }, [supabase]);

  const value: Store = {
    supabase,
    api,
    session,
    authReady,
    profile,
    conversations,
    activeConversation,
    messages,
    hasOlderMessages,
    tasks,
    activeTask,
    notifications,
    view,
    theme,
    busy,
    error,
    toast,
    setToast,
    setView,
    setTheme,
    refreshConversations,
    openConversation,
    loadOlderMessages,
    sendMessage,
    sendAttachment,
    refreshMessage,
    reactMessage,
    editMessage,
    deleteMessage,
    pinMessage,
    attachmentUrl,
    refreshTasks,
    openTask,
    createTask,
    changeTaskStatus,
    addTaskComment,
    addSubtask,
    toggleSubtask,
    uploadTaskAttachment,
    removeTaskAttachment,
    taskAttachmentUrl,
    refreshNotifications,
    markNotificationRead,
    markAllNotificationsRead,
    enablePush,
    disablePush,
    clearLocalCache,
    logout,
  };

  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useTaskly() {
  const value = useContext(Context);
  if (!value) throw new Error('useTaskly must be used inside TasklyProvider');
  return value;
}
