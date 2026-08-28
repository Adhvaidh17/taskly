import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../local_chat/local_attachment_store.dart';
import '../local_chat/local_chat_database.dart';
import 'backup_key_service.dart';
import 'google_drive_backup_service.dart';

class ChatBackupResult {
  const ChatBackupResult({
    required this.createdAt,
    required this.encryptedBytes,
    required this.messageCount,
    required this.mediaBytes,
  });

  final DateTime createdAt;
  final int encryptedBytes;
  final int messageCount;
  final int mediaBytes;
}

class ChatBackupService {
  ChatBackupService({
    required this.authUserId,
    required this.database,
    required this.attachments,
    required this.keys,
    required this.drive,
  });

  final String authUserId;
  final LocalChatDatabase database;
  final LocalAttachmentStore attachments;
  final BackupKeyService keys;
  final GoogleDriveBackupService drive;

  final AesGcm _aes = AesGcm.with256bits();

  static final List<int> _magic = utf8.encode('TASKLYV60');

  Future<ChatBackupResult> backUpNow({
    bool includeVideos = true,
  }) async {
    final key = await keys.ensureRecoveryKey(authUserId);
    final built = await buildEncryptedBackup(
      recoveryKey: key,
      includeVideos: includeVideos,
    );

    await drive.upload(
      encryptedBytes: built.bytes,
      metadata: {
        'schema': 60,
        'created_at': built.createdAt.toIso8601String(),
        'message_count': built.messageCount,
        'media_bytes': built.mediaBytes,
        'encrypted_bytes': built.bytes.length,
        'include_videos': includeVideos,
      },
    );

    await database.putSetting(
      'backup_last_at',
      built.createdAt.toIso8601String(),
    );
    await database.putSetting(
      'backup_last_message_count',
      '${built.messageCount}',
    );
    await database.putMigrationState('first_verified_backup_v60', 'complete');

    return ChatBackupResult(
      createdAt: built.createdAt,
      encryptedBytes: built.bytes.length,
      messageCount: built.messageCount,
      mediaBytes: built.mediaBytes,
    );
  }

