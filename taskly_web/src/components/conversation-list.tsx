'use client';

import { Archive, MoreHorizontal, Search, UsersRound } from 'lucide-react';
import { useMemo, useState } from 'react';
import { useTaskly } from '@/lib/taskly-store';
import { Avatar, fmtDay, IconButton } from './common';

export function ConversationList() {
  const { conversations, activeConversation, openConversation, profile, refreshConversations } = useTaskly();
  const [query, setQuery] = useState('');
  const [showArchived, setShowArchived] = useState(false);
  const rows = useMemo(() => conversations.filter((item) => {
    if (!showArchived && item.is_archived) return false;
    const q = query.trim().toLowerCase();
    if (!q) return true;
    return [item.name, item.last_message, item.last_sender_name].some((value) => String(value || '').toLowerCase().includes(q));
  }), [conversations, query, showArchived]);

  return (
    <section className="conversation-panel">
      <header className="panel-title-row"><div><span className="panel-kicker">Taskly</span><h1>Chats</h1></div><div className="panel-actions"><IconButton label="Refresh chats" onClick={() => void refreshConversations()}><MoreHorizontal size={20} /></IconButton></div></header>
      <div className="search-box"><Search size={17} /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search conversations" /></div>
      <div className="filter-pills"><button className={!showArchived ? 'active' : ''} onClick={() => setShowArchived(false)}>All</button><button className={showArchived ? 'active' : ''} onClick={() => setShowArchived(true)}><Archive size={14} /> Archived</button></div>
      <div className="conversation-scroll">
        {rows.map((item) => {
          const active = activeConversation?.channel_id === item.channel_id;
          const preview = item.is_self_chat ? 'Message yourself' : item.last_message || (item.kind === 'group' ? `${item.member_count || 0} members` : 'Start a conversation');
          return (
            <button key={item.channel_id} className={`conversation-row ${active ? 'active' : ''}`} onClick={() => void openConversation(item)}>
              <div className="conversation-avatar-wrap">
                {item.is_self_chat ? <Avatar user={profile} size={46} /> : <Avatar name={item.name} size={46} />}
                {item.kind === 'group' ? <span className="group-dot"><UsersRound size={10} /></span> : null}
              </div>
              <div className="conversation-copy">
                <div className="conversation-top"><strong>{item.name || (item.is_self_chat ? 'You' : 'Conversation')}</strong><time>{fmtDay(item.last_message_at)}</time></div>
                <div className="conversation-bottom"><span>{item.last_sender_name && item.kind === 'group' ? `${item.last_sender_name}: ` : ''}{preview}</span>{(item.unread_count || 0) > 0 ? <b className="unread-pill">{item.unread_count}</b> : null}</div>
              </div>
            </button>
          );
        })}
        {!rows.length ? <div className="list-empty">No conversations found.</div> : null}
      </div>
    </section>
  );
}
