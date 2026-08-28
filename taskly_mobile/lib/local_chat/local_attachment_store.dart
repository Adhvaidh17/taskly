import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class LocalAttachmentStore {
  LocalAttachmentStore(this.authUserId);

  final String authUserId;
  static const _uuid = Uuid();

  Future<Directory> _base() async {
    final support = await getApplicationSupportDirectory();
    final safeUser =
        authUserId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final dir = Directory(
      p.join(support.path, 'taskly_local_chat', safeUser, 'media'),
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> channelDirectory(int channelId) async {
    final base = await _base();
    final dir = Directory(p.join(base.path, '$channelId'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> importOutgoing({
    required int channelId,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Attachment does not exist', sourcePath);
    }
    final dir = await channelDirectory(channelId);
    final ext = p.extension(sourcePath);
    final target = File(p.join(dir.path, '${_uuid.v4()}$ext'));
    await source.copy(target.path);
    return target.path;
  }

  Future<String> writeIncoming({
    required int channelId,
    required String originalName,
    required Uint8List bytes,
  }) async {
    final dir = await channelDirectory(channelId);
    final ext = p.extension(originalName);
    final target = File(p.join(dir.path, '${_uuid.v4()}$ext'));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<Uint8List> read(String path) => File(path).readAsBytes();

  Future<void> remove(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<int> totalBytes() async {
    final base = await _base();
    var bytes = 0;
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }

  Future<void> clearAll() async {
    final base = await _base();
    if (await base.exists()) await base.delete(recursive: true);
  }

  Future<String> mediaRootPath() async => (await _base()).path;
}
