import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'backup_key_service.dart';
import 'chat_backup_service.dart';

class TransferSession {
  const TransferSession({
    required this.qrPayload,
    required this.close,
  });

  final String qrPayload;
  final Future<void> Function() close;
}

class LocalTransferService {
  LocalTransferService({
    required this.authUserId,
    required this.backup,
    required this.keys,
  });

  final String authUserId;
  final ChatBackupService backup;
  final BackupKeyService keys;

  static const _uuid = Uuid();

  Future<TransferSession> startSource({
    bool includeVideos = true,
  }) async {
    final recoveryKey = await keys.ensureRecoveryKey(authUserId);
    final built = await backup.buildEncryptedBackup(
      recoveryKey: recoveryKey,
      includeVideos: includeVideos,
    );

    final token = _uuid.v4();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final host = await _bestLanAddress();

    var consumed = false;
    server.listen((request) async {
      if (consumed ||
          request.uri.path != '/taskly-transfer' ||
          request.uri.queryParameters['token'] != token) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      consumed = true;
      request.response.headers.contentType = ContentType.binary;
      request.response.headers.set(
        HttpHeaders.contentLengthHeader,
        '${built.bytes.length}',
      );
      request.response.add(built.bytes);
      await request.response.close();
      await server.close(force: true);
    });

    final payload = Uri(
      scheme: 'taskly',
      host: 'transfer',
      queryParameters: {
        'v': '60',
        'host': host,
        'port': '${server.port}',
        'token': token,
        // Like a QR-assisted old-phone transfer: this one-time key is conveyed
        // by the QR, not by Taskly's server.
        'key': recoveryKey,
      },
    ).toString();

    return TransferSession(
      qrPayload: payload,
      close: () async {
        try {
          await server.close(force: true);
        } catch (_) {}
      },
    );
  }

  Future<void> receiveFromQr(String qrPayload) async {
    final uri = Uri.parse(qrPayload);
    if (uri.scheme != 'taskly' ||
        uri.host != 'transfer' ||
        uri.queryParameters['v'] != '60') {
      throw const FormatException('This is not a Taskly transfer QR.');
    }

    final host = uri.queryParameters['host'];
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    final token = uri.queryParameters['token'];
    final key = uri.queryParameters['key'];

    if (host == null || port == null || token == null || key == null) {
      throw const FormatException('Taskly transfer QR is incomplete.');
    }

    final url = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: '/taskly-transfer',
      queryParameters: {'token': token},
    );

    final response = await http.get(url).timeout(const Duration(minutes: 5));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Old phone rejected the transfer (${response.statusCode}).',
      );
    }

    await backup.restoreEncryptedBackup(
      Uint8List.fromList(response.bodyBytes),
      recoveryKey: key,
    );
    await keys.setRecoveryKey(authUserId, key);
  }

  Future<String> _bestLanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) return address.address;
      }
    }
    throw StateError(
      'Connect both phones to the same Wi-Fi network and try again.',
    );
  }
}
