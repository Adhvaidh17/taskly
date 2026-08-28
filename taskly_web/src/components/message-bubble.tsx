'use client';

import { Check, CheckCheck, Download, FileText, MoreVertical, Pin, Reply, SmilePlus, Trash2 } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useTaskly } from '@/lib/taskly-store';
import type { Message } from '@/lib/taskly-types';
import { fmtBytes, fmtTime } from './common';

export function MessageBubble({ message, onReply }: { message: Message; onReply: (message: Message) => void }) {
  const { profile, attachmentUrl, reactMessage, editMessage, deleteMessage, pinMessage, api, refreshMessage } = useTaskly();
  const mine = message.sender?.id === profile?.id;
  const [mediaUrl, setMediaUrl] = useState<string | null>(message.client_preview_url || null);
  const [menu, setMenu] = useState(false);
  const [showReactions, setShowReactions] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editBody, setEditBody] = useState(message.body);
  const mime = message.attachment_mime_type || '';
  const isImage = mime.startsWith('image/') || message.type === 'image';
  const isVideo = mime.startsWith('video/') || message.type === 'video';
  const isFile = Boolean(message.attachment_path) && !isImage && !isVideo;
  const reactions = useMemo(() => {
    const map = new Map<string, { count: number; mine: boolean }>();
    for (const row of message.message_reactions || []) {
      const current = map.get(row.emoji) || { count: 0, mine: false };
      current.count += 1;
      if (row.profile_id === profile?.id) current.mine = true;
      map.set(row.emoji, current);
    }
    return [...map.entries()];
  }, [message.message_reactions, profile?.id]);

  useEffect(() => {
    let cancelled = false;
    if ((isImage || isVideo) && !message.client_preview_url && message.attachment_path) {
      void attachmentUrl(message).then((url) => { if (!cancelled) setMediaUrl(url); }).catch(() => {});
    }
    return () => { cancelled = true; };
  }, [attachmentUrl, isImage, isVideo, message]);

  async function downloadFile() {
    const url = await attachmentUrl(message);
    if (!url) return;
    window.open(url, '_blank', 'noopener,noreferrer');
  }

  async function saveEdit() {
    const clean = editBody.trim();
    if (!clean || clean === message.body) { setEditing(false); return; }
    await editMessage(message, clean);
    setEditing(false);
  }

  return (
    <div className={`message-row ${mine ? 'mine' : 'other'}`}>
      <div className={`message-bubble ${mine ? 'mine' : 'other'} ${message.sending_failed ? 'failed' : ''}`}>
        {!mine ? <div className="message-sender">{message.sender?.name || 'Taskly user'}</div> : null}
        {message.forwarded_from_message_id ? <div className="forwarded-label">Forwarded</div> : null}
        {message.reply_to ? <div className="reply-card"><b>{message.reply_to.sender?.name || 'Message'}</b><span>{message.reply_to.body || 'Attachment'}</span></div> : null}
        {message.deleted_at ? <div className="deleted-message">This message was deleted.</div> : (
          <>
            {isImage ? <button className="media-preview" onClick={() => void downloadFile()}>{mediaUrl ? <img src={mediaUrl} alt={message.attachment_name || 'Image'} /> : <span className="media-skeleton" />}</button> : null}
            {isVideo ? <button className="media-preview video-preview" onClick={() => void downloadFile()}>{mediaUrl ? <video src={mediaUrl} muted preload="metadata" /> : <span className="media-skeleton" />}<span className="video-play">▶</span></button> : null}
            {isFile ? <button className="file-bubble" onClick={() => void downloadFile()}><span className="file-icon"><FileText size={20} /></span><span><strong>{message.attachment_name || message.body}</strong><small>{fmtBytes(message.attachment_size_bytes)}{mime ? ` · ${mime.split('/').pop()?.toUpperCase()}` : ''}</small></span><Download size={18} /></button> : null}
            {editing ? <div className="inline-edit"><textarea value={editBody} onChange={(e) => setEditBody(e.target.value)} autoFocus /><div><button onClick={() => setEditing(false)}>Cancel</button><button className="primary-button small" onClick={() => void saveEdit()}>Save</button></div></div> : (!message.attachment_path || message.body !== message.attachment_name) && message.body ? <div className="message-text">{message.body}</div> : null}
            {message.suggestion ? <div className="suggestion-card"><div><span className="suggestion-label">Task detected</span><strong>{message.suggestion.title}</strong>{message.suggestion.description ? <p>{message.suggestion.description}</p> : null}</div>{message.suggestion.status === 'pending' ? <div className="suggestion-actions"><button onClick={() => void api.dismissSuggestion(message.suggestion!.id).then(() => refreshMessage(message.id))}>Dismiss</button><button className="primary-button small" onClick={() => void api.confirmSuggestion(message.suggestion!.id).then(() => refreshMessage(message.id))}>Create task</button></div> : <span className="suggestion-status">{message.suggestion.status}</span>}</div> : null}
          </>
        )}
        {reactions.length ? <div className="reaction-row">{reactions.map(([emoji, data]) => <button key={emoji} className={data.mine ? 'mine' : ''} onClick={() => void reactMessage(message, emoji)}>{emoji} <b>{data.count}</b></button>)}</div> : null}
        <div className="message-meta"><span>{message.edited_at ? 'edited · ' : ''}{fmtTime(message.created_at)}</span>{mine ? message.optimistic ? <Check size={14} /> : <CheckCheck size={14} /> : null}{message.sending_failed ? <b>Not sent</b> : null}</div>
        {message.id > 0 && !message.deleted_at ? <div className="message-hover-tools"><button title="React" onClick={() => setShowReactions((value) => !value)}><SmilePlus size={16} /></button><button title="Reply" onClick={() => onReply(message)}><Reply size={16} /></button><button title="More" onClick={() => setMenu((value) => !value)}><MoreVertical size={16} /></button></div> : null}
        {showReactions ? <div className="reaction-picker">{['👍','❤️','😂','😮','😢','🙏'].map((emoji) => <button key={emoji} onClick={() => { setShowReactions(false); void reactMessage(message, emoji); }}>{emoji}</button>)}</div> : null}
        {menu ? <div className="message-menu"><button onClick={() => { setMenu(false); void pinMessage(message, !message.is_pinned); }}><Pin size={15} /> {message.is_pinned ? 'Unpin' : 'Pin'}</button>{mine ? <button onClick={() => { setMenu(false); setEditing(true); }}><span>✎</span> Edit</button> : null}{mine ? <button className="danger" onClick={() => { setMenu(false); if (confirm('Delete this message?')) void deleteMessage(message); }}><Trash2 size={15} /> Delete</button> : null}</div> : null}
      </div>
    </div>
  );
}
