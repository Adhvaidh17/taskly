import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_crypto_service.dart';
import 'local_attachment_store.dart';
import 'local_chat_database_v64.dart';
import 'local_chat_transport.dart';

class LocalChatRuntime {
  LocalChatRuntime._();

  static final LocalChatRuntime instance = LocalChatRuntime._();

  LocalChatDatabaseV64 get database => LocalChatDatabaseV64.instance;
  LocalChatTransport? transport;
  LocalAttachmentStore? attachments;
  DeviceCryptoService? crypto;

  String? _authUserId;
  String? _lastTransportError;

  bool get isLocalReady => _authUserId != null;
  bool get transportReady => transport != null;
  String? get lastTransportError => _lastTransportError;

  Future<void> initialize(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    if (_authUserId != user.id) {
      await disposeTransportOnly();
      _authUserId = user.id;
    }
    await database.openForUser(user.id);
    attachments ??= LocalAttachmentStore(user.id);
    crypto ??= DeviceCryptoService();
    if (transport != null) return;
    final nextTransport = LocalChatTransport(client: client, database: database, crypto: crypto!, attachments: attachments!);
    try {
      await nextTransport.initialize();
      transport = nextTransport;
      _lastTransportError = null;
    } catch (error) {
      _lastTransportError = '$error';
      debugPrint('TASKLY_LOCAL_TRANSPORT_INIT $error');
      try { await nextTransport.dispose(); } catch (_) {}
      transport = null;
    }
  }

  Future<bool> ensureTransport(SupabaseClient client) async {
    await initialize(client);
    return transport != null;
  }

  Future<bool> needsRestoreGate(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return false;
    _authUserId = user.id;
    await database.openForUser(user.id);
    attachments ??= LocalAttachmentStore(user.id);
    crypto ??= DeviceCryptoService();
    final skipped = await database.getSetting('restore_gate_skipped');
    if (skipped == '1') return false;
    return !(await database.hasAnyMessages());
  }

  Future<void> skipRestoreGate() async => database.putSetting('restore_gate_skipped', '1');

  Future<void> disposeTransportOnly() async {
    final current = transport;
    transport = null;
    if (current != null) { try { await current.dispose(); } catch (_) {} }
  }

  Future<void> signOutCleanup() async {
    await disposeTransportOnly();
    await database.close();
    attachments = null;
    crypto = null;
    _authUserId = null;
    _lastTransportError = null;
  }
}
