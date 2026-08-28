# Scope and production follow-ups

This patch implements the complete group/direct-chat/task workflow requested. It does not claim to reproduce every separate WhatsApp product subsystem.

The following require separate production integrations before a large public launch:

- Firebase Cloud Messaging/APNs for notifications while the app is closed.
- Voice/video calling infrastructure.
- WhatsApp-style Status/Stories.
- End-to-end encrypted message key management.
- Offline-first local database and conflict resolution.
- Message pagination, media thumbnails and CDN transformations for very large groups.
- Abuse reporting, blocking, account deletion and Play Store contacts-data disclosure screens.

The current in-app notification centre, Realtime chat updates, private Supabase storage and Row Level Security are included.
