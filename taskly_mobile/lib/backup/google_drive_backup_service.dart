import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class DriveBackupMetadata {
  const DriveBackupMetadata({
    required this.backupFileId,
    required this.modifiedAt,
    required this.sizeBytes,
    this.messageCount,
    this.mediaBytes,
  });

  final String backupFileId;
  final DateTime modifiedAt;
  final int sizeBytes;
  final int? messageCount;
  final int? mediaBytes;
}

class GoogleDriveBackupService {
  GoogleDriveBackupService();

  static const backupName = 'taskly-chat-backup-v60.bin';
  static const metadataName = 'taskly-chat-backup-v60.json';
  static const List<String> _scopes = <String>[
    drive.DriveApi.driveAppdataScope,
  ];

  static final GoogleSignIn _signIn = GoogleSignIn.instance;
  static Future<void>? _initialization;
  static StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  static GoogleSignInAccount? _account;

  GoogleSignInAccount? get currentAccount => _account;

  Future<void> _ensureInitialized() {
    return _initialization ??= _initializeShared();
  }

  static Future<void> _initializeShared() async {
    await _signIn.initialize();

    _events ??= _signIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _account = event.user;
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _account = null;
      }
    });

    final lightweight = _signIn.attemptLightweightAuthentication();
    if (lightweight != null) {
      try {
        final account = await lightweight;
        if (account != null) _account = account;
      } on GoogleSignInException {
        // Silent auth is best-effort. Interactive auth happens on user action.
      }
    }
  }

  Future<GoogleSignInAccount?> signIn({
    bool interactive = true,
  }) async {
    await _ensureInitialized();

    final existing = _account;
    if (existing != null) return existing;
    if (!interactive) return null;

    if (!_signIn.supportsAuthenticate()) {
      throw StateError(
        'Interactive Google Sign-In is not supported on this platform.',
      );
    }

    final account = await _signIn.authenticate(scopeHint: _scopes);
    _account = account;
    return account;
  }

  Future<void> signOut() async {
    await _ensureInitialized();
    await _signIn.signOut();
    _account = null;
  }

  Future<Map<String, String>> _authorizationHeaders(
    GoogleSignInAccount account, {
    required bool interactive,
  }) async {
    var headers = await account.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: false,
    );

    if (headers == null && interactive) {
      headers = await account.authorizationClient.authorizationHeaders(
        _scopes,
        promptIfNecessary: true,
      );
    }

    if (headers == null) {
      throw StateError(
        'Google Drive access has not been authorized. '
        'Tap Back up now or Restore to authorize it.',
      );
    }
    return headers;
  }

  Future<drive.DriveApi> _api({
    bool interactive = true,
  }) async {
    final account = await signIn(interactive: interactive);
    if (account == null) {
      throw StateError('Google Drive account is not connected.');
    }

    final headers = await _authorizationHeaders(
      account,
      interactive: interactive,
    );
    return drive.DriveApi(_GoogleAuthClient(headers));
  }

  Future<DriveBackupMetadata?> findBackup({
    bool interactive = false,
  }) async {
    final api = await _api(interactive: interactive);
    return _findBackupWithApi(api);
  }

  Future<DriveBackupMetadata?> _findBackupWithApi(
    drive.DriveApi api,
  ) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$backupName' and trashed = false",
      $fields: 'files(id,name,modifiedTime,size)',
      pageSize: 10,
    );

    final files = list.files ?? const <drive.File>[];
    if (files.isEmpty) return null;

    files.sort((a, b) {
      final av = a.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bv = b.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bv.compareTo(av);
    });

    final file = files.first;
    final backupId = file.id;
    if (backupId == null || backupId.isEmpty) return null;

    int? messageCount;
    int? mediaBytes;

    try {
      final metaList = await api.files.list(
        spaces: 'appDataFolder',
        q: "name = '$metadataName' and trashed = false",
        $fields: 'files(id,modifiedTime)',
        pageSize: 1,
      );

      final metaFiles = metaList.files ?? const <drive.File>[];
      final metadataId =
          metaFiles.isEmpty ? null : metaFiles.first.id;

      if (metadataId != null) {
        final bytes = await _downloadFile(api, metadataId);
        final value = jsonDecode(utf8.decode(bytes));
        if (value is Map) {
          messageCount = (value['message_count'] as num?)?.toInt();
          mediaBytes = (value['media_bytes'] as num?)?.toInt();
        }
      }
    } catch (_) {
      // Metadata is optional. The encrypted binary is authoritative.
    }

    return DriveBackupMetadata(
      backupFileId: backupId,
      modifiedAt: file.modifiedTime ?? DateTime.now().toUtc(),
      sizeBytes: int.tryParse(file.size ?? '') ?? 0,
      messageCount: messageCount,
      mediaBytes: mediaBytes,
    );
  }

  Future<DriveBackupMetadata> upload({
    required Uint8List encryptedBytes,
    required Map<String, dynamic> metadata,
  }) async {
    final api = await _api(interactive: true);

    final backupId = await _upsert(
      api,
      name: backupName,
      bytes: encryptedBytes,
      mimeType: 'application/octet-stream',
    );

    await _upsert(
      api,
      name: metadataName,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode(metadata)),
      ),
      mimeType: 'application/json',
    );

    return DriveBackupMetadata(
      backupFileId: backupId,
      modifiedAt: DateTime.now().toUtc(),
      sizeBytes: encryptedBytes.length,
      messageCount: (metadata['message_count'] as num?)?.toInt(),
      mediaBytes: (metadata['media_bytes'] as num?)?.toInt(),
    );
  }

  Future<Uint8List> downloadBackup({
    bool interactive = true,
  }) async {
    final api = await _api(interactive: interactive);
    final info = await _findBackupWithApi(api);
    if (info == null) {
      throw StateError('No Taskly Google Drive backup was found.');
    }
    return _downloadFile(api, info.backupFileId);
  }

  Future<String> _upsert(
    drive.DriveApi api, {
    required String name,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final existing = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$name' and trashed = false",
      $fields: 'files(id)',
      pageSize: 1,
    );

    final media = drive.Media(
      Stream<List<int>>.value(bytes),
      bytes.length,
      contentType: mimeType,
    );

    final existingFiles = existing.files ?? const <drive.File>[];
    if (existingFiles.isNotEmpty) {
      final id = existingFiles.first.id;
      if (id == null) {
        throw StateError('Google Drive returned an invalid file ID.');
      }
      await api.files.update(
        drive.File(),
        id,
        uploadMedia: media,
        $fields: 'id',
      );
      return id;
    }

    final file = drive.File()
      ..name = name
      ..parents = const <String>['appDataFolder'];

    final created = await api.files.create(
      file,
      uploadMedia: media,
      $fields: 'id',
    );

    final id = created.id;
    if (id == null) {
      throw StateError('Google Drive did not return a backup file ID.');
    }
    return id;
  }

  Future<Uint8List> _downloadFile(
    drive.DriveApi api,
    String id,
  ) async {
    final response = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (response is! drive.Media) {
      throw StateError('Unexpected Google Drive download response.');
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this.headers);

  final Map<String, String> headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
