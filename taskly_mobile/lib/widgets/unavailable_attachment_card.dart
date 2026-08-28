import 'package:flutter/material.dart';

import '../models/message.dart';

class UnavailableAttachmentCard extends StatelessWidget {
  const UnavailableAttachmentCard({
    super.key,
    required this.message,
    required this.currentProfileId,
  });

  final MessageItem message;
  final int currentProfileId;

  String get _kind {
    final mime = message.attachmentMimeType ?? '';
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    return 'attachment';
  }

  IconData get _icon {
    final mime = message.attachmentMimeType ?? '';
    if (mime.startsWith('image/')) return Icons.broken_image_outlined;
    if (mime.startsWith('video/')) return Icons.video_file_outlined;
    if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String get _text {
    if (message.isMine(currentProfileId)) {
      return 'This $_kind is not available on this device.';
    }
    final name = message.sender.name.trim().isEmpty
        ? 'the sender'
        : message.sender.name.trim();
    return "This $_kind is not available on $name's device.";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .65),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_icon, size: 21, color: color),
            ),
            const SizedBox(width: 11),
            Flexible(
              child: Text(
                _text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
