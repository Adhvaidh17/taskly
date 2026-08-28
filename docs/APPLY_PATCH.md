# Apply the Taskly patch

## 1. Back up the project

From the parent folder:

```bash
cp -r taskly_mobile taskly_mobile_backup_20260729
```

On Windows, you can also duplicate the folder in File Explorer.

## 2. Copy changed Flutter files

Copy the contents of this archive's `taskly_mobile/` folder over your existing `taskly_mobile/` folder. Choose **Replace files in the destination**.

Your real `config/prod.json` is not included and will not be overwritten. Keep it as:

```json
{
  "SUPABASE_URL": "https://wqarwlhivahsivzaufnz.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_gYrceNTVFdwC8bPdPjdECA_S-SNs6aP",
  "DEFAULT_DIAL_CODE": "+91"
}
```

## 3. Run the dated Supabase migration

In the `taskly-app` Supabase dashboard:

1. Open **SQL Editor**.
2. Click **New query**.
3. Open `supabase/migrations/20260729_groups_direct_chats_ai_tasks.sql` from this archive.
4. Copy all SQL into the editor.
5. Click **Run** once.

The migration preserves existing data. Existing legacy workspaces become groups. New accounts receive only a profile and can create/join groups later.

## 4. Deploy the AI Edge Function

Install and authenticate the Supabase CLI, then run from this patch root:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set OPENAI_API_KEY="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"
supabase secrets set OPENAI_TASK_MODEL="gpt-5-mini"
supabase functions deploy analyse-task-message
```

`YOUR_PROJECT_REF` is the ID at the beginning of your Supabase project URL.

The OpenAI key belongs only in Supabase secrets. Never place it in Flutter, `prod.json`, GitHub or the Play Store bundle.

## 5. Refresh Flutter dependencies

```bash
cd taskly_mobile
flutter clean
flutter pub get
flutter analyze
```

Run on your current device:

```bash
flutter run --dart-define-from-file=config/prod.json
```

Build the Play Store bundle:

```bash
flutter build appbundle --release --dart-define-from-file=config/prod.json
```

## 6. Verify connection and workflow

1. Create two Taskly accounts using different emails and phone numbers.
2. Confirm both appear in **Supabase → Authentication → Users** and **Table Editor → profiles**.
3. Account A creates a group from **Profile → Create group**.
4. Share the group ID; Account B joins through **Profile → Join group**.
5. In group chat, Account A sends: `Hey @Mathi, collect my assignment at 5 PM.`
6. A task review card should appear only for Account A.
7. Confirm it. The task appears for both group members and under Account B's assigned tasks.
8. Only Account B can change its status.
9. Account A receives a notification when the status changes.

## 7. Contacts permission

Android permission is included in `AndroidManifest.xml`. When Taskly asks for contacts permission, approve it to discover existing users. Taskly uploads only SHA-256 hashes for exact phone/email matching; it does not upload the phone's full address book names.

For iOS, add this inside `ios/Runner/Info.plist` before `</dict>`:

```xml
<key>NSContactsUsageDescription</key>
<string>Taskly uses your contacts to show people who already use Taskly.</string>
```
