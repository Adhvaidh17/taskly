import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackupKeyService {
  BackupKeyService({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Random _random = Random.secure();

  String _key(String authUserId) => 'taskly.v60.$authUserId.backup_key_64';

  Future<String> ensureRecoveryKey(String authUserId) async {
    final existing = await _storage.read(key: _key(authUserId));
    if (existing != null && RegExp(r'^\d{64}$').hasMatch(existing)) {
      return existing;
    }

    final buffer = StringBuffer();
    for (var i = 0; i < 64; i++) {
      buffer.write(_random.nextInt(10));
    }
    final value = buffer.toString();
    await _storage.write(key: _key(authUserId), value: value);
    return value;
  }

  Future<String?> recoveryKey(String authUserId) {
    return _storage.read(key: _key(authUserId));
  }

  Future<void> setRecoveryKey(String authUserId, String value) async {
    final normalized = value.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\d{64}$').hasMatch(normalized)) {
      throw const FormatException('Recovery key must contain exactly 64 digits.');
    }
    await _storage.write(key: _key(authUserId), value: normalized);
  }

  List<int> deriveAesKey(String recoveryKey, String authUserId) {
    final normalized = recoveryKey.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\d{64}$').hasMatch(normalized)) {
      throw const FormatException('Recovery key must contain exactly 64 digits.');
    }
    return sha256
        .convert('$normalized|taskly-backup-v60|$authUserId'.codeUnits)
        .bytes;
  }

  String grouped(String raw) {
    final value = raw.replaceAll(RegExp(r'\s+'), '');
    return [
      for (var i = 0; i < value.length; i += 4)
        value.substring(i, min(i + 4, value.length)),
    ].join(' ');
  }
}
