# Android Google Drive setup

Taskly v6 stores the encrypted backup in Google Drive's hidden app-data folder,
not as readable chat files.

1. In the Google Cloud project connected to the Android app, enable **Google Drive API**.
2. Ensure the Android OAuth client has the app package name and SHA-1/SHA-256
   fingerprints used by the installed build.
3. Add the Drive app-data scope to the OAuth consent configuration.
4. Keep the existing Google Sign-In setup if already present.
5. Run `flutter pub get`.
6. Test with a real Google account:
   Settings -> Chats -> Chat backup -> Back up now.
7. Uninstall/reinstall on a test phone (or use a second phone), verify the same
   Taskly account, choose Restore from Google Drive, and enter the 64-digit key.

The 64-digit recovery key is never uploaded as plaintext to Taskly/Supabase.
Losing both the old phone and the key means the encrypted backup cannot be
decrypted.
