import 'dart:io';

import 'package:flutter/material.dart';

import '../../local_chat/local_chat_database.dart';

class ChatInfoScreenV60 extends StatefulWidget {
  const ChatInfoScreenV60({
    super.key,
    required this.database,
    required this.channelId,
    required this.workspaceId,
    required this.title,
    required this.isGroup,
    this.avatarUrl,
    this.about,
    this.isOwnProfile = false,
    this.onEditOwnProfile,
    this.onSearchChat,
    this.onManageGroup,
    this.onBlock,
    this.onReport,
    this.onDeleteChat,
  });

  final LocalChatDatabase database;
  final int channelId;
  final int workspaceId;
  final String title;
  final bool isGroup;
  final String? avatarUrl;
  final String? about;
  final bool isOwnProfile;
  final VoidCallback? onEditOwnProfile;
  final VoidCallback? onSearchChat;
  final VoidCallback? onManageGroup;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;
  final Future<void> Function()? onDeleteChat;

  @override
  State<ChatInfoScreenV60> createState() => _ChatInfoScreenV60State();
}

class _ChatInfoScreenV60State extends State<ChatInfoScreenV60> {
  Map<String, dynamic>? _prefs;
  int _media = 0;
  int _links = 0;
  int _docs = 0;
  int _starred = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final results = await Future.wait([
      widget.database.mediaLinksDocs(widget.channelId, category: 'media'),
      widget.database.mediaLinksDocs(widget.channelId, category: 'links'),
      widget.database.mediaLinksDocs(widget.channelId, category: 'docs'),
      widget.database.starredMessages(widget.channelId),
    ]);
    final prefs = await widget.database.conversation(widget.channelId);

    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _media = results[0].length;
      _links = results[1].length;
      _docs = results[2].length;
      _starred = results[3].length;
    });
  }

  bool _flag(String name) => (_prefs?[name] as num? ?? 0).toInt() == 1;

  Future<void> _set({
    bool? muted,
    int? disappearingSeconds,
    bool? chatLocked,
    bool? advancedPrivacy,
  }) async {
    await widget.database.setConversationPreference(
      widget.channelId,
      muted: muted,
      disappearingSeconds: disappearingSeconds,
      chatLocked: chatLocked,
      advancedPrivacy: advancedPrivacy,
    );
    await _reload();
  }

  Future<void> _clearChat() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: const Text(
          'Messages and local media for this chat will be removed from '
          'this phone. There is no “removed from device” placeholder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.database.clearChat(widget.channelId);
    await _reload();
  }

  Future<void> _chooseDisappearing() async {
    final current = (_prefs?['disappearing_seconds'] as num?)?.toInt();
    final value = await showModalBottomSheet<int?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Disappearing messages',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final option in const [
              (label: 'Off', seconds: 0),
              (label: '24 hours', seconds: 86400),
              (label: '7 days', seconds: 604800),
              (label: '90 days', seconds: 7776000),
            ])
              ListTile(
                title: Text(option.label),
                trailing: Icon(
                  (current ?? 0) == option.seconds
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: (current ?? 0) == option.seconds
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onTap: () => Navigator.pop(context, option.seconds),
              ),
          ],
        ),
      ),
    );
    if (value == null) return;
    await _set(disappearingSeconds: value);
  }

  String _disappearingLabel() {
    final seconds = (_prefs?['disappearing_seconds'] as num?)?.toInt() ?? 0;
    if (seconds == 86400) return '24 hours';
    if (seconds == 604800) return '7 days';
    if (seconds == 7776000) return '90 days';
    return 'Off';
  }

  @override
  Widget build(BuildContext context) {
    final avatar = widget.avatarUrl;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isGroup ? 'Group info' : 'Chat info')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 53,
                      foregroundImage: avatar != null && avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: Text(
                        widget.title.isEmpty
                            ? '?'
                            : widget.title.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.isOwnProfile && widget.onEditOwnProfile != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton.filled(
                          onPressed: widget.onEditOwnProfile,
                          icon: const Icon(Icons.edit_rounded, size: 18),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  textAlign: TextAlign.center,
                ),
                if ((widget.about ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.about!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (!widget.isOwnProfile && !widget.isGroup)
                  const Padding(
                    padding: EdgeInsets.only(top: 9),
                    child: Text(
                      'You can view this person’s profile photo and status. '
                      'Only they can edit their actual profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),

          _Section(
            children: [
              ListTile(
                leading: const Icon(Icons.perm_media_rounded),
                title: const Text('Media, links and docs'),
                subtitle: Text(
                  '$_media media  ·  $_links links  ·  $_docs docs',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MediaLinksDocsScreenV60(
                      database: widget.database,
                      channelId: widget.channelId,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('Starred messages'),
                subtitle: Text('$_starred starred'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.search_rounded),
                title: const Text('Search'),
                onTap: widget.onSearchChat,
              ),
            ],
          ),

          _Section(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_off_outlined),
                title: const Text('Mute notifications'),
                value: _flag('muted'),
                onChanged: (value) => _set(muted: value),
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper_rounded),
                title: const Text('Chat theme & wallpaper'),
                subtitle: const Text('Choose this chat’s local appearance'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Disappearing messages'),
                subtitle: Text(_disappearingLabel()),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _chooseDisappearing,
              ),
            ],
          ),

          _Section(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline_rounded),
                title: const Text('Chat lock'),
                subtitle: const Text(
                  'Protect this chat with your device authentication',
                ),
                value: _flag('chat_locked'),
                onChanged: (value) => _set(chatLocked: value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.shield_outlined),
                title: const Text('Advanced chat privacy'),
                subtitle: const Text(
                  'Restrict export-like actions and sensitive previews',
                ),
                value: _flag('advanced_privacy'),
                onChanged: (value) => _set(advancedPrivacy: value),
              ),
              const ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('Encryption'),
                subtitle: Text(
                  'Messages are encrypted per recipient device while in transit.',
                ),
              ),
            ],
          ),

          if (widget.isGroup)
            _Section(
              children: [
                ListTile(
                  leading: const Icon(Icons.groups_rounded),
                  title: const Text('Participants & admins'),
                  subtitle: const Text(
                    'Members, admin roles, permissions and invite code',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onManageGroup,
                ),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Invite to group'),
                  onTap: widget.onManageGroup,
                ),
              ],
            ),

          _Section(
            children: [
              ListTile(
                leading: const Icon(Icons.storage_rounded),
                title: const Text('Manage storage'),
                subtitle: const Text(
                  'Review local media and documents for this chat',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MediaLinksDocsScreenV60(
                      database: widget.database,
                      channelId: widget.channelId,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Clear chat'),
                onTap: _clearChat,
              ),
            ],
          ),

          if (!widget.isGroup)
            _Section(
              danger: true,
              children: [
                if (widget.onBlock != null)
                  ListTile(
                    leading: const Icon(Icons.block_rounded),
                    title: const Text('Block'),
                    onTap: widget.onBlock,
                  ),
                if (widget.onReport != null)
                  ListTile(
                    leading: const Icon(Icons.report_outlined),
                    title: const Text('Report'),
                    onTap: widget.onReport,
                  ),
              ],
            ),

          if (widget.onDeleteChat != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await widget.onDeleteChat!();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete chat from this phone'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.children,
    this.danger = false,
  });

  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Card(
        child: Theme(
          data: Theme.of(context).copyWith(
            listTileTheme: ListTileThemeData(
              iconColor: danger ? Theme.of(context).colorScheme.error : null,
              textColor: danger ? Theme.of(context).colorScheme.error : null,
            ),
          ),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class MediaLinksDocsScreenV60 extends StatefulWidget {
  const MediaLinksDocsScreenV60({
    super.key,
    required this.database,
    required this.channelId,
  });

  final LocalChatDatabase database;
  final int channelId;

  @override
  State<MediaLinksDocsScreenV60> createState() =>
      _MediaLinksDocsScreenV60State();
}

class _MediaLinksDocsScreenV60State
    extends State<MediaLinksDocsScreenV60> {
  String _tab = 'media';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media, links and docs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'media', label: Text('Media')),
                ButtonSegment(value: 'links', label: Text('Links')),
                ButtonSegment(value: 'docs', label: Text('Docs')),
              ],
              selected: {_tab},
              onSelectionChanged: (value) {
                setState(() => _tab = value.first);
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: widget.database.mediaLinksDocs(
                widget.channelId,
                category: _tab,
              ),
              builder: (context, snapshot) {
                final rows = snapshot.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return Center(child: Text('No ${_tab == 'docs' ? 'documents' : _tab}.'));
                }

                if (_tab == 'media') {
                  return GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final path = row['attachment_path'] as String?;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: path != null &&
                                (row['attachment_mime_type'] as String?)
                                        ?.startsWith('image/') ==
                                    true &&
                                File(path).existsSync()
                            ? Image.file(File(path), fit: BoxFit.cover)
                            : ColoredBox(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: const Icon(Icons.movie_outlined),
                              ),
                      );
                    },
                  );
                }

                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      leading: Icon(
                        _tab == 'links'
                            ? Icons.link_rounded
                            : Icons.insert_drive_file_outlined,
                      ),
                      title: Text(
                        _tab == 'links'
                            ? row['body'] as String? ?? ''
                            : row['attachment_name'] as String? ?? 'Document',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
