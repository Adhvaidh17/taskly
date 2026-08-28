import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/files/attachment_policy.dart';
import '../core/supabase/taskly_supabase.dart';
import '../models/message.dart';

class PreparedLocalMedia {
  const PreparedLocalMedia({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;

  bool get isImage => mimeType.startsWith('image/');
}

class LocalMediaResolution {
  const LocalMediaResolution._({
    this.path,
    required this.unavailable,
    required this.downloading,
  });

  const LocalMediaResolution.available(String path)
      : this._(path: path, unavailable: false, downloading: false);

  const LocalMediaResolution.missing()
      : this._(unavailable: true, downloading: false);

  const LocalMediaResolution.pending()
      : this._(unavailable: false, downloading: true);

  final String? path;
  final bool unavailable;
  final bool downloading;
}

/// Keeps Taskly media device-local while Supabase remains only the transport.
///
/// Android native storage root:
/// `Android/media/<package>/Taskly/Media/Taskly Images[/Sent]`
/// `Android/media/<package>/Taskly/Media/Taskly Documents[/Sent]`
/// `Android/media/<package>/Taskly/Media/Taskly Video[/Sent]`
/// `Android/media/<package>/Taskly/Media/Taskly Audio[/Sent]`
/// `Android/media/<package>/Taskly/Attachments[/Sent]`
///
/// iOS uses the equivalent Taskly hierarchy in the app Documents sandbox.
/// The database never receives these device paths.
class LocalMediaService {
  LocalMediaService();

  static const MethodChannel _channel = MethodChannel('taskly/media');
  static const _pathPrefix = 'taskly_media_path_v41_';
  static const _missingPrefix = 'taskly_media_missing_v41_';
  static const _taskPathPrefix = 'taskly_task_attachment_path_v42_';
  static const _taskMissingPrefix = 'taskly_task_attachment_missing_v42_';

  Future<PreparedLocalMedia> prepareOutgoing(String originalPath) async {
    final validation = await AttachmentPolicy.validate(originalPath);
    if (!validation.isValid) {
      throw ArgumentError(validation.error ?? 'Unsupported attachment');
    }

    final fallbackMime = validation.mimeType ??
        lookupMimeType(originalPath) ??
        'application/octet-stream';
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'prepareOutgoing',
        {
          'path': originalPath,
          'mimeType': fallbackMime,
          'maxDimension': 1600,
          'jpegQuality': 78,
        },
      );
      if (raw != null) {
        final path = '${raw['path'] ?? ''}'.trim();
        if (path.isNotEmpty && await File(path).exists()) {
          final file = File(path);
          return PreparedLocalMedia(
            path: path,
            name: '${raw['name'] ?? file.uri.pathSegments.last}',
            mimeType: '${raw['mimeType'] ?? fallbackMime}',
            sizeBytes: await file.length(),
          );
        }
      }
    } catch (error) {
      debugPrint('TASKLY_MEDIA_PREPARE_NATIVE_FALLBACK $error');
    }

    final file = File(originalPath);
    return PreparedLocalMedia(
      path: originalPath,
      name: file.uri.pathSegments.last,
      mimeType: fallbackMime,
      sizeBytes: await file.length(),
    );
  }

