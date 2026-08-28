import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.publicKeyBase64,
  });

  final String deviceId;
  final String publicKeyBase64;
}

class EncryptedEnvelope {
  const EncryptedEnvelope({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
    required this.senderPublicKey,
  });

  final String ciphertext;
  final String nonce;
  final String mac;
  final String senderPublicKey;
}

class DeviceCryptoService {
  DeviceCryptoService({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  static const _uuid = Uuid();

  String _key(String authUserId, String suffix) =>
      'taskly.v60.$authUserId.$suffix';

  Future<DeviceIdentity> ensureIdentity(String authUserId) async {
    var deviceId = await _storage.read(key: _key(authUserId, 'device_id'));
    var privateB64 =
        await _storage.read(key: _key(authUserId, 'x25519_private'));
    var publicB64 =
        await _storage.read(key: _key(authUserId, 'x25519_public'));

    if (deviceId == null || privateB64 == null || publicB64 == null) {
      final pair = await _x25519.newKeyPair();
      final privateBytes = await pair.extractPrivateKeyBytes();
      final publicKey = await pair.extractPublicKey();

      deviceId = _uuid.v4();
      privateB64 = base64Encode(privateBytes);
      publicB64 = base64Encode(publicKey.bytes);

      await _storage.write(
        key: _key(authUserId, 'device_id'),
        value: deviceId,
      );
      await _storage.write(
        key: _key(authUserId, 'x25519_private'),
        value: privateB64,
      );
      await _storage.write(
        key: _key(authUserId, 'x25519_public'),
        value: publicB64,
      );
    }

    return DeviceIdentity(
      deviceId: deviceId,
      publicKeyBase64: publicB64,
    );
  }

  Future<SimpleKeyPairData> _ownKeyPair(String authUserId) async {
    final identity = await ensureIdentity(authUserId);
    final privateB64 =
        await _storage.read(key: _key(authUserId, 'x25519_private'));
    if (privateB64 == null) {
      throw StateError('Taskly device private key is missing.');
    }

    return SimpleKeyPairData(
      base64Decode(privateB64),
      publicKey: SimplePublicKey(
        base64Decode(identity.publicKeyBase64),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }

  Future<EncryptedEnvelope> encryptJson({
    required String authUserId,
    required String remotePublicKeyBase64,
    required String clientMessageId,
    required Map<String, dynamic> payload,
  }) async {
    final own = await _ownKeyPair(authUserId);
    final ownPublic = await own.extractPublicKey();
    final remote = SimplePublicKey(
      base64Decode(remotePublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final shared = await _x25519.sharedSecretKey(
      keyPair: own,
      remotePublicKey: remote,
    );
    final sharedBytes = await shared.extractBytes();
    final keyBytes = _deriveAesKey(sharedBytes, clientMessageId);

    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(keyBytes),
    );

    return EncryptedEnvelope(
      ciphertext: base64Encode(box.cipherText),
      nonce: base64Encode(box.nonce),
      mac: base64Encode(box.mac.bytes),
      senderPublicKey: base64Encode(ownPublic.bytes),
    );
  }

  Future<Map<String, dynamic>> decryptJson({
    required String authUserId,
    required String senderPublicKeyBase64,
    required String clientMessageId,
    required String ciphertextBase64,
    required String nonceBase64,
    required String macBase64,
  }) async {
    final own = await _ownKeyPair(authUserId);
    final senderPublic = SimplePublicKey(
      base64Decode(senderPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final shared = await _x25519.sharedSecretKey(
      keyPair: own,
      remotePublicKey: senderPublic,
    );
    final sharedBytes = await shared.extractBytes();
    final keyBytes = _deriveAesKey(sharedBytes, clientMessageId);

    final box = SecretBox(
      base64Decode(ciphertextBase64),
      nonce: base64Decode(nonceBase64),
      mac: Mac(base64Decode(macBase64)),
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: SecretKey(keyBytes),
    );

    final value = jsonDecode(utf8.decode(clear));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Taskly encrypted message payload.');
    }
    return value;
  }

  Uint8List _deriveAesKey(List<int> sharedSecret, String clientMessageId) {
    final context = utf8.encode('taskly-chat-v60:$clientMessageId');
    final digest = hashes.sha256.convert(<int>[
      ...sharedSecret,
      ...context,
    ]);
    return Uint8List.fromList(digest.bytes);
  }

  Future<void> destroyDeviceIdentity(String authUserId) async {
    for (final suffix in const [
      'device_id',
      'x25519_private',
      'x25519_public',
    ]) {
      await _storage.delete(key: _key(authUserId, suffix));
    }
  }
}
