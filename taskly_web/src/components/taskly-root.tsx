'use client';

import { AlertCircle } from 'lucide-react';
import { AuthScreen } from './auth-screen';
import { ChatView } from './chat-view';
import { ConversationList } from './conversation-list';
import { NavRail } from './nav-rail';
import { NotificationsView } from './notifications-view';
import { SettingsView } from './settings-view';
import { TasksView } from './tasks-view';
import { Spinner } from './common';
import { TasklyProvider, useTaskly } from '@/lib/taskly-store';

export function TasklyRoot() {
  return <TasklyProvider><TasklyApp /></TasklyProvider>;
}

function TasklyApp() {
  const { authReady, session, view, error, toast, setToast } = useTaskly();
  if (!authReady) return <div className="boot-screen"><img src="/taskly-logo.svg" alt="Taskly" /><Spinner label="Opening Taskly" /></div>;
  if (!session) return <AuthScreen />;
  return <main className="taskly-shell"><NavRail />{view === 'chats' ? <><ConversationList /><ChatView /></> : view === 'tasks' ? <div className="shell-wide"><TasksView /></div> : view === 'notifications' ? <div className="shell-wide"><NotificationsView /></div> : <div className="shell-wide"><SettingsView /></div>}{error ? <div className="global-error"><AlertCircle size={17} /><span>{error}</span></div> : null}{toast ? <button className="toast" onClick={() => setToast(null)}>{toast}</button> : null}</main>;
}
