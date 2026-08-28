'use client';

import { CalendarClock, CheckCircle2, CheckSquare2, CircleDot, ListFilter, Plus, Search, UserRound } from 'lucide-react';
import { useMemo, useState } from 'react';
import { useTaskly } from '@/lib/taskly-store';
import type { Conversation, Profile, TaskItem } from '@/lib/taskly-types';
import { Avatar, EmptyState, Modal } from './common';
import { TaskDetail } from './task-detail';

export function TasksView() {
  const { tasks, activeTask, openTask, profile, conversations, createTask, api, refreshTasks } = useTaskly();
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('all');
  const [createOpen, setCreateOpen] = useState(false);
  const [detailOpen, setDetailOpen] = useState(Boolean(activeTask));
  const rows = useMemo(() => tasks.filter((task) => {
    if (status !== 'all' && task.status !== status) return false;
    const q = query.trim().toLowerCase();
    return !q || [task.title, task.description, task.assignee?.name, task.workspace_name].some((value) => String(value || '').toLowerCase().includes(q));
  }), [tasks, query, status]);

  function select(task: TaskItem) { setDetailOpen(true); void openTask(task); }

  return (
    <section className="tasks-workspace">
      <div className="tasks-list-panel">
        <header className="tasks-head"><div><span className="panel-kicker">Your work</span><h1>Tasks</h1></div><button className="primary-button" onClick={() => setCreateOpen(true)}><Plus size={17} /> New task</button></header>
        <div className="task-toolbar"><div className="search-box"><Search size={17} /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search tasks" /></div><button className="secondary-button" onClick={() => void refreshTasks()}><ListFilter size={16} /> Refresh</button></div>
        <div className="filter-pills task-pills">{[['all','All'],['todo','To do'],['in_progress','In progress'],['done','Done']].map(([key,label]) => <button key={key} className={status === key ? 'active' : ''} onClick={() => setStatus(key)}>{label}</button>)}</div>
        <div className="task-list-scroll">{rows.map((task) => <TaskCard key={task.id} task={task} onClick={() => select(task)} />)}{!rows.length ? <EmptyState icon={<CheckSquare2 size={28} />} title="No tasks here" text="Try another filter or create a task." /> : null}</div>
      </div>
      <div className="task-stage">{detailOpen && activeTask ? <TaskDetail task={activeTask} onClose={() => setDetailOpen(false)} /> : <EmptyState icon={<CheckSquare2 size={32} />} title="Select a task" text="Open a task to see its details, subtasks, comments and attachments." />}</div>
      {createOpen ? <CreateTaskModal conversations={conversations} profile={profile} api={api} onClose={() => setCreateOpen(false)} onCreate={async (values) => { const task = await createTask(values); setCreateOpen(false); setDetailOpen(true); await openTask(task); }} /> : null}
    </section>
  );
}

function TaskCard({ task, onClick }: { task: TaskItem; onClick: () => void }) {
  const done = task.status === 'done';
  const overdue = !done && task.deadline && new Date(task.deadline).getTime() < Date.now();
  return <button className={`task-card-row ${done ? 'done' : ''}`} onClick={onClick}><span className={`task-status-icon ${task.status}`}>{done ? <CheckCircle2 size={19} /> : task.status === 'in_progress' ? <CircleDot size={19} /> : <CheckSquare2 size={19} />}</span><span className="task-card-copy"><span className="task-title-line"><strong>{task.title}</strong><em className={`priority-chip ${task.priority}`}>{task.priority}</em></span><span className="task-meta-line"><span><UserRound size={13} /> {task.assignee?.name || 'Unassigned'}</span><span className={overdue ? 'overdue' : ''}><CalendarClock size={13} /> {task.deadline ? new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(task.deadline)) : 'No deadline'}</span></span><span className="task-context">{task.workspace_name || task.workspace?.name || task.channel?.name || 'Taskly'}</span></span></button>;
}

function CreateTaskModal({ conversations, profile, api, onClose, onCreate }: {
  conversations: Conversation[];
  profile: Profile | null;
  api: ReturnType<typeof useTaskly>['api'];
  onClose: () => void;
  onCreate: (values: { title: string; description?: string; priority: string; deadline?: string | null; assigneeId: number; channelId: number }) => Promise<void>;
}) {
  const channels = conversations.filter((item) => !item.is_archived);
  const [channelId, setChannelId] = useState(channels[0]?.channel_id || 0);
  const [members, setMembers] = useState<Profile[]>(profile ? [profile] : []);
  const [assigneeId, setAssigneeId] = useState(profile?.id || 0);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState('medium');
  const [deadline, setDeadline] = useState('');
  const [busy, setBusy] = useState(false);

  async function changeChannel(id: number) {
    setChannelId(id);
    const rows = await api.members(id);
    setMembers(rows);
    if (!rows.some((item) => item.id === assigneeId)) setAssigneeId(rows[0]?.id || profile?.id || 0);
  }

  async function submit() {
    if (!title.trim() || !channelId || !assigneeId) return;
    setBusy(true);
    try { await onCreate({ title, description, priority, deadline: deadline ? new Date(deadline).toISOString() : null, assigneeId, channelId }); }
    finally { setBusy(false); }
  }

  return <Modal title="Create task" onClose={onClose}><div className="form-stack"><label className="field"><span>Title</span><input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="What needs to be done?" autoFocus /></label><label className="field"><span>Description</span><textarea value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Add context or instructions" /></label><div className="form-grid"><label className="field"><span>Conversation / group</span><select value={channelId} onChange={(e) => void changeChannel(Number(e.target.value))}>{channels.map((item) => <option key={item.channel_id} value={item.channel_id}>{item.name}</option>)}</select></label><label className="field"><span>Assignee</span><select value={assigneeId} onChange={(e) => setAssigneeId(Number(e.target.value))}>{members.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="field"><span>Priority</span><select value={priority} onChange={(e) => setPriority(e.target.value)}><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option></select></label><label className="field"><span>Deadline</span><input type="datetime-local" value={deadline} onChange={(e) => setDeadline(e.target.value)} /></label></div><div className="modal-actions"><button className="secondary-button" onClick={onClose}>Cancel</button><button className="primary-button" onClick={() => void submit()} disabled={busy || !title.trim() || !channelId || !assigneeId}>{busy ? 'Creating…' : 'Create task'}</button></div></div></Modal>;
}
