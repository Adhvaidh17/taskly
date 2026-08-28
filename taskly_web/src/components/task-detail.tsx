'use client';

import { CalendarClock, CheckCircle2, Circle, Download, FileText, MessageSquareText, Paperclip, Plus, Trash2, X } from 'lucide-react';
import { useMemo, useRef, useState } from 'react';
import { useTaskly } from '@/lib/taskly-store';
import type { TaskAttachment, TaskItem } from '@/lib/taskly-types';
import { Avatar, fmtBytes, IconButton } from './common';

const statusLabels: Record<string, string> = { todo: 'To do', in_progress: 'In progress', done: 'Done' };

export function TaskDetail({ task, onClose }: { task: TaskItem; onClose: () => void }) {
  const {
    profile,
    changeTaskStatus,
    addTaskComment,
    addSubtask,
    toggleSubtask,
    uploadTaskAttachment,
    removeTaskAttachment,
    taskAttachmentUrl,
  } = useTaskly();
  const [comment, setComment] = useState('');
  const [subtask, setSubtask] = useState('');
  const [busy, setBusy] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const progress = useMemo(() => {
    const rows = task.subtasks || [];
    if (!rows.length) return 0;
    return rows.filter((item) => item.is_done).length / rows.length;
  }, [task.subtasks]);

  async function addCommentNow() {
    if (!comment.trim()) return;
    setBusy(true);
    try { await addTaskComment(task, comment); setComment(''); } finally { setBusy(false); }
  }

  async function addSubtaskNow() {
    if (!subtask.trim()) return;
    setBusy(true);
    try { await addSubtask(task, subtask); setSubtask(''); } finally { setBusy(false); }
  }

  return (
    <aside className="task-detail-drawer">
      <header className="task-detail-head"><div><span className={`priority-dot ${task.priority}`} /> <span className="panel-kicker">{task.workspace_name || task.workspace?.name || 'Taskly'}</span><h2>{task.title}</h2></div><IconButton label="Close task" onClick={onClose}><X size={19} /></IconButton></header>
      <div className="task-detail-scroll">
        <section className="task-summary-grid">
          <div><span>Status</span><select value={task.status} onChange={(e) => void changeTaskStatus(task, e.target.value)}><option value="todo">To do</option><option value="in_progress">In progress</option><option value="done">Done</option></select></div>
          <div><span>Priority</span><strong className={`priority-text ${task.priority}`}>{task.priority}</strong></div>
          <div><span>Assignee</span><div className="inline-person"><Avatar user={task.assignee} size={27} /><strong>{task.assignee?.name || 'Unassigned'}</strong></div></div>
          <div><span>Due</span><strong>{task.deadline ? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(task.deadline)) : 'No deadline'}</strong></div>
        </section>
        {task.description ? <section className="detail-section"><h3>Description</h3><p className="task-description">{task.description}</p></section> : null}
        <section className="detail-section">
          <div className="detail-section-head"><h3>Subtasks</h3>{task.subtasks?.length ? <span>{Math.round(progress * 100)}%</span> : null}</div>
          {task.subtasks?.length ? <div className="progress-track"><span style={{ width: `${progress * 100}%` }} /></div> : null}
          <div className="subtask-list">{(task.subtasks || []).map((item) => <button key={item.id} onClick={() => void toggleSubtask(task, item.id, !item.is_done, item.version)}>{item.is_done ? <CheckCircle2 size={19} className="done" /> : <Circle size={19} />}<span className={item.is_done ? 'done-text' : ''}>{item.title}</span></button>)}</div>
          <div className="inline-add"><input value={subtask} onChange={(e) => setSubtask(e.target.value)} placeholder="Add a subtask" onKeyDown={(e) => { if (e.key === 'Enter') void addSubtaskNow(); }} /><button onClick={() => void addSubtaskNow()} disabled={busy || !subtask.trim()}><Plus size={17} /></button></div>
        </section>
        <section className="detail-section">
          <div className="detail-section-head"><h3>Attachments</h3><button className="text-button" onClick={() => fileRef.current?.click()}><Paperclip size={15} /> Add file</button></div>
          <input ref={fileRef} hidden type="file" onChange={(e) => { const file = e.target.files?.[0]; e.currentTarget.value = ''; if (file) void uploadTaskAttachment(task, file); }} />
          <div className="attachment-list">{(task.attachments || []).map((attachment) => <TaskAttachmentRow key={attachment.id} task={task} attachment={attachment} removeTaskAttachment={removeTaskAttachment} taskAttachmentUrl={taskAttachmentUrl} profileId={profile?.id || 0} />)}{!(task.attachments || []).length ? <div className="subtle-empty">No attachments yet.</div> : null}</div>
        </section>
        <section className="detail-section">
          <h3>Activity & comments</h3>
          <div className="comment-list">{(task.comments || []).map((item) => <div key={item.id} className="comment-row"><Avatar user={item.user} size={31} /><div><div><strong>{item.user?.name || 'Taskly user'}</strong><time>{item.created_at ? new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(item.created_at)) : ''}</time></div><p>{item.body}</p></div></div>)}</div>
          <div className="comment-composer"><MessageSquareText size={18} /><textarea value={comment} onChange={(e) => setComment(e.target.value)} placeholder="Write a comment" onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void addCommentNow(); } }} /><button className="primary-button small" disabled={busy || !comment.trim()} onClick={() => void addCommentNow()}>Send</button></div>
        </section>
        <section className="detail-section timeline-section"><h3>Status history</h3>{(task.status_history || []).map((item) => <div key={item.id} className="timeline-row"><span /><div><strong>{statusLabels[item.to_status] || item.to_status}</strong><small>{item.user?.name || 'Taskly'}{item.created_at ? ` · ${new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(item.created_at))}` : ''}</small></div></div>)}</section>
      </div>
    </aside>
  );
}

function TaskAttachmentRow({ task, attachment, removeTaskAttachment, taskAttachmentUrl, profileId }: {
  task: TaskItem;
  attachment: TaskAttachment;
  removeTaskAttachment: (task: TaskItem, attachment: TaskAttachment) => Promise<void>;
  taskAttachmentUrl: (attachment: TaskAttachment) => Promise<string | null>;
  profileId: number;
}) {
  const removed = Boolean(attachment.removed_at);
  const canRemove = !removed && (attachment.uploaded_by_profile_id === profileId || task.creator?.id === profileId);
  return <div className={`attachment-row ${removed ? 'removed' : ''}`}><span className="file-icon"><FileText size={18} /></span><span><strong>{attachment.original_name}</strong><small>{removed ? 'Removed from task' : [fmtBytes(attachment.size_bytes), attachment.mime_type].filter(Boolean).join(' · ')}</small></span>{!removed ? <button title="Download" onClick={() => void taskAttachmentUrl(attachment).then((url) => url && window.open(url, '_blank', 'noopener,noreferrer'))}><Download size={17} /></button> : null}{canRemove ? <button className="danger" title="Remove attachment" onClick={() => { if (confirm(`Remove ${attachment.original_name} from this task?`)) void removeTaskAttachment(task, attachment); }}><Trash2 size={17} /></button> : null}</div>;
}
