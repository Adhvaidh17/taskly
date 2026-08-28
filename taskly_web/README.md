# Taskly Web — Next.js desktop client

Domain: `https://taskly.madrascreatives.com`

This is a separate desktop UI connected to the same Supabase project, Storage, Realtime, Edge Functions and Firebase project used by Taskly mobile.

## Requirements

- Node.js 20.9+ (Node 22 LTS is recommended on CloudPanel)
- Existing Taskly Supabase migrations through v4.3
- `analyse-task-message`, `dispatch-notification` and `remove-task-attachment` functions already deployed
- Firebase Web app registered in the same Firebase project if browser push is required

## Local setup

```bash
cp .env.example .env.local
npm install
npm run dev
```

Open `http://localhost:3000` on desktop.

## CloudPanel

Create a **Node.js Site**:

- Domain: `taskly.madrascreatives.com`
- Node.js: 22 LTS
- App Port: 3000

Upload this folder to the CloudPanel site user's `htdocs/taskly.madrascreatives.com/`, create `.env.production`, then:

```bash
cd ~/htdocs/taskly.madrascreatives.com
npm install
npm run build
npm install -g pm2
PORT=3000 pm2 start npm --name taskly-web -- start
pm2 save
```

On later deployments:

```bash
npm install
npm run build
pm2 restart taskly-web --update-env
```

## Environment variables

Only browser-safe values belong in this project. Do not put any of these in the web app:

- Supabase service-role key
- Firebase service-account JSON/private key
- OpenAI API key

The Supabase publishable/anon key and Firebase Web config are client configuration and are expected to be visible in browser code. Security is enforced by Supabase Auth + RLS.

## Firebase Web Push

`npm run build` generates `public/firebase-messaging-sw.js` from the `NEXT_PUBLIC_FIREBASE_*` variables. Set the Firebase Web Push/VAPID key in `NEXT_PUBLIC_FIREBASE_VAPID_KEY`.

Taskly's existing `taskly_register_device_token_v40` RPC already accepts platform `web`, so the browser token joins the same notification pipeline as Android/iOS.

## Local-first behaviour

Conversations, recent messages, tasks and profile data are cached in IndexedDB. Opening an already visited chat paints the cached messages immediately and refreshes from Supabase in the background.

Binary files are not stored in Postgres. Messages/tasks store metadata and the actual file is in Supabase Storage. Browser downloads remain browser-controlled.

## Shared Flutter/Web contract

When this folder is placed next to `taskly_mobile` under `taskly_flutter_supabase`, use the Flutter sync patch's:

```bash
bash sync_taskly_shared.sh
```

It regenerates the shared contract and Web theme tokens from the same root configuration/current Flutter theme.
