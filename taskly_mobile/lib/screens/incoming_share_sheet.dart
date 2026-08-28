import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/files/attachment_policy.dart';
import '../models/channel.dart';
import '../providers/chat_provider.dart';
import '../services/incoming_share_service.dart';
import 'forward_message_sheet.dart';

Future<void> showIncomingShareFlow(
  BuildContext context,
  IncomingSharePayload payload,
) async {
  final chat = context.read<ChatProvider>();
  final target = await showModalBottomSheet<List<ConversationItem>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ForwardMessageSheet(
      conversations: chat.conversations,
      title: 'Share with Taskly',
      multiple: false,
    ),
  );
  if (target == null || target.isEmpty || !context.mounted) return;
  final conversation = target.first;
  try {
    if (payload.text.trim().isNotEmpty) {
      await chat.send(conversation: conversation, body: payload.text.trim());
    }
    for (final path in payload.files) {
      final validation = await AttachmentPolicy.validate(path);
      if (!validation.isValid) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(validation.error ?? 'Unsupported file')),
          );
        }
        continue;
      }
      await chat.sendAttachment(conversation: conversation, filePath: path);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shared to ${conversation.name}')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $error')));
    }
  }
}
