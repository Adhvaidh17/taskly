'use client';

import { Bell, CheckCheck } from 'lucide-react';
import { useTaskly } from '@/lib/taskly-store';
import { Avatar, EmptyState, fmtDay } from './common';

export function NotificationsView() {
  const { notifications, markNotificationRead, markAllNotificationsRead } = useTaskly();
  const unread = notifications.filter((item) => !item.is_read).length;
  return <section className="single-panel-page"><header className="page-head"><div><span className="panel-kicker">Activity</span><h1>Notifications</h1><p>{unread ? `${unread} unread` : 'You are all caught up'}</p></div>{unread ? <button className="secondary-button" onClick={() => void markAllNotificationsRead()}><CheckCheck size={16} /> Mark all read</button> : null}</header><div className="notification-list">{notifications.map((item) => <button key={item.id} className={`notification-row ${!item.is_read ? 'unread' : ''}`} onClick={() => void markNotificationRead(item)}><Avatar user={item.actor} name="Taskly" size={40} /><span><span className="notification-title"><strong>{item.title}</strong><time>{fmtDay(item.created_at)}</time></span><p>{item.body}</p><small>{item.type.replaceAll('_', ' ')}</small></span></button>)}{!notifications.length ? <EmptyState icon={<Bell size={28} />} title="No notifications yet" text="Task and chat activity will appear here." /> : null}</div></section>;
}
