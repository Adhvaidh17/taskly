import 'dart:io';

import 'package:flutter/material.dart';

import '../local_chat/local_chat_database.dart';
import 'ai_universe_shell_v62.dart';
import 'taskly_ai_theme_v62.dart';

class ChatInfoScreenV62 extends StatefulWidget {
  const ChatInfoScreenV62({
    super.key,
    required this.database,
    required this.channelId,
    required this.title,
    required this.isGroup,
    this.avatarUrl,
    this.status,
    this.about,
    this.isOwnProfile = false,
    this.canEditGroupInfo = false,
    this.onEditProfilePhoto,
    this.onEditStatus,
    this.onEditGroupInfo,
    this.onAudioCall,
    this.onVideoCall,
    this.onSearchChat,
    this.onOpenTasks,
    this.onToggleFavourite,
    this.isFavourite = false,
    this.onMediaVisibility,
    this.onEncryptionDetails,
    this.onGroupsInCommon,
    this.onAddContact,
    this.onManageGroup,
    this.onCustomNotifications,
    this.onChatWallpaper,
    this.onExportChat,
    this.onBlock,
    this.onReport,
    this.onExitGroup,
    this.onDeleteChat,
  });

  final LocalChatDatabase database;
  final int channelId;
  final String title;
  final bool isGroup;
  final String? avatarUrl;
  final String? status;
  final String? about;
  final bool isOwnProfile;
  final bool canEditGroupInfo;
  final VoidCallback? onEditProfilePhoto;
  final VoidCallback? onEditStatus;
  final VoidCallback? onEditGroupInfo;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onSearchChat;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onToggleFavourite;
  final bool isFavourite;
  final VoidCallback? onMediaVisibility;
  final VoidCallback? onEncryptionDetails;
  final VoidCallback? onGroupsInCommon;
  final VoidCallback? onAddContact;
  final VoidCallback? onManageGroup;
  final VoidCallback? onCustomNotifications;
  final VoidCallback? onChatWallpaper;
  final VoidCallback? onExportChat;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;
  final Future<void> Function()? onExitGroup;
  final Future<void> Function()? onDeleteChat;

  @override
  State<ChatInfoScreenV62> createState() => _ChatInfoScreenV62State();
}