  Future<PreparedLocalMedia> prepareTaskAttachmentOutgoing(
      String originalPath) async {
    final validation = await AttachmentPolicy.validate(originalPath);
    if (!validation.isValid) {
      throw ArgumentError(validation.error ?? 'Unsupported attachment');
    }
    final mimeType = validation.mimeType ??
        lookupMimeType(originalPath) ??
        'application/octet-stream';
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'prepareTaskAttachmentOutgoing',
      {'path': originalPath, 'mimeType': mimeType},
    );
    final path = '${raw?['path'] ?? ''}'.trim();
    if (path.isEmpty || !await File(path).exists()) {
      throw const FileSystemException(
          'Task attachment could not be copied locally.');
    }
    final file = File(path);
    return PreparedLocalMedia(
      path: path,
      name: '${raw?['name'] ?? file.uri.pathSegments.last}',
      mimeType: '${raw?['mimeType'] ?? mimeType}',
      sizeBytes: await file.length(),
    );
  }

  Future<void> removeTaskAttachmentLocal(int attachmentId) async {
    if (attachmentId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('$_taskPathPrefix$attachmentId')?.trim() ?? '';
    if (path.isNotEmpty) {
      try {
        await _channel.invokeMethod<void>('deleteLocalFile', {'path': path});
      } catch (error) {
        debugPrint(
            'TASKLY_TASK_ATTACHMENT_LOCAL_DELETE_ERROR id=$attachmentId $error');
      }
    }
    await prefs.remove('$_taskPathPrefix$attachmentId');
    await prefs.setBool('$_taskMissingPrefix$attachmentId', true);
  }

  Future<void> bindTaskAttachment(int attachmentId, String path) async {
    if (attachmentId <= 0 || path.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_taskPathPrefix$attachmentId', path);
    await prefs.remove('$_taskMissingPrefix$attachmentId');
  }

  Future<LocalMediaResolution> existingTaskAttachment(int attachmentId) async {
    if (attachmentId <= 0) return const LocalMediaResolution.pending();
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('$_taskPathPrefix$attachmentId')?.trim() ?? '';
    if (path.isNotEmpty) {
      if (await File(path).exists()) {
        return LocalMediaResolution.available(path);
      }
      await prefs.setBool('$_taskMissingPrefix$attachmentId', true);
      return const LocalMediaResolution.missing();
    }
    if (prefs.getBool('$_taskMissingPrefix$attachmentId') == true) {
      return const LocalMediaResolution.missing();
    }
    return const LocalMediaResolution.pending();
  }

  Future<LocalMediaResolution> downloadTaskAttachment({
    required int attachmentId,
    required String bucket,
    required String remotePath,
    required String name,
    required String mimeType,
    required TasklySupabase backend,
  }) async {
    final existing = await existingTaskAttachment(attachmentId);
    if (existing.path != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_taskMissingPrefix$attachmentId');
    try {
      final bytes = await backend.downloadTaskAttachment(
        bucket: bucket,
        path: remotePath,
      );
      if (bytes.isEmpty) return const LocalMediaResolution.missing();
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'saveTaskAttachmentIncoming',
        {
          'bytes': bytes,
          'name': name,
          'mimeType': mimeType,
        },
      );
      final localPath = '${raw?['path'] ?? ''}'.trim();
      if (localPath.isEmpty || !await File(localPath).exists()) {
        return const LocalMediaResolution.missing();
      }
      await bindTaskAttachment(attachmentId, localPath);
      return LocalMediaResolution.available(localPath);
    } catch (error) {
      debugPrint(
          'TASKLY_TASK_ATTACHMENT_DOWNLOAD_ERROR id=$attachmentId $error');
      return const LocalMediaResolution.pending();
    }
  }

  Future<void> bindMessage(int messageId, String path) async {
    if (messageId <= 0 || path.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_pathPrefix$messageId', path);
    await prefs.remove('$_missingPrefix$messageId');
  }

  Future<LocalMediaResolution> existingForMessage(int messageId) async {
    if (messageId <= 0) return const LocalMediaResolution.pending();
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('$_pathPrefix$messageId')?.trim() ?? '';
    if (path.isNotEmpty) {
      if (await File(path).exists()) {
        return LocalMediaResolution.available(path);
      }
      await prefs.setBool('$_missingPrefix$messageId', true);
      return const LocalMediaResolution.missing();
    }
    if (prefs.getBool('$_missingPrefix$messageId') == true) {
      return const LocalMediaResolution.missing();
    }
    return const LocalMediaResolution.pending();
  }

  Future<LocalMediaResolution> ensureMessageLocal({
    required MessageItem message,
    required TasklySupabase backend,
    required bool sentByMe,
  }) async {
    if (!message.hasAttachment || message.id <= 0) {
      return const LocalMediaResolution.missing();
    }

    final existing = await existingForMessage(message.id);
    if (existing.path != null || existing.unavailable) return existing;

    final bucket = message.attachmentBucket?.trim() ?? '';
    final remotePath = message.attachmentPath?.trim() ?? '';
    if (bucket.isEmpty || remotePath.isEmpty) {
      return const LocalMediaResolution.missing();
    }

    try {
      final Uint8List bytes = await backend.downloadMessageAttachment(
        bucket: bucket,
        path: remotePath,
      );
      if (bytes.isEmpty) return const LocalMediaResolution.missing();
      final name = (message.attachmentName?.trim().isNotEmpty == true)
          ? message.attachmentName!.trim()
          : remotePath.split('/').last;
      final mimeType = message.attachmentMimeType?.trim().isNotEmpty == true
          ? message.attachmentMimeType!.trim()
          : (lookupMimeType(name) ?? 'application/octet-stream');

      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'saveIncoming',
        {
          'bytes': bytes,
          'name': name,
          'mimeType': mimeType,
          'sent': sentByMe,
        },
      );
      final localPath = '${raw?['path'] ?? ''}'.trim();
      if (localPath.isEmpty || !await File(localPath).exists()) {
        return const LocalMediaResolution.missing();
      }
      await bindMessage(message.id, localPath);
      return LocalMediaResolution.available(localPath);
    } catch (error) {
      debugPrint('TASKLY_MEDIA_DOWNLOAD_ERROR messageId=${message.id} $error');
      // Network/server failure is not recorded as a permanent local deletion.
      return const LocalMediaResolution.pending();
    }
  }

  Future<void> openFile(String path, {String? mimeType}) async {
    if (!await File(path).exists()) {
      throw const FileSystemException(
          'This file is not available on this device.');
    }
    await _channel.invokeMethod<void>('openFile', {
      'path': path,
      'mimeType':
          mimeType ?? lookupMimeType(path) ?? 'application/octet-stream',
    });
  }

  Future<String?> mediaRoot() async {
    try {
      return await _channel.invokeMethod<String>('mediaRoot');
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAllLocalMedia() async {
    try {
      await _channel.invokeMethod<void>('clearMedia');
    } finally {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
            (key) =>
                key.startsWith(_pathPrefix) ||
                key.startsWith(_missingPrefix) ||
                key.startsWith(_taskPathPrefix) ||
                key.startsWith(_taskMissingPrefix),
          );
      for (final key in keys.toList(growable: false)) {
        await prefs.remove(key);
      }
    }
  }
}
