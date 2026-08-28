'use client';

import { getApp, getApps, initializeApp } from 'firebase/app';
import { getMessaging, getToken, isSupported, onMessage, type Messaging } from 'firebase/messaging';
import type { SupabaseClient } from '@supabase/supabase-js';
import { TASKLY_CONTRACT } from '@/generated/taskly-contract';

function firebaseConfig() {
  return {
    apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
    authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
    projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
    storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
    messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
    appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
  };
}

async function messaging(): Promise<Messaging | null> {
  if (!(await isSupported())) return null;
  const config = firebaseConfig();
  if (Object.values(config).some((value) => !value)) return null;
  const app = getApps().length ? getApp() : initializeApp(config);
  return getMessaging(app);
}

function deviceId() {
  const key = 'taskly-web-device-id';
  let value = localStorage.getItem(key);
  if (!value) {
    value = `web-${crypto.randomUUID()}`;
    localStorage.setItem(key, value);
  }
  return value;
}

export async function enableWebPush(supabase: SupabaseClient) {
  const instance = await messaging();
  if (!instance) throw new Error('Web push is not configured or not supported in this browser.');
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('Notification permission was not granted.');
  const registration = await navigator.serviceWorker.register('/firebase-messaging-sw.js');
  const vapidKey = process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY;
  if (!vapidKey) throw new Error('NEXT_PUBLIC_FIREBASE_VAPID_KEY is missing.');
  const token = await getToken(instance, { vapidKey, serviceWorkerRegistration: registration });
  if (!token) throw new Error('Firebase did not return a web push token.');
  const { error } = await supabase.rpc(TASKLY_CONTRACT.rpc.registerDeviceToken, {
    p_token: token,
    p_platform: 'web',
    p_device_id: deviceId(),
  });
  if (error) throw error;
  localStorage.setItem('taskly-web-fcm-token', token);
  return token;
}

export async function disableWebPush(supabase: SupabaseClient) {
  const token = localStorage.getItem('taskly-web-fcm-token');
  if (token) {
    await supabase.rpc(TASKLY_CONTRACT.rpc.unregisterDeviceToken, { p_token: token });
    localStorage.removeItem('taskly-web-fcm-token');
  }
}

export async function listenForForegroundPush(callback: (payload: unknown) => void) {
  const instance = await messaging();
  if (!instance) return () => {};
  return onMessage(instance, callback);
}