  Future<BuiltChatBackup> buildEncryptedBackup({
    required String recoveryKey,
    bool includeVideos = true,
  }) async {
    await database.cleanupMissingAttachments();
    await database.checkpoint();

    final dbPath = await database.databasePath();
    final mediaRoot = await attachments.mediaRootPath();
    final archive = Archive();

    final dbBytes = await File(dbPath).readAsBytes();
    archive.addFile(
      ArchiveFile('db/taskly_chat.db', dbBytes.length, dbBytes),
    );

    var mediaBytes = 0;
    final mediaDir = Directory(mediaRoot);
    if (await mediaDir.exists()) {
      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is! File) continue;

        final ext = p.extension(entity.path).toLowerCase();
        final looksVideo = const {
          '.mp4',
          '.mov',
          '.m4v',
          '.avi',
          '.mkv',
          '.webm',
        }.contains(ext);
        if (!includeVideos && looksVideo) continue;

        final bytes = await entity.readAsBytes();
        mediaBytes += bytes.length;
        final relative = p.relative(entity.path, from: mediaRoot);
        archive.addFile(
          ArchiveFile(
            p.posix.join('media', relative.replaceAll('\\', '/')),
            bytes.length,
            bytes,
          ),
        );
      }
    }

    final messageCount = await database.messageCount();
    final createdAt = DateTime.now().toUtc();
    final manifest = utf8.encode(jsonEncode({
      'schema': 60,
      'auth_user_id': authUserId,
      'created_at': createdAt.toIso8601String(),
      'message_count': messageCount,
      'media_bytes': mediaBytes,
      'include_videos': includeVideos,
    }));
    archive.addFile(
      ArchiveFile('manifest.json', manifest.length, manifest),
    );

    final zipped = ZipEncoder().encode(archive);
    final encrypted = await _encrypt(
      Uint8List.fromList(zipped),
      recoveryKey,
    );

    return BuiltChatBackup(
      bytes: encrypted,
      createdAt: createdAt,
      messageCount: messageCount,
      mediaBytes: mediaBytes,
    );
  }

  Future<void> restoreFromDrive({
    required String recoveryKey,
  }) async {
    final encrypted = await drive.downloadBackup(interactive: true);
    await restoreEncryptedBackup(
      encrypted,
      recoveryKey: recoveryKey,
    );
  }

  Future<void> restoreEncryptedBackup(
    Uint8List encrypted, {
    required String recoveryKey,
  }) async {
    final zipped = await _decrypt(encrypted, recoveryKey);
    final archive = ZipDecoder().decodeBytes(zipped, verify: true);

    final temp = await getTemporaryDirectory();
    final restoreDir = Directory(
      p.join(
        temp.path,
        'taskly_restore_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await restoreDir.create(recursive: true);

    try {
      for (final item in archive) {
        if (!item.isFile) continue;
        final safeName = p.normalize(item.name);
        if (p.isAbsolute(safeName) || safeName.startsWith('..')) {
          throw const FormatException('Unsafe backup path.');
        }
        final target = File(p.join(restoreDir.path, safeName));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(item.content as List<int>, flush: true);
      }

      final manifestFile = File(p.join(restoreDir.path, 'manifest.json'));
      final dbFile = File(p.join(restoreDir.path, 'db', 'taskly_chat.db'));
      if (!await manifestFile.exists() || !await dbFile.exists()) {
        throw const FormatException('Taskly backup is incomplete.');
      }

      final manifest = jsonDecode(await manifestFile.readAsString());
      if (manifest is! Map || manifest['schema'] != 60) {
        throw const FormatException('Unsupported Taskly backup version.');
      }

      await database.close();

      // Re-open once only to discover the correct per-user destination path.
      await database.openForUser(authUserId);
      final destinationDbPath = await database.databasePath();
      await database.close();

      final destinationDb = File(destinationDbPath);
      await destinationDb.parent.create(recursive: true);
      if (await destinationDb.exists()) await destinationDb.delete();
      for (final suffix in ['-wal', '-shm']) {
        final extra = File('$destinationDbPath$suffix');
        if (await extra.exists()) await extra.delete();
      }
      await dbFile.copy(destinationDbPath);

      final destinationMedia = Directory(await attachments.mediaRootPath());
      if (await destinationMedia.exists()) {
        await destinationMedia.delete(recursive: true);
      }
      await destinationMedia.create(recursive: true);

      final restoredMedia = Directory(p.join(restoreDir.path, 'media'));
      if (await restoredMedia.exists()) {
        await for (final entity in restoredMedia.list(recursive: true)) {
          if (entity is! File) continue;
          final relative = p.relative(entity.path, from: restoredMedia.path);
          final target = File(p.join(destinationMedia.path, relative));
          await target.parent.create(recursive: true);
          await entity.copy(target.path);
        }
      }

      await database.openForUser(authUserId);
      await database.cleanupMissingAttachments();
      await database.putSetting('restore_gate_skipped', '1');
      await database.putSetting(
        'restore_last_at',
        DateTime.now().toUtc().toIso8601String(),
      );
    } finally {
      if (await restoreDir.exists()) {
        await restoreDir.delete(recursive: true);
      }
    }
  }

  Future<Uint8List> _encrypt(
    Uint8List clear,
    String recoveryKey,
  ) async {
    final secret = SecretKey(keys.deriveAesKey(recoveryKey, authUserId));
    final box = await _aes.encrypt(clear, secretKey: secret);

    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(box.nonce.length)
      ..add(box.nonce)
      ..addByte(box.mac.bytes.length)
      ..add(box.mac.bytes)
      ..add(box.cipherText);
    return out.takeBytes();
  }

  Future<Uint8List> _decrypt(
    Uint8List encrypted,
    String recoveryKey,
  ) async {
    if (encrypted.length < _magic.length + 2) {
      throw const FormatException('Taskly backup is invalid.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (encrypted[i] != _magic[i]) {
        throw const FormatException('Not a Taskly v6 backup.');
      }
    }

    var offset = _magic.length;
    final nonceLength = encrypted[offset++];
    if (offset + nonceLength >= encrypted.length) {
      throw const FormatException('Invalid backup nonce.');
    }
    final nonce = encrypted.sublist(offset, offset + nonceLength);
    offset += nonceLength;

    final macLength = encrypted[offset++];
    if (offset + macLength >= encrypted.length) {
      throw const FormatException('Invalid backup authentication tag.');
    }
    final mac = encrypted.sublist(offset, offset + macLength);
    offset += macLength;

    final cipher = encrypted.sublist(offset);
    final secret = SecretKey(keys.deriveAesKey(recoveryKey, authUserId));
    final clear = await _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
      secretKey: secret,
    );
    return Uint8List.fromList(clear);
  }
}

class BuiltChatBackup {
  const BuiltChatBackup({
    required this.bytes,
    required this.createdAt,
    required this.messageCount,
    required this.mediaBytes,
  });

  final Uint8List bytes;
  final DateTime createdAt;
  final int messageCount;
  final int mediaBytes;
}
