import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'device_crypto_service.dart';
import 'local_attachment_store.dart';
import 'local_chat_database.dart';

class LocalChatTransport {
  LocalChatTransport({
    required this.client,
    required this.database,
    required this.crypto,
    required this.attachments,
  });

  final SupabaseClient client;
  final LocalChatDatabase database;
  final DeviceCryptoService crypto;
  final LocalAttachmentStore attachments;

  static const _uuid = Uuid();
  static const maxTransientAttachmentBytes = 15 * 1024 * 1024;

  final StreamController<int> _channelChanged =
      StreamController<int>.broadcast();
  RealtimeChannel? _realtime;
  Timer? _fallbackTimer;
  String? _deviceId;
  int? _profileId;
  bool _pulling = false;
  bool _deviceKeyRegistered = false;

  Stream<int> get channelChanged => _channelChanged.stream;

  User get _authUser {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('Not signed in.');
    return user;
  }

  Future<void> initialize() async {
    final user = _authUser;
    final identity = await crypto.ensureIdentity(user.id);
    _deviceId = identity.deviceId;

    final profile = await _currentProfile();
    _profileId = (profile['id'] as num).toInt();

    try {
      await client.rpc(
        'taskly_register_device_key',
        params: {
          'p_device_id': identity.deviceId,
          'p_public_key': identity.publicKeyBase64,
        },
      );
      _deviceKeyRegistered = true;
    } catch (_) {
      // Local chat must remain usable while offline. The device key is
      // registered automatically on the next successful retry.
    }

    await database.cleanupMissingAttachments();
    try {
      await pullNow();
      await flushOutbox();
    } catch (_) {
      // Offline: keep the local transcript and outbox intact.
    }

    if (_realtime != null) {
      await client.removeChannel(_realtime!);
    }
    _realtime = client
        .channel('taskly-v60-inbox-${identity.deviceId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_delivery_envelopes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_profile_id',
            value: _profileId!,
          ),
          callback: (_) => unawaited(pullNow()),
        )
        .subscribe();

    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(pullNow()),
    );
  }

  Future<Map<String, dynamic>> sendText({
    required int workspaceId,
    required int channelId,
    required String body,
    String? replyToClientId,
  }) async {
    final profile = await _currentProfile();
    final clientId = _uuid.v4();
    final createdAt = DateTime.now().toUtc();

    final localId = await database.insertMessage(
      clientMessageId: clientId,
      workspaceId: workspaceId,
      channelId: channelId,
      senderProfileId: (profile['id'] as num).toInt(),
      senderName: profile['name'] as String? ?? 'You',
      senderEmail: profile['email'] as String?,
      senderPhone: profile['phone'] as String?,
      senderAvatarUrl: profile['avatar_url'] as String?,
      body: body,
      type: 'text',
      createdAt: createdAt,
      replyToClientId: replyToClientId,
      deliveryState: 'sending',
    );

    final payload = {
      'op': 'message',
      'message': {
        'client_message_id': clientId,
        'workspace_id': workspaceId,
        'channel_id': channelId,
        'sender': _publicProfile(profile),
        'body': body,
        'type': 'text',
        'created_at': createdAt.toIso8601String(),
        'reply_to_client_id': replyToClientId,
      },
    };
    await _queueOrFanOut(channelId, clientId, payload);
    await database.db.update(
      'local_messages',
      {'delivery_state': 'sent'},
      where: 'id = ?',
      whereArgs: [localId],
    );
    final row = await database.messageByClientId(clientId);
    return _legacyRow(row!);
  }

  Future<Map<String, dynamic>> sendAttachment({
    required int workspaceId,
    required int channelId,
    required String sourcePath,
    String body = '',
    String? mimeType,
    String? replyToClientId,
  }) async {
    final source = File(sourcePath);
    final size = await source.length();
    if (size > maxTransientAttachmentBytes) {
      throw StateError(
        'This file is larger than 15 MB. Taskly v6 does not keep '
        'chat media permanently on the server.',
      );
    }

    final profile = await _currentProfile();
    final clientId = _uuid.v4();
    final createdAt = DateTime.now().toUtc();
    final localPath = await attachments.importOutgoing(
      channelId: channelId,
      sourcePath: sourcePath,
    );
    final bytes = await File(localPath).readAsBytes();
    final name = source.uri.pathSegments.isEmpty
        ? 'attachment'
        : source.uri.pathSegments.last;

    final type = mimeType?.startsWith('image/') == true
        ? 'image'
        : mimeType?.startsWith('video/') == true
            ? 'video'
            : mimeType?.startsWith('audio/') == true
                ? 'audio'
                : 'file';

    final localId = await database.insertMessage(
      clientMessageId: clientId,
      workspaceId: workspaceId,
      channelId: channelId,
      senderProfileId: (profile['id'] as num).toInt(),
      senderName: profile['name'] as String? ?? 'You',
      senderEmail: profile['email'] as String?,
      senderPhone: profile['phone'] as String?,
      senderAvatarUrl: profile['avatar_url'] as String?,
      body: body,
      type: type,
      createdAt: createdAt,
      replyToClientId: replyToClientId,
      attachmentPath: localPath,
      attachmentName: name,
      attachmentMimeType: mimeType,
      attachmentSizeBytes: bytes.length,
      deliveryState: 'sending',
    );

    final payload = {
      'op': 'message',
      'message': {
        'client_message_id': clientId,
        'workspace_id': workspaceId,
        'channel_id': channelId,
        'sender': _publicProfile(profile),
        'body': body,
        'type': type,
        'created_at': createdAt.toIso8601String(),
        'reply_to_client_id': replyToClientId,
        'attachment': {
          'name': name,
          'mime_type': mimeType,
          'size_bytes': bytes.length,
          'bytes_base64': base64Encode(bytes),
        },
      },
    };
    await _queueOrFanOut(channelId, clientId, payload);
    await database.db.update(
      'local_messages',
      {'delivery_state': 'sent'},
      where: 'id = ?',
      whereArgs: [localId],
    );
    final row = await database.messageByClientId(clientId);
    return _legacyRow(row!);
  }

  Future<Map<String, dynamic>> sendStructuredMessage({
    required int workspaceId,
    required int channelId,
    required String body,
    required String type,
    Map<String, dynamic>? metadata,
    String? replyToClientId,
    String? attachmentPath,
    String? attachmentName,
    String? attachmentMimeType,
  }) async {
    final profile = await _currentProfile();
    final clientId = _uuid.v4();
    final createdAt = DateTime.now().toUtc();
    String? localPath = attachmentPath;
    int? size;
    if (localPath != null && localPath.isNotEmpty) {
      final source = File(localPath);
      if (!await source.exists()) throw const FileSystemException('Attachment unavailable.');
      localPath = await attachments.importOutgoing(
        channelId: channelId,
        sourcePath: localPath,
      );
      size = await File(localPath).length();
    }
    final localId = await database.insertMessage(
      clientMessageId: clientId,
      workspaceId: workspaceId,
      channelId: channelId,
      senderProfileId: (profile['id'] as num).toInt(),
      senderName: profile['name'] as String? ?? 'You',
      senderEmail: profile['email'] as String?,
      senderPhone: profile['phone'] as String?,
      senderAvatarUrl: profile['avatar_url'] as String?,
      body: body,
      type: type,
      createdAt: createdAt,
      replyToClientId: replyToClientId,
      attachmentPath: localPath,
      attachmentName: attachmentName,
      attachmentMimeType: attachmentMimeType,
      attachmentSizeBytes: size,
      deliveryState: 'sending',
      metadata: metadata,
    );
    final attachment = localPath == null
        ? null
        : {
            'name': attachmentName ?? 'attachment',
            'mime_type': attachmentMimeType,
            'size_bytes': size ?? 0,
            'bytes_base64': base64Encode(await File(localPath).readAsBytes()),
          };
    final payload = {
      'op': 'message',
      'message': {
        'client_message_id': clientId,
        'workspace_id': workspaceId,
        'channel_id': channelId,
        'sender': _publicProfile(profile),
        'body': body,
        'type': type,
        'created_at': createdAt.toIso8601String(),
        'reply_to_client_id': replyToClientId,
        'metadata': metadata ?? const <String, dynamic>{},
        if (attachment != null) 'attachment': attachment,
      },
    };
    await _queueOrFanOut(channelId, clientId, payload);
    await database.db.update('local_messages', {'delivery_state': 'sent'}, where: 'id = ?', whereArgs: [localId]);
    return _legacyRow((await database.messageByClientId(clientId))!);
  }

  Future<void> editMessage({
    required int channelId,
    required String clientMessageId,
    required String body,
  }) async {
    await database.updateMessageText(clientMessageId, body);
    await _queueOrFanOut(
      channelId,
      _uuid.v4(),
      {
        'op': 'edit',
        'target_client_message_id': clientMessageId,
        'body': body,
        'edited_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    _channelChanged.add(channelId);
  }

  Future<void> deleteForEveryone({
    required int channelId,
    required String clientMessageId,
  }) async {
    final row = await database.messageByClientId(clientMessageId);
    await database.removeAttachment(clientMessageId);
    if (row != null && (row['body'] as String? ?? '').trim().isNotEmpty) {
      await database.deleteMessage(clientMessageId);
    }

    await _queueOrFanOut(
      channelId,
      _uuid.v4(),
      {
        'op': 'delete',
        'target_client_message_id': clientMessageId,
      },
    );
    _channelChanged.add(channelId);
  }

  Future<void> removeAttachmentFromDevice({
    required int channelId,
    required String clientMessageId,
  }) async {
    await database.removeAttachment(clientMessageId);
    _channelChanged.add(channelId);
  }

  Future<void> setPinned({
    required int channelId,
    required String clientMessageId,
    required bool pinned,
  }) async {
    await database.setMessagePinned(clientMessageId, pinned);
    await _queueOrFanOut(
      channelId,
      _uuid.v4(),
      {
        'op': 'pin',
        'target_client_message_id': clientMessageId,
        'value': pinned,
      },
    );
    _channelChanged.add(channelId);
  }

  Future<void> setReaction({
    required int channelId,
    required String clientMessageId,
    required String emoji,
    required int reactorProfileId,
    required bool enabled,
  }) async {
    final row = await database.messageByClientId(clientMessageId);
    final current = _decodeMap(row?['reactions_json']);
    final key = '$reactorProfileId';
    if (enabled) {
      current[key] = emoji;
    } else {
      current.remove(key);
    }
    await database.setMessageReactions(clientMessageId, current);

    await _queueOrFanOut(
      channelId,
      _uuid.v4(),
      {
        'op': 'reaction',
        'target_client_message_id': clientMessageId,
        'reactor_profile_id': reactorProfileId,
        'emoji': emoji,
        'enabled': enabled,
      },
    );
    _channelChanged.add(channelId);
  }

  Future<void> pullNow() async {
    if (_pulling) return;
    final deviceId = _deviceId;
    if (deviceId == null) return;
    _pulling = true;

    try {
      if (!_deviceKeyRegistered && _deviceId != null && crypto != null) {
        try {
          await client.rpc('taskly_register_device_key', params: {
            'p_device_id': _deviceId,
            'p_public_key': (await crypto!.ensureIdentity(_authUser.id)).publicKeyBase64,
          });
          _deviceKeyRegistered = true;
        } catch (_) {}
      }
      final result = await client.rpc(
        'taskly_pull_chat_envelopes',
        params: {
          'p_device_id': deviceId,
          'p_limit': 100,
        },
      );

      final rows = (result as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (rows.isEmpty) return;

      final ackIds = <String>[];
      for (final row in rows) {
        try {
          final payload = await crypto.decryptJson(
            authUserId: _authUser.id,
            senderPublicKeyBase64: row['sender_public_key'] as String,
            clientMessageId: row['client_message_id'] as String,
            ciphertextBase64: row['ciphertext'] as String,
            nonceBase64: row['nonce'] as String,
            macBase64: row['mac'] as String,
          );
          final channelId = await _applyIncoming(payload);
          ackIds.add(row['id'] as String);
          if (channelId != null) _channelChanged.add(channelId);
        } catch (_) {
          // Do not ACK decrypt/commit failures; retry until envelope expires.
        }
      }

      if (ackIds.isNotEmpty) {
        await client.rpc(
          'taskly_ack_chat_envelopes',
          params: {
            'p_device_id': deviceId,
            'p_ids': ackIds,
          },
        );
      }
    } finally {
      _pulling = false;
    }
  }

  Future<int?> _applyIncoming(Map<String, dynamic> payload) async {
    final op = payload['op'] as String? ?? '';

    if (op == 'message') {
      final raw = Map<String, dynamic>.from(payload['message'] as Map);
      final sender = Map<String, dynamic>.from(raw['sender'] as Map);
      final channelId = (raw['channel_id'] as num).toInt();
      final workspaceId = (raw['workspace_id'] as num).toInt();

      String? attachmentPath;
      String? attachmentName;
      String? attachmentMime;
      int? attachmentSize;

      final attachment = raw['attachment'];
      if (attachment is Map) {
        final a = Map<String, dynamic>.from(attachment);
        attachmentName = a['name'] as String? ?? 'attachment';
        attachmentMime = a['mime_type'] as String?;
        final bytes = base64Decode(a['bytes_base64'] as String);
        attachmentSize = bytes.length;
        attachmentPath = await attachments.writeIncoming(
          channelId: channelId,
          originalName: attachmentName,
          bytes: bytes,
        );
      }

      await database.insertMessage(
        clientMessageId: raw['client_message_id'] as String,
        workspaceId: workspaceId,
        channelId: channelId,
        senderProfileId: (sender['id'] as num?)?.toInt(),
        senderName: sender['name'] as String? ?? '',
        senderEmail: sender['email'] as String?,
        senderPhone: sender['phone'] as String?,
        senderAvatarUrl: sender['avatar_url'] as String?,
        body: raw['body'] as String? ?? '',
        type: raw['type'] as String? ?? 'text',
        createdAt: DateTime.parse(raw['created_at'] as String),
        replyToClientId: raw['reply_to_client_id'] as String?,
        attachmentPath: attachmentPath,
        attachmentName: attachmentName,
        attachmentMimeType: attachmentMime,
        attachmentSizeBytes: attachmentSize,
        deliveryState: 'delivered',
        metadata: raw['metadata'] is Map
            ? Map<String, dynamic>.from(raw['metadata'] as Map)
            : null,
      );
      return channelId;
    }

    final target = payload['target_client_message_id'] as String?;
    if (target == null) return null;
    final original = await database.messageByClientId(target);
    final channelId = (original?['channel_id'] as num?)?.toInt();

    switch (op) {
      case 'edit':
        await database.updateMessageText(
          target,
          payload['body'] as String? ?? '',
          editedAt: payload['edited_at'] == null
              ? null
              : DateTime.parse(payload['edited_at'] as String),
        );
        break;

      case 'delete':
        await database.removeAttachment(target);
        final remaining = await database.messageByClientId(target);
        if (remaining != null) await database.deleteMessage(target);
        break;

      case 'pin':
        await database.setMessagePinned(target, payload['value'] == true);
        break;

      case 'reaction':
        if (original != null) {
          final current = _decodeMap(original['reactions_json']);
          final reactor = '${payload['reactor_profile_id']}';
          if (payload['enabled'] == true) {
            current[reactor] = payload['emoji'];
          } else {
            current.remove(reactor);
          }
          await database.setMessageReactions(target, current);
        }
        break;
    }
    return channelId;
  }

  Future<void> _queueOrFanOut(
    int channelId,
    String clientMessageId,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _fanOut(
        channelId: channelId,
        clientMessageId: clientMessageId,
        payload: payload,
      );
      await database.removeOutbox(clientMessageId);
    } catch (_) {
      await database.enqueueOutbox(
        clientMessageId: clientMessageId,
        channelId: channelId,
        payloadJson: jsonEncode(payload),
      );
    }
  }

  Future<void> flushOutbox() async {
    final rows = await database.outbox();
    for (final row in rows) {
      final id = row['client_message_id'] as String;
      try {
        final payload = jsonDecode(row['payload_json'] as String);
        if (payload is! Map) continue;
        await _fanOut(
          channelId: (row['channel_id'] as num).toInt(),
          clientMessageId: id,
          payload: Map<String, dynamic>.from(payload),
        );
        await database.removeOutbox(id);
      } catch (_) {
        // Keep it until connectivity is restored.
      }
    }
  }

  Future<void> _fanOut({
    required int channelId,
    required String clientMessageId,
    required Map<String, dynamic> payload,
  }) async {
    final identity = await crypto.ensureIdentity(_authUser.id);
    final result = await client.rpc(
      'taskly_recipient_device_keys',
      params: {
        'p_channel_id': channelId,
        'p_current_device_id': identity.deviceId,
      },
    );

    final devices = (result as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    for (final device in devices) {
      final encrypted = await crypto.encryptJson(
        authUserId: _authUser.id,
        remotePublicKeyBase64: device['public_key'] as String,
        clientMessageId: clientMessageId,
        payload: payload,
      );

      await client.rpc(
        'taskly_enqueue_chat_envelope',
        params: {
          'p_client_message_id': clientMessageId,
          'p_channel_id': channelId,
          'p_recipient_profile_id': (device['profile_id'] as num).toInt(),
          'p_recipient_device_id': device['device_id'] as String,
          'p_sender_device_id': identity.deviceId,
          'p_sender_public_key': encrypted.senderPublicKey,
          'p_ciphertext': encrypted.ciphertext,
          'p_nonce': encrypted.nonce,
          'p_mac': encrypted.mac,
        },
      );
    }
  }

  Future<Map<String, dynamic>> _currentProfile() async {
    final row = await client
        .from('profiles')
        .select('id,name,email,phone,avatar_url')
        .eq('auth_user_id', _authUser.id)
        .single();
    return Map<String, dynamic>.from(row);
  }

  Map<String, dynamic> _publicProfile(Map<String, dynamic> profile) {
    return <String, dynamic>{
      'id': profile['id'],
      'name': profile['name'],
      'email': profile['email'],
      'phone': profile['phone'],
      'avatar_url': profile['avatar_url'],
    };
  }

  Map<String, dynamic> _decodeMap(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _legacyRow(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['id'],
      'client_message_id': row['client_message_id'],
      'workspace_id': row['workspace_id'],
      'channel_id': row['channel_id'],
      'body': row['body'],
      'type': row['type'],
      'created_at': row['created_at'],
      'edited_at': row['edited_at'],
      'is_pinned': (row['pinned'] as num? ?? 0).toInt() == 1,
      'attachment_path': row['attachment_path'],
      'attachment_name': row['attachment_name'],
      'attachment_mime_type': row['attachment_mime_type'],
      'attachment_size_bytes': row['attachment_size_bytes'],
      'sender': {
        'id': row['sender_profile_id'],
        'name': row['sender_name'],
        'email': row['sender_email'],
        'phone': row['sender_phone'],
        'avatar_url': row['sender_avatar_url'],
      },
      'reply_to': null,
    };
  }

  Future<void> dispose() async {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    final realtime = _realtime;
    _realtime = null;
    if (realtime != null) await client.removeChannel(realtime);
    await _channelChanged.close();
  }
}
