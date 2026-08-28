import 'dart:io';

import 'package:mime/mime.dart';

class AttachmentPolicy {
  static const int maxBytes = 25 * 1024 * 1024;

  static const Set<String> allowedExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'txt', 'csv', 'md', 'rtf',
    'zip', 'rar', '7z',
    'mp3', 'm4a', 'aac', 'wav', 'ogg',
    'mp4', 'mov', 'm4v', 'webm',
  };


  static const Set<String> allowedMimeTypes = {
    'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif',
    'application/pdf', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain', 'text/csv', 'text/markdown', 'text/rtf', 'application/rtf',
    'application/zip', 'application/x-zip-compressed',
    'application/vnd.rar', 'application/x-rar-compressed',
    'application/x-7z-compressed',
    'audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/aac',
    'audio/wav', 'audio/x-wav', 'audio/ogg',
    'video/mp4', 'video/quicktime', 'video/x-m4v', 'video/webm',
  };

  static const Set<String> imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif',
  };

  static const Set<String> videoExtensions = {'mp4', 'mov', 'm4v', 'webm'};

  static String extension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String? mimeType(String path, {List<int>? headerBytes}) {
    return lookupMimeType(path, headerBytes: headerBytes);
  }

  static bool isImage(String? mimeType, String path) {
    return mimeType?.startsWith('image/') == true ||
        imageExtensions.contains(extension(path));
  }

  static bool isVideo(String? mimeType, String path) {
    return mimeType?.startsWith('video/') == true ||
        videoExtensions.contains(extension(path));
  }

  static Future<AttachmentValidation> validate(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const AttachmentValidation.invalid('The shared file is unavailable.');
    }
    final size = await file.length();
    if (size <= 0) {
      return const AttachmentValidation.invalid('The file is empty.');
    }
    if (size > maxBytes) {
      return const AttachmentValidation.invalid('Files must be 25 MB or smaller.');
    }
    final ext = extension(path);
    final mime = mimeType(path);
    final allowedMime = mime != null && allowedMimeTypes.contains(mime);
    if (!allowedExtensions.contains(ext) && !allowedMime) {
      return AttachmentValidation.invalid(
        ext.isEmpty ? 'This file type is not supported.' : '.$ext files are not supported.',
      );
    }
    return AttachmentValidation.valid(sizeBytes: size, mimeType: mime);
  }

  static const String supportedFormatsLabel =
      'Images: JPG, JPEG, PNG, GIF, WEBP, HEIC, HEIF · '
      'Documents: PDF, DOC, DOCX, XLS, XLSX, PPT, PPTX, TXT, CSV, MD, RTF · '
      'Archives: ZIP, RAR, 7Z · Audio: MP3, M4A, AAC, WAV, OGG · '
      'Video: MP4, MOV, M4V, WEBM · Maximum 25 MB per file.';
}

class AttachmentValidation {
  const AttachmentValidation._({
    required this.isValid,
    this.error,
    this.sizeBytes,
    this.mimeType,
  });

  const AttachmentValidation.valid({required int sizeBytes, String? mimeType})
      : this._(isValid: true, sizeBytes: sizeBytes, mimeType: mimeType);

  const AttachmentValidation.invalid(String error)
      : this._(isValid: false, error: error);

  final bool isValid;
  final String? error;
  final int? sizeBytes;
  final String? mimeType;
}
