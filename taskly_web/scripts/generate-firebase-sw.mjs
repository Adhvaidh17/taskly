import fs from 'node:fs';
import path from 'node:path';
import dotenv from 'dotenv';

for (const file of ['.env.local', '.env.production', '.env']) {
  const full = path.join(process.cwd(), file);
  if (fs.existsSync(full)) dotenv.config({ path: full, override: false });
}

const keys = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};
const configured = Object.values(keys).every(Boolean);
const target = path.join(process.cwd(), 'public', 'firebase-messaging-sw.js');

const source = configured
  ? `/* Generated at build time. Firebase Web config is public client config, not a server credential. */\nimportScripts('https://www.gstatic.com/firebasejs/12.2.1/firebase-app-compat.js');\nimportScripts('https://www.gstatic.com/firebasejs/12.2.1/firebase-messaging-compat.js');\nfirebase.initializeApp(${JSON.stringify(keys)});\nconst messaging = firebase.messaging();\nmessaging.onBackgroundMessage((payload) => {\n  const data = payload.data || {};\n  const title = payload.notification?.title || data.title || 'Taskly';\n  const options = {\n    body: payload.notification?.body || data.body || 'New activity',\n    icon: '/taskly-logo.svg',\n    badge: '/taskly-logo.svg',\n    data: { url: data.url || data.click_action || '/' },\n    tag: data.notification_id || data.message_id || data.task_id || undefined\n  };\n  return self.registration.showNotification(title, options);\n});\nself.addEventListener('notificationclick', (event) => {\n  event.notification.close();\n  const target = new URL(event.notification.data?.url || '/', self.location.origin).href;\n  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {\n    for (const client of list) {\n      if ('focus' in client && client.url.startsWith(self.location.origin)) {\n        client.navigate(target);\n        return client.focus();\n      }\n    }\n    return clients.openWindow ? clients.openWindow(target) : undefined;\n  }));\n});\n`
  : `/* Firebase Web Push is not configured for this build. */\nself.addEventListener('push', () => {});\n`;

fs.writeFileSync(target, source, 'utf8');
console.log(configured ? 'Taskly Firebase service worker generated.' : 'Taskly Firebase service worker left in safe no-op mode.');
