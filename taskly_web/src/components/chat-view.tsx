'use client';

import { ArrowDown, Info, Paperclip, Search, Send, Smile, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { useTaskly } from '@/lib/taskly-store';
import type { Message } from '@/lib/taskly-types';
import { Avatar, EmptyState, IconButton } from './common';
import { MessageBubble } from './message-bubble';
import { GroupInfo } from './group-info';

export function ChatView() {
  const { activeConversation, messages, hasOlderMessages, loadOlderMessages, sendMessage, sendAttachment, profile } = useTaskly();
  const [body, setBody] = useState('');
  const [replyTo, setReplyTo] = useState<Message | null>(null);
  const [showInfo, setShowInfo] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState('');
  const scrollRef = useRef<HTMLDivElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    requestAnimationFrame(() => { const el = scrollRef.current; if (el) el.scrollTop = el.scrollHeight; });
  }, [activeConversation?.channel_id, messages.length]);

  if (!activeConversation) {
    return <section className="chat-empty-panel"><EmptyState icon={<img src="/taskly-logo.svg" alt="" />} title="Taskly Web" text="Select a conversation to start messaging, creating tasks and sharing files." /></section>;
  }

  const filtered = query.trim() ? messages.filter((message) => message.body.toLowerCase().includes(query.toLowerCase())) : messages;
  const canSend = !activeConversation.only_admins_can_send || ['owner','admin'].includes(activeConversation.current_role || '') || activeConversation.kind !== 'group';

  async function submit() {
    const clean = body.trim();
    if (!clean || !canSend) return;
    setBody('');
    const reply = replyTo; setReplyTo(null);
    await sendMessage(clean, reply);
  }

  return (
    <section className="chat-workspace">
      <div className="chat-main">
        <header className="chat-header">
          <button className="chat-person" onClick={() => setShowInfo(true)}><Avatar name={activeConversation.is_self_chat ? profile?.name : activeConversation.name} size={40} /><span><strong>{activeConversation.name || (activeConversation.is_self_chat ? 'You' : 'Conversation')}</strong><small>{activeConversation.kind === 'group' ? `${activeConversation.member_count || 0} members` : activeConversation.is_self_chat ? 'Message yourself' : 'Taskly contact'}</small></span></button>
          <div className="chat-header-actions">{searchOpen ? <div className="header-search"><Search size={16} /><input autoFocus value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search this chat" /><button onClick={() => { setSearchOpen(false); setQuery(''); }}><X size={16} /></button></div> : <IconButton label="Search" onClick={() => setSearchOpen(true)}><Search size={19} /></IconButton>}<IconButton label="Conversation info" onClick={() => setShowInfo(true)}><Info size={19} /></IconButton></div>
        </header>
        <div className="message-canvas" ref={scrollRef}>
          <div className="chat-wallpaper" />
          <div className="messages-column">
            {hasOlderMessages ? <button className="load-older" onClick={() => void loadOlderMessages()}><ArrowDown size={15} /> Load older messages</button> : null}
            {filtered.map((message, index) => {
              const day = new Date(message.created_at).toDateString();
              const previousDay = index > 0 ? new Date(filtered[index - 1].created_at).toDateString() : null;
              return <div key={message.id}>{day !== previousDay ? <div className="day-separator"><span>{new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: new Date(message.created_at).getFullYear() !== new Date().getFullYear() ? 'numeric' : undefined }).format(new Date(message.created_at))}</span></div> : null}<MessageBubble message={message} onReply={setReplyTo} /></div>;
            })}
          </div>
        </div>
        {replyTo ? <div className="composer-reply"><span><b>Replying to {replyTo.sender?.name}</b><small>{replyTo.body || replyTo.attachment_name || 'Attachment'}</small></span><button onClick={() => setReplyTo(null)}><X size={17} /></button></div> : null}
        <footer className="composer">
          <input ref={fileRef} type="file" hidden onChange={(e) => { const file = e.target.files?.[0]; e.currentTarget.value = ''; if (file) void sendAttachment(file, replyTo).then(() => setReplyTo(null)); }} />
          <IconButton label="Emoji"><Smile size={20} /></IconButton>
          <IconButton label="Attach file" onClick={() => fileRef.current?.click()}><Paperclip size={20} /></IconButton>
          <textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder={canSend ? 'Type a message' : 'Only admins can send messages'} disabled={!canSend} onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void submit(); } }} />
          <button className="send-button" disabled={!body.trim() || !canSend} onClick={() => void submit()}><Send size={19} /></button>
        </footer>
      </div>
      {showInfo ? <GroupInfo conversation={activeConversation} onClose={() => setShowInfo(false)} /> : null}
    </section>
  );
}
