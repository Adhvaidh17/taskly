import 'package:flutter/material.dart';

import 'taskly_ai_theme_v62.dart';

class MessageActionCallbacksV62 {
  const MessageActionCallbacksV62({
    this.onReact,
    this.onCopy,
    this.onReply,
    this.onForward,
    this.onStar,
    this.onInfo,
    this.onDelete,
  });

  final ValueChanged<String>? onReact;
  final VoidCallback? onCopy;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onStar;
  final VoidCallback? onInfo;
  final VoidCallback? onDelete;
}

Future<void> showMessageActionSheetV62({
  required BuildContext context,
  required String messagePreview,
  required MessageActionCallbacksV62 callbacks,
}) {
  const reactions = ['❤️', '👍', '😂', '😮', '😢', '🙏'];
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(messagePreview, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
          Text('React', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: reactions.map((reaction) {
              return InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: callbacks.onReact == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        callbacks.onReact!(reaction);
                      },
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Text(reaction, style: const TextStyle(fontSize: 25)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          if (callbacks.onCopy != null)
            _action(sheetContext, Icons.copy_rounded, 'Copy', callbacks.onCopy!),
          if (callbacks.onReply != null)
            _action(sheetContext, Icons.reply_rounded, 'Reply', callbacks.onReply!),
          if (callbacks.onForward != null)
            _action(sheetContext, Icons.forward_rounded, 'Forward', callbacks.onForward!),
          if (callbacks.onStar != null)
            _action(sheetContext, Icons.star_border_rounded, 'Star', callbacks.onStar!),
          if (callbacks.onInfo != null)
            _action(sheetContext, Icons.info_outline_rounded, 'Message info', callbacks.onInfo!),
          if (callbacks.onDelete != null)
            _action(
              sheetContext,
              Icons.delete_outline_rounded,
              'Delete',
              callbacks.onDelete!,
              destructive: true,
            ),
        ],
      ),
    ),
  );
}

Widget _action(
  BuildContext sheetContext,
  IconData icon,
  String label,
  VoidCallback callback, {
  bool destructive = false,
}) {
  final color = destructive ? Theme.of(sheetContext).colorScheme.error : null;
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(label, style: TextStyle(color: color)),
    onTap: () {
      Navigator.pop(sheetContext);
      callback();
    },
  );
}
