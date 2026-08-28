'use client';

import { Archive, ChevronRight, LogOut, Search, Trash2, UsersRound, Volume2, VolumeX, X } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { Conversation, Message, Profile } from '@/lib/taskly-types';
import { useTaskly } from '@/lib/taskly-store';
import { Avatar, IconButton, Spinner } from './common';
import { SharedContentModal } from './shared-content';

export function GroupInfo({ conversation, onClose }: { conversation: Conversation; onClose: () => void }) {
  const { api, attachmentUrl, refreshConversations, openConversation } = useTaskly();
  const [members, setMembers] = useState<Profile[]>([]);
  const [media, setMedia] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [sharedOpen, setSharedOpen] = useState(false);
  const [query, setQuery] = useState('');

  useEffect(() => {
    let stop = false;
    void Promise.all([api.members(conversation.channel_id), api.groupSharedContent(conversation.channel_id, 'media', 7)]).then(([m, s]) => {
      if (!stop) { setMembers(m); setMedia(s.slice(0, 7)); setLoading(false); }
    }).catch(() => setLoading(false));
    return () => { stop = true; };
  }, [api, conversation.channel_id]);

  return (
    <aside className="info-drawer">
      <header><div><span className="panel-kicker">Conversation info</span><h2>{conversation.kind === 'group' ? 'Group info' : 'Contact info'}</h2></div><IconButton label="Close" onClick={onClose}><X size={19} /></IconButton></header>
      <div className="info-scroll">
        <div className="info-profile"><Avatar name={conversation.name} size={76} /><h2>{conversation.name}</h2><p>{conversation.description || (conversation.kind === 'group' ? `${conversation.member_count || members.length} members` : 'Taskly conversation')}</p></div>
        <section className="info-section">
          <button className="section-link" onClick={() => setSharedOpen(true)}><div><strong>Media, links and docs</strong><span>{media.length ? `${media.length}+ recent` : 'Shared content'}</span></div><ChevronRight size={18} /></button>
          <div className="media-strip">{media.length ? media.map((message) => <TinyMedia key={message.id} message={message} attachmentUrl={attachmentUrl} onOpen={() => setSharedOpen(true)} />) : <span className="media-empty">No recent media</span>}</div>
        </section>
        <section className="info-section compact-actions">
          <button onClick={() => void api.setConversationPreferences(conversation.channel_id, !conversation.is_muted, undefined).then(refreshConversations)}>{conversation.is_muted ? <Volume2 size={18} /> : <VolumeX size={18} />}<span>{conversation.is_muted ? 'Unmute notifications' : 'Mute notifications'}</span></button>
          <button onClick={() => void api.setConversationPreferences(conversation.channel_id, undefined, !conversation.is_archived).then(refreshConversations)}><Archive size={18} /><span>{conversation.is_archived ? 'Unarchive chat' : 'Archive chat'}</span></button>
        </section>
        {conversation.kind === 'group' ? <section className="info-section"><div className="section-heading"><div><strong>{members.length} members</strong><span>People in this group</span></div><UsersRound size={18} /></div><div className="search-box small"><Search size={15} /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search members" /></div>{loading ? <Spinner /> : <div className="member-list">{members.filter((member) => member.name.toLowerCase().includes(query.toLowerCase())).map((member) => <div key={member.id}><Avatar user={member} size={36} /><span><strong>{member.name}</strong><small>{member.about || member.email || member.phone}</small></span>{member.role ? <em>{member.role}</em> : null}</div>)}</div>}</section> : null}
        <section className="info-section danger-zone">
          {conversation.kind === 'group' ? <button onClick={() => { if (confirm(`Leave ${conversation.name}?`)) void api.leaveGroup(conversation.workspace_id).then(() => refreshConversations()).then(onClose); }}><LogOut size={18} /> Leave group</button> : null}
          {conversation.kind === 'group' && conversation.current_role === 'owner' ? <button onClick={() => { if (confirm(`Delete ${conversation.name} for everyone?`)) void api.deleteGroup(conversation.workspace_id).then(() => refreshConversations()).then(onClose); }}><Trash2 size={18} /> Delete group</button> : <button onClick={() => { if (confirm('Delete this chat from your chat list?')) void api.deleteChat(conversation.channel_id).then(() => refreshConversations()).then(onClose); }}><Trash2 size={18} /> Delete chat</button>}
        </section>
      </div>
      {sharedOpen ? <SharedContentModal conversation={conversation} onClose={() => setSharedOpen(false)} /> : null}
    </aside>
  );
}

function TinyMedia({ message, attachmentUrl, onOpen }: { message: Message; attachmentUrl: (message: Message) => Promise<string | null>; onOpen: () => void }) {
  const [url, setUrl] = useState<string | null>(null);
  const video = (message.attachment_mime_type || '').startsWith('video/');
  useEffect(() => { let stop = false; void attachmentUrl(message).then((value) => { if (!stop) setUrl(value); }); return () => { stop = true; }; }, [attachmentUrl, message]);
  return <button onClick={onOpen}>{url ? video ? <video src={url} muted preload="metadata" /> : <img src={url} alt="Shared media" /> : <span className="media-skeleton" />}</button>;
}