class _ChatInfoScreenV62State extends State<ChatInfoScreenV62> {
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
      _media = _existingMedia(results[0]).length;
      _links = results[1].length;
      _docs = _existingDocs(results[2]).length;
      _starred = results[3].length;
    });
  }

  List<Map<String, dynamic>> _existingMedia(List<Map<String, dynamic>> rows) {
    return rows.where((row) {
      final path = row['attachment_path'] as String?;
      return path != null && path.isNotEmpty && File(path).existsSync();
    }).toList();
  }

  List<Map<String, dynamic>> _existingDocs(List<Map<String, dynamic>> rows) {
    return rows.where((row) {
      final path = row['attachment_path'] as String?;
      return path == null || path.isEmpty || File(path).existsSync();
    }).toList();
  }

  bool _flag(String key) => (_prefs?[key] as num? ?? 0).toInt() == 1;

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
          'Messages and local media for this chat will be deleted from this phone. Deleted attachments disappear completely; no “removed from device” placeholder is kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (yes != true) return;
    await widget.database.clearChat(widget.channelId);
    await _reload();
  }

  Future<void> _chooseDisappearing() async {
    final current = (_prefs?['disappearing_seconds'] as num?)?.toInt() ?? 0;
    final value = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) Navigator.pop(context, value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Disappearing messages', style: TextStyle(fontWeight: FontWeight.w800))),
              for (final option in const [
                (label: 'Off', seconds: 0),
                (label: '24 hours', seconds: 86400),
                (label: '7 days', seconds: 604800),
                (label: '90 days', seconds: 7776000),
              ])
                RadioListTile<int>(
                  value: option.seconds,
                  title: Text(option.label),
                ),
            ],
          ),
        ),
      ),
    );
    if (value != null) await _set(disappearingSeconds: value);
  }

  String _disappearingLabel() {
    final value = (_prefs?['disappearing_seconds'] as num?)?.toInt() ?? 0;
    if (value == 86400) return '24 hours';
    if (value == 604800) return '7 days';
    if (value == 7776000) return '90 days';
    return 'Off';
  }

  @override
  Widget build(BuildContext context) {
    final canEditIdentity = widget.isOwnProfile || (widget.isGroup && widget.canEditGroupInfo);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isGroup ? 'Group info' : 'Chat info')),
      body: AiUniverseShellV62(
        intensity: .34,
        showStars: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 36),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 58,
                        foregroundImage: (widget.avatarUrl ?? '').isNotEmpty
                            ? NetworkImage(widget.avatarUrl!)
                            : null,
                        child: Text(
                          widget.title.isEmpty ? '?' : widget.title.characters.first.toUpperCase(),
                          style: const TextStyle(fontSize: 35, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (canEditIdentity && widget.onEditProfilePhoto != null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: IconButton.filled(
                            onPressed: widget.onEditProfilePhoto,
                            icon: const Icon(Icons.photo_camera_outlined, size: 19),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (widget.isGroup && widget.canEditGroupInfo && widget.onEditGroupInfo != null)
                        IconButton(onPressed: widget.onEditGroupInfo, icon: const Icon(Icons.edit_outlined, size: 19)),
                    ],
                  ),
                  if ((widget.status ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: Text(widget.status!, textAlign: TextAlign.center)),
                        if (widget.isOwnProfile && widget.onEditStatus != null)
                          IconButton(onPressed: widget.onEditStatus, icon: const Icon(Icons.edit_outlined, size: 17)),
                      ],
                    ),
                  ],
                  if ((widget.about ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.about!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.64),
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.onAudioCall != null ||
                widget.onVideoCall != null ||
                widget.onSearchChat != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Row(
                  children: [
                    if (widget.onAudioCall != null)
                      Expanded(
                        child: _QuickActionV62(
                          icon: Icons.call_outlined,
                          label: 'Audio',
                          onTap: widget.onAudioCall!,
                        ),
                      ),
                    if (widget.onAudioCall != null && widget.onVideoCall != null)
                      const SizedBox(width: 8),
                    if (widget.onVideoCall != null)
                      Expanded(
                        child: _QuickActionV62(
                          icon: Icons.videocam_outlined,
                          label: 'Video',
                          onTap: widget.onVideoCall!,
                        ),
                      ),
                    if ((widget.onAudioCall != null || widget.onVideoCall != null) &&
                        widget.onSearchChat != null)
                      const SizedBox(width: 8),
                    if (widget.onSearchChat != null)
                      Expanded(
                        child: _QuickActionV62(
                          icon: Icons.search_rounded,
                          label: 'Search',
                          onTap: widget.onSearchChat!,
                        ),
                      ),
                  ],
                ),
              ),
            _Section(
              children: [
                ListTile(
                  leading: const Icon(Icons.perm_media_outlined),
                  title: const Text('Media, links and docs'),
                  subtitle: Text('$_media media  ·  $_links links  ·  $_docs docs'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MediaLinksDocsScreenV62(
                        database: widget.database,
                        channelId: widget.channelId,
                      ),
                    ),
                  ).then((_) => _reload()),
                ),
                ListTile(
                  leading: const Icon(Icons.star_outline_rounded),
                  title: const Text('Starred messages'),
                  subtitle: Text('$_starred starred'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onSearchChat,
                ),
                ListTile(
                  leading: const Icon(Icons.search_rounded),
                  title: const Text('Search'),
                  onTap: widget.onSearchChat,
                ),
                if (widget.onOpenTasks != null)
                  ListTile(
                    leading: const Icon(Icons.task_alt_rounded),
                    title: const Text('Tasks'),
                    subtitle: const Text('Tasks created from this conversation'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onOpenTasks,
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
                if (widget.onCustomNotifications != null)
                  ListTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: const Text('Custom notifications'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onCustomNotifications,
                  ),
                if (widget.onToggleFavourite != null)
                  ListTile(
                    leading: Icon(widget.isFavourite ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                    title: Text(widget.isFavourite ? 'Remove from favourites' : 'Add to favourites'),
                    onTap: widget.onToggleFavourite,
                  ),
                if (widget.onMediaVisibility != null)
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Media visibility'),
                    subtitle: const Text('Choose whether new media appears in the device gallery'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.onMediaVisibility,
                  ),
                ListTile(
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: const Text('Chat theme & wallpaper'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onChatWallpaper,
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
                  subtitle: const Text('Protect this chat with device authentication'),
                  value: _flag('chat_locked'),
                  onChanged: (value) => _set(chatLocked: value),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.shield_outlined),
                  title: const Text('Advanced chat privacy'),
                  subtitle: const Text('Restrict sensitive preview/export-like actions'),
                  value: _flag('advanced_privacy'),
                  onChanged: (value) => _set(advancedPrivacy: value),
                ),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Encryption'),
                  subtitle: const Text('Chat history is kept on your devices; encrypted backup is separate.'),
                  trailing: widget.onEncryptionDetails == null ? null : const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onEncryptionDetails,
                ),
              ],
            ),
            if (!widget.isGroup &&
                (widget.onGroupsInCommon != null || widget.onAddContact != null))
              _Section(
                children: [
                  if (widget.onGroupsInCommon != null)
                    ListTile(
                      leading: const Icon(Icons.group_outlined),
                      title: const Text('Groups in common'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: widget.onGroupsInCommon,
                    ),
                  if (widget.onAddContact != null)
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: const Text('Add to contacts'),
                      onTap: widget.onAddContact,
                    ),
                ],
              ),
            if (widget.isGroup)
              _Section(
                children: [
                  ListTile(
                    leading: const Icon(Icons.groups_rounded),
                    title: const Text('Participants & admins'),
                    subtitle: const Text('Members, roles, permissions and invite options'),
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
                  subtitle: const Text('Review local media and documents'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MediaLinksDocsScreenV62(
                        database: widget.database,
                        channelId: widget.channelId,
                      ),
                    ),
                  ).then((_) => _reload()),
                ),
                if (widget.onExportChat != null)
                  ListTile(
                    leading: const Icon(Icons.ios_share_outlined),
                    title: const Text('Export chat'),
                    onTap: _flag('advanced_privacy') ? null : widget.onExportChat,
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear chat'),
                  onTap: _clearChat,
                ),
              ],
            ),
            if (widget.isGroup && widget.onExitGroup != null)
              _Section(
                danger: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.exit_to_app_rounded),
                    title: const Text('Exit group'),
                    onTap: () async {
                      await widget.onExitGroup!();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            if (!widget.isGroup && (widget.onBlock != null || widget.onReport != null))
              _Section(
                danger: true,
                children: [
                  if (widget.onBlock != null)
                    ListTile(leading: const Icon(Icons.block_rounded), title: const Text('Block'), onTap: widget.onBlock),
                  if (widget.onReport != null)
                    ListTile(leading: const Icon(Icons.report_outlined), title: const Text('Report'), onTap: widget.onReport),
                ],
              ),
            if (widget.onDeleteChat != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 3, 16, 0),
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
      ),
    );
  }
}

