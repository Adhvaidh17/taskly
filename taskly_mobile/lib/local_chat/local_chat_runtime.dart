import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_crypto_service.dart';
import 'local_attachment_store.dart';
import 'local_chat_database.dart';
import 'local_chat_transport.dart';

class LocalChatRuntime {
  LocalChatRuntime._();

  static final LocalChatRuntime instance = LocalChatRuntime._();

  LocalChatDatabase get database => LocalChatDatabase.instance;
  LocalChatTransport? transport;
  LocalAttachmentStore? attachments;
  DeviceCryptoService? crypto;

  String? _authUserId;

  Future<void> initialize(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    if (_authUserId == user.id && transport != null) return;

    await disposeTransportOnly();

    _authUserId = user.id;
    await database.openForUser(user.id);
    attachments = LocalAttachmentStore(user.id);
    crypto = DeviceCryptoService();

    transport = LocalChatTransport(
      client: client,
      database: database,
      crypto: crypto!,
      attachments: attachments!,
    );
    await transport!.initialize();
  }

  Future<bool> needsRestoreGate(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return false;

    _authUserId = user.id;
    await database.openForUser(user.id);

    // The restore screen needs the local attachment store and key service
    // before the live chat transport is initialized.
    attachments ??= LocalAttachmentStore(user.id);
    crypto ??= DeviceCryptoService();

    final skipped = await database.getSetting('restore_gate_skipped');
    if (skipped == '1') return false;
    return !(await database.hasAnyMessages());
  }

  Future<void> skipRestoreGate() async {
    await database.putSetting('restore_gate_skipped', '1');
  }

  Future<void> disposeTransportOnly() async {
    final current = transport;
    transport = null;
    if (current != null) await current.dispose();
  }

  Future<void> signOutCleanup() async {
    await disposeTransportOnly();
    await database.close();
    attachments = null;
    crypto = null;
    _authUserId = null;
  }
}
