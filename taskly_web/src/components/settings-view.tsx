'use client';

import { BellRing, Database, HelpCircle, LogOut, Monitor, Moon, ShieldCheck, Smartphone, Sun, UserRound } from 'lucide-react';
import { useState } from 'react';
import { useTaskly } from '@/lib/taskly-store';
import { Avatar } from './common';

export function SettingsView() {
  const { profile, theme, setTheme, enablePush, disablePush, clearLocalCache, logout, api } = useTaskly();
  const [section, setSection] = useState('profile');
  const [name, setName] = useState(profile?.name || '');
  const [phone, setPhone] = useState(profile?.phone || '');
  const [about, setAbout] = useState(profile?.about || '');
  const [message, setMessage] = useState<string | null>(null);
  const items = [
    ['profile', <UserRound size={19} key="i" />, 'Profile'],
    ['appearance', <Monitor size={19} key="i" />, 'Appearance'],
    ['notifications', <BellRing size={19} key="i" />, 'Notifications'],
    ['storage', <Database size={19} key="i" />, 'Storage & data'],
    ['privacy', <ShieldCheck size={19} key="i" />, 'Privacy'],
    ['help', <HelpCircle size={19} key="i" />, 'Help'],
  ];

  return <section className="settings-workspace"><aside className="settings-menu"><header><span className="panel-kicker">Taskly</span><h1>Settings</h1></header><div className="settings-profile-mini"><Avatar user={profile} size={46} /><span><strong>{profile?.name}</strong><small>{profile?.email || profile?.phone}</small></span></div><nav>{items.map(([key, icon, label]) => <button key={String(key)} className={section === key ? 'active' : ''} onClick={() => setSection(String(key))}>{icon}<span>{label}</span></button>)}</nav><button className="settings-logout" onClick={() => void logout()}><LogOut size={18} /> Log out</button></aside><main className="settings-content">{section === 'profile' ? <SettingsSection title="Profile" subtitle="This profile is shared with Taskly mobile."><div className="profile-editor"><Avatar user={profile} size={78} /><div className="form-stack"><label className="field"><span>Name</span><input value={name} onChange={(e) => setName(e.target.value)} /></label><label className="field"><span>Phone</span><input value={phone} onChange={(e) => setPhone(e.target.value)} /></label><label className="field"><span>About</span><input value={about} onChange={(e) => setAbout(e.target.value)} placeholder="Available, at work…" /></label><button className="primary-button align-start" onClick={() => void api.updateProfile({ name, phone, about }).then(() => setMessage('Profile updated')).catch((e) => setMessage(String(e)))}>Save profile</button></div></div></SettingsSection> : null}{section === 'appearance' ? <SettingsSection title="Appearance" subtitle="The choice is stored on this browser."><div className="choice-grid">{[['system', <Monitor size={22} key="i" />, 'System default'], ['light', <Sun size={22} key="i" />, 'Light'], ['dark', <Moon size={22} key="i" />, 'Dark']].map(([key, icon, label]) => <button key={String(key)} className={theme === key ? 'active' : ''} onClick={() => setTheme(key as any)}>{icon}<strong>{label}</strong><span>{theme === key ? 'Selected' : ''}</span></button>)}</div></SettingsSection> : null}{section === 'notifications' ? <SettingsSection title="Notifications" subtitle="Firebase Web Push uses the same Taskly notification rows as mobile."><div className="setting-card"><BellRing size={22} /><div><strong>Desktop notifications</strong><p>Receive chat and task notifications when this browser is in the background.</p></div><div className="setting-actions"><button className="primary-button" onClick={() => void enablePush().catch((e) => setMessage(String(e)))}>Enable</button><button className="secondary-button" onClick={() => void disablePush().catch((e) => setMessage(String(e)))}>Disable</button></div></div></SettingsSection> : null}{section === 'storage' ? <SettingsSection title="Storage & data" subtitle="Web messages are cached in IndexedDB for instant chat opening."><div className="setting-card"><Database size={22} /><div><strong>Local browser cache</strong><p>Clearing this removes cached conversations, messages and task lists from this browser only. Supabase data and Storage files are not deleted.</p></div><button className="secondary-button" onClick={() => void clearLocalCache()}>Clear cache</button></div></SettingsSection> : null}{section === 'privacy' ? <SettingsSection title="Privacy" subtitle="Database access is enforced by your existing Supabase RLS policies."><div className="setting-card"><ShieldCheck size={22} /><div><strong>Same permissions as mobile</strong><p>Taskly Web uses the authenticated user's token. It never contains the service-role key or Firebase service-account credential.</p></div></div><div className="setting-card"><Smartphone size={22} /><div><strong>Linked-device style architecture</strong><p>This browser is an independent client of the same Taskly backend. QR device linking can be added later without changing the data model.</p></div></div></SettingsSection> : null}{section === 'help' ? <SettingsSection title="Help" subtitle="Taskly Web desktop companion."><div className="setting-card"><HelpCircle size={22} /><div><strong>Web address</strong><p>https://taskly.madrascreatives.com</p></div></div></SettingsSection> : null}{message ? <div className="settings-message">{message}<button onClick={() => setMessage(null)}>×</button></div> : null}</main></section>;
}

function SettingsSection({ title, subtitle, children }: { title: string; subtitle: string; children: React.ReactNode }) {
  return <section className="settings-section"><header><h2>{title}</h2><p>{subtitle}</p></header>{children}</section>;
}