class _QuickActionV62 extends StatelessWidget {
  const _QuickActionV62({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: .84),
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: scheme.primary, size: 21),
              const SizedBox(height: 5),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children, this.danger = false});
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

class MediaLinksDocsScreenV62 extends StatefulWidget {
  const MediaLinksDocsScreenV62({super.key, required this.database, required this.channelId});
  final LocalChatDatabase database;
  final int channelId;

  @override
  State<MediaLinksDocsScreenV62> createState() => _MediaLinksDocsScreenV62State();
}

class _MediaLinksDocsScreenV62State extends State<MediaLinksDocsScreenV62> {
  String _tab = 'media';

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await widget.database.mediaLinksDocs(widget.channelId, category: _tab);
    if (_tab == 'links') return rows;
    return rows.where((row) {
      final path = row['attachment_path'] as String?;
      return path == null || path.isEmpty || File(path).existsSync();
    }).toList();
  }

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
              onSelectionChanged: (value) => setState(() => _tab = value.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(_tab),
              future: _load(),
              builder: (context, snapshot) {
                final rows = snapshot.data;
                if (rows == null) return const Center(child: CircularProgressIndicator());
                if (rows.isEmpty) return Center(child: Text('No ${_tab == 'docs' ? 'documents' : _tab}.'));

                if (_tab == 'media') {
                  return GridView.builder(
                    padding: const EdgeInsets.all(5),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final path = row['attachment_path'] as String?;
                      final mime = row['attachment_mime_type'] as String? ?? '';
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: path != null && mime.startsWith('image/')
                            ? Image.file(File(path), fit: BoxFit.cover)
                            : ColoredBox(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                      leading: Icon(_tab == 'links' ? Icons.link_rounded : Icons.insert_drive_file_outlined),
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
