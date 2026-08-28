'use client';

import { Bell, CheckSquare, LogOut, MessageCircle, MoonStar, Settings, SunMedium } from 'lucide-react';
import { Avatar, IconButton } from './common';
import { useTaskly } from '@/lib/taskly-store';
import type { ViewKey } from '@/lib/taskly-types';

export function NavRail() {
  const { profile, view, setView, notifications, theme, setTheme, logout } = useTaskly();
  const unread = notifications.filter((item) => !item.is_read).length;
  const items: Array<{ key: ViewKey; label: string; icon: React.ReactNode; badge?: number }> = [
    { key: 'chats', label: 'Chats', icon: <MessageCircle size={22} /> },
    { key: 'tasks', label: 'Tasks', icon: <CheckSquare size={22} /> },
    { key: 'notifications', label: 'Notifications', icon: <Bell size={22} />, badge: unread },
    { key: 'settings', label: 'Settings', icon: <Settings size={22} /> },
  ];
  return (
    <aside className="nav-rail">
      <div className="rail-brand"><img src="/taskly-logo.svg" alt="Taskly" /></div>
      <nav>
        {items.map((item) => (
          <button key={item.key} className={`rail-item ${view === item.key ? 'active' : ''}`} onClick={() => setView(item.key)} title={item.label}>
            <span className="rail-icon">{item.icon}{item.badge ? <span className="rail-badge">{item.badge > 99 ? '99+' : item.badge}</span> : null}</span>
            <span>{item.label}</span>
          </button>
        ))}
      </nav>
      <div className="rail-bottom">
        <IconButton label="Toggle theme" onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}>{theme === 'dark' ? <SunMedium size={20} /> : <MoonStar size={20} />}</IconButton>
        <IconButton label="Log out" onClick={() => void logout()}><LogOut size={20} /></IconButton>
        <Avatar user={profile} size={34} />
      </div>
    </aside>
  );
}
