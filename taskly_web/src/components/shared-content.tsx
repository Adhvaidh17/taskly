'use client';

import { ExternalLink, FileText, ImageIcon, Link2, PlayCircle } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import type { Conversation, Message } from '@/lib/taskly-types';
import { useTaskly } from '@/lib/taskly-store';
import { EmptyState, fmtBytes, Modal, Spinner } from './common';

export function SharedContentModal({ conversation, initialTab = 'media', onClose }: {
  conversation: Conversation;
  initialTab?: 'media' | 'documents' | 'links';
  onClose: () => void;
}) {
  const { api, attachmentUrl } = useTaskly();
  const [tab, setTab] = useState<'media' | 'documents' | 'links'>(initialTab);
  const [rows, setRows] = useState<Record<string, Message[]>>({});
  const [loading, setLoading] = useState<Record<string, boolean>>({});

  async function load(kind: 'media' | 'documents' | 'links') {
    if (rows[kind] || loading[kind]) return;
    setLoading((state) => ({ ...state, [kind]: true }));
    try { setRows((state) => ({ ...state, [kind]: await api.groupSharedContent(conversation.channel_id, kind) })); }
    finally { setLoading((state) => ({ ...state, [kind]: false })); }
  }

  useEffect(() => { void load(tab); }, [tab]);

  return (
    <Modal title="Media, links and docs" onClose={onClose} wide>
      <div className="shared-tabs">
        <button className={tab === 'media' ? 'active' : ''} onClick={() => setTab('media')}>Media</button>
        <button className={tab === 'documents' ? 'active' : ''} onClick={() => setTab('documents')}>Docs</button>
        <button className={tab === 'links' ? 'active' : ''} onClick={() => setTab('links')}>Links</button>
      </div>
      {loading[tab] && !rows[tab] ? <Spinner /> : tab === 'media' ? <MediaGrid rows={rows.media || []} attachmentUrl={attachmentUrl} /> : tab === 'documents' ? <DocsList rows={rows.documents || []} attachmentUrl={attachmentUrl} /> : <LinksList rows={rows.links || []} />}
    </Modal>
  );
}

function MediaGrid({ rows, attachmentUrl }: { rows: Message[]; attachmentUrl: (message: Message) => Promise<string | null> }) {
  if (!rows.length) return <EmptyState icon={<ImageIcon size={26} />} title="No media shared yet" />;
  return <div className="shared-media-grid">{rows.map((message) => <MediaTile key={message.id} message={message} attachmentUrl={attachmentUrl} />)}</div>;
}

function MediaTile({ message, attachmentUrl }: { message: Message; attachmentUrl: (message: Message) => Promise<string | null> }) {
  const [url, setUrl] = useState<string | null>(null);
  const isVideo = (message.attachment_mime_type || '').startsWith('video/');
  useEffect(() => { let stop = false; void attachmentUrl(message).then((value) => { if (!stop) setUrl(value); }); return () => { stop = true; }; }, [attachmentUrl, message]);
  return <button className="shared-media-tile" onClick={() => url && window.open(url, '_blank', 'noopener,noreferrer')}>{url ? isVideo ? <video src={url} muted preload="metadata" /> : <img src={url} alt={message.attachment_name || 'Shared media'} /> : <span className="media-skeleton" />}{isVideo ? <PlayCircle className="tile-play" size={30} /> : null}</button>;
}

function DocsList({ rows, attachmentUrl }: { rows: Message[]; attachmentUrl: (message: Message) => Promise<string | null> }) {
  if (!rows.length) return <EmptyState icon={<FileText size={26} />} title="No documents shared yet" />;
  return <div className="shared-list">{rows.map((message) => <button key={message.id} onClick={() => void attachmentUrl(message).then((url) => url && window.open(url, '_blank', 'noopener,noreferrer'))}><span className="file-icon"><FileText size={20} /></span><span><strong>{message.attachment_name || message.body}</strong><small>{message.sender?.name || 'Taskly'}{message.attachment_size_bytes ? ` · ${fmtBytes(message.attachment_size_bytes)}` : ''}</small></span><ExternalLink size={17} /></button>)}</div>;
}

function LinksList({ rows }: { rows: Message[] }) {
  const links = useMemo(() => rows.flatMap((message) => {
    const found = message.body.match(/(?:(?:https?:\/\/)|(?:www\.))[^\s<>()]+/gi) || [];
    return found.map((url) => ({ url, sender: message.sender?.name || 'Taskly', id: `${message.id}-${url}` }));
  }), [rows]);
  if (!links.length) return <EmptyState icon={<Link2 size={26} />} title="No links shared yet" />;
  return <div className="shared-list">{links.map((item) => <button key={item.id} onClick={() => window.open(item.url.startsWith('www.') ? `https://${item.url}` : item.url, '_blank', 'noopener,noreferrer')}><span className="file-icon"><Link2 size={20} /></span><span><strong>{item.url}</strong><small>{item.sender}</small></span><ExternalLink size={17} /></button>)}</div>;
}
