import 'package:flutter/material.dart';

import '../models/channel.dart';

class ForwardMessageSheet extends StatefulWidget {
  const ForwardMessageSheet({
    super.key,
    required this.conversations,
    this.title = 'Forward to',
    this.multiple = true,
  });

  final List<ConversationItem> conversations;
  final String title;
  final bool multiple;

  @override
  State<ForwardMessageSheet> createState() => _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends State<ForwardMessageSheet> {
  final Set<int> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.conversations
        .where((item) => item.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search chats and groups',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final item = visible[index];
                  final selected = _selected.contains(item.channelId);
                  return CheckboxListTile(
                    value: selected,
                    secondary: CircleAvatar(
                      child: Icon(item.isGroup
                          ? Icons.groups_rounded
                          : item.isSelfChat
                              ? Icons.bookmark_rounded
                              : Icons.person_rounded),
                    ),
                    title: Text(item.name),
                    subtitle: Text(item.isGroup
                        ? '${item.memberCount} members'
                        : item.isSelfChat
                            ? 'Your personal chat'
                            : 'Direct message'),
                    onChanged: (_) {
                      if (!widget.multiple) {
                        Navigator.pop(context, [item]);
                        return;
                      }
                      setState(() {
                        selected
                            ? _selected.remove(item.channelId)
                            : _selected.add(item.channelId);
                      });
                    },
                  );
                },
              ),
            ),
            if (widget.multiple)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            widget.conversations
                                .where((item) => _selected.contains(item.channelId))
                                .toList(),
                          ),
                  icon: const Icon(Icons.forward_rounded),
                  label: Text('Send to ${_selected.length}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
