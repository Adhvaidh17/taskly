'use client';

import { X } from 'lucide-react';
import type { ReactNode } from 'react';
import type { Profile } from '@/lib/taskly-types';

export function Avatar({ user, name, size = 38 }: { user?: Profile | null; name?: string; size?: number }) {
  const label = user?.name || name || '?';
  const initials = label.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join('') || '?';
  return user?.avatar_url ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img className="avatar" src={user.avatar_url} alt={label} style={{ width: size, height: size }} />
  ) : (
    <div className="avatar avatar-fallback" style={{ width: size, height: size, fontSize: Math.max(11, size * 0.32) }}>{initials}</div>
  );
}

export function IconButton({ children, label, onClick, active, danger, disabled }: {
  children: ReactNode;
  label: string;
  onClick?: () => void;
  active?: boolean;
  danger?: boolean;
  disabled?: boolean;
}) {
  return <button className={`icon-button ${active ? 'is-active' : ''} ${danger ? 'is-danger' : ''}`} aria-label={label} title={label} onClick={onClick} disabled={disabled}>{children}</button>;
}

export function Modal({ title, children, onClose, wide = false }: { title: string; children: ReactNode; onClose: () => void; wide?: boolean }) {
  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose(); }}>
      <div className={`modal-card ${wide ? 'modal-wide' : ''}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head"><h2>{title}</h2><IconButton label="Close" onClick={onClose}><X size={19} /></IconButton></div>
        <div className="modal-body">{children}</div>
      </div>
    </div>
  );
}

export function Spinner({ label = 'Loading' }: { label?: string }) {
  return <div className="spinner-wrap"><span className="spinner" /><span>{label}</span></div>;
}

export function EmptyState({ icon, title, text }: { icon?: ReactNode; title: string; text?: string }) {
  return <div className="empty-state"><div className="empty-icon">{icon}</div><h3>{title}</h3>{text ? <p>{text}</p> : null}</div>;
}

export function fmtTime(value?: string | null) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(date);
}

export function fmtDay(value?: string | null) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const now = new Date();
  if (date.toDateString() === now.toDateString()) return fmtTime(value);
  const yesterday = new Date(now); yesterday.setDate(now.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';
  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date);
}

export function fmtBytes(value?: number | null) {
  if (!value || value <= 0) return '';
  if (value < 1024) return `${value} B`;
  if (value < 1024 ** 2) return `${(value / 1024).toFixed(1)} KB`;
  if (value < 1024 ** 3) return `${(value / 1024 ** 2).toFixed(1)} MB`;
  return `${(value / 1024 ** 3).toFixed(1)} GB`;
}
