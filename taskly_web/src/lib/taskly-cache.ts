'use client';

import { openDB, type IDBPDatabase } from 'idb';
import type { Conversation, Message, Profile, TaskItem } from './taskly-types';

type CacheRecord<T> = { key: string; value: T; updatedAt: number };
let dbPromise: Promise<IDBPDatabase> | null = null;

function db() {
  if (!dbPromise) {
    dbPromise = openDB('taskly-web-v1', 1, {
      upgrade(database) {
        if (!database.objectStoreNames.contains('kv')) database.createObjectStore('kv', { keyPath: 'key' });
      },
    });
  }
  return dbPromise;
}

const key = (namespace: string, name: string) => `${namespace}:${name}`;

async function read<T>(namespace: string, name: string): Promise<T | null> {
  const database = await db();
  const row = (await database.get('kv', key(namespace, name))) as CacheRecord<T> | undefined;
  return row?.value ?? null;
}

async function write<T>(namespace: string, name: string, value: T) {
  const database = await db();
  await database.put('kv', { key: key(namespace, name), value, updatedAt: Date.now() } satisfies CacheRecord<T>);
}

export const TasklyCache = {
  profile: (ns: string) => read<Profile>(ns, 'profile'),
  writeProfile: (ns: string, value: Profile) => write(ns, 'profile', value),
  conversations: (ns: string) => read<Conversation[]>(ns, 'conversations'),
  writeConversations: (ns: string, value: Conversation[]) => write(ns, 'conversations', value),
  messages: (ns: string, channelId: number) => read<Message[]>(ns, `messages:${channelId}`),
  writeMessages: (ns: string, channelId: number, value: Message[]) => write(ns, `messages:${channelId}`, value),
  tasks: (ns: string) => read<TaskItem[]>(ns, 'tasks'),
  writeTasks: (ns: string, value: TaskItem[]) => write(ns, 'tasks', value),
  async clearNamespace(ns: string) {
    const database = await db();
    const tx = database.transaction('kv', 'readwrite');
    let cursor = await tx.store.openCursor();
    while (cursor) {
      if (String(cursor.key).startsWith(`${ns}:`)) await cursor.delete();
      cursor = await cursor.continue();
    }
    await tx.done;
  },
};
