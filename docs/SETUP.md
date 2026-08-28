# Setup

## 1. Create Supabase project
Create a project, save the project URL and publishable/anon key.

## 2. Install database
Open Supabase Dashboard > SQL Editor, paste `supabase/schema.sql`, and run it once.

The script creates profiles, workspaces, members, clients, channels, messages, tasks, subtasks, comments, history, tags, attachments, task suggestions, reminders and device tokens. It also creates RLS policies and a private `task-files` bucket.

## 3. Authentication
In Authentication > Providers, keep Email enabled. During development you may disable email confirmation. For production, keep confirmation enabled and configure redirect URLs.

## 4. Create Flutter platform files
From the package root:

```powershell
cd taskly_mobile
flutter create . --platforms=android,ios
flutter pub get
flutter analyze
```

## 5. Run

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_ANON_KEY
```

## 6. USB Android
Enable Developer options and USB debugging, connect a data cable and accept the RSA prompt.

```powershell
adb devices
flutter devices
flutter run -d DEVICE_ID --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_ANON_KEY
```

No `adb reverse` is needed because Supabase is hosted online.

## 7. Build APK

```powershell
flutter build apk --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_ANON_KEY
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Notes
- Voice-to-text needs an external transcription provider or a Supabase Edge Function.
- Push notifications need Firebase Cloud Messaging/APNs plus a sender function.
- Realtime is enabled for `messages` and `tasks` by the schema.
