import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme/app_theme.dart';
import '../models/channel.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../providers/chat_provider.dart';
import 'chat_room_screen.dart';
import 'contact_info_screen.dart';
import 'group_tasks_screen.dart';
import 'group_media_screen.dart';
import 'people_search_screen.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({super.key, required this.conversation});

  final ConversationItem conversation;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  late ConversationItem _conversation;
  Map<String, dynamic>? _adminState;
  List<MessageItem> _latestMedia = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      unawaited(_loadLatestMedia());
    });
  }

  Future<void> _load() async {
    final provider = context.read<ChatProvider>();
    try {
      await provider.refreshMembers(_conversation.channelId);
      if (_conversation.isGroup) {
        final state = await provider.loadGroupAdminState(_conversation.workspaceId);
        _adminState = state;
        _conversation = _conversation.copyWith(
          name: '${state['name'] ?? _conversation.name}',
          description: '${state['description'] ?? ''}',
          joinCode: state['join_code'] as String?,
          currentRole: '${state['role'] ?? _conversation.currentRole}',
          onlyAdminsCanSend: state['only_admins_can_send'] == true,
          onlyAdminsCanEdit: state['only_admins_can_edit'] != false,
          approveNewMembers: state['approve_new_members'] == true,
          pendingJoinRequests:
              (state['pending_join_requests'] as List? ?? const []).length,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLatestMedia() async {
    if (!_conversation.isGroup) return;
    try {
      final chat = context.read<ChatProvider>();
      final profileId = chat.currentProfileId ?? await chat.backend.profileId();
      final rows = await chat.backend.groupSharedContent(
        _conversation.channelId,
        kind: 'media',
        limit: 7,
      );
      if (!mounted) return;
      setState(() {
        _latestMedia = rows
            .map((row) => MessageItem.fromJson(row, currentProfileId: profileId))
            .toList(growable: false);
      });
    } catch (_) {
      // Group info remains usable even if media metadata is temporarily offline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final members = provider.members[_conversation.channelId] ?? const <AppUser>[];
    final pending = (_adminState?['pending_join_requests'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final myId = provider.currentProfileId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_conversation.isGroup ? 'Group info' : 'Contact info'),
        actions: [
          if (_conversation.isGroup && (_conversation.canManage || !_conversation.onlyAdminsCanEdit))
            IconButton(
              tooltip: 'Edit group',
              onPressed: _editGroup,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 46,
                      backgroundImage: _conversation.avatarUrl == null
                          ? null
                          : NetworkImage(_conversation.avatarUrl!),
                      child: _conversation.avatarUrl == null
                          ? Icon(
                              _conversation.isGroup ? Icons.groups : Icons.person,
                              size: 42,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _conversation.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((_conversation.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _conversation.description!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.taskly.textMuted),
                    ),
                  ],
                  if (_conversation.isGroup) ...[
                    const SizedBox(height: 18),
                    _groupCodeCard(),
                    const SizedBox(height: 16),
                    _mediaCard(),
                    if (_conversation.canManage) ...[
                      const SizedBox(height: 16),
                      _adminActions(),
                      const SizedBox(height: 16),
                      _permissionsCard(),
                      if (pending.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Pending requests (${pending.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...pending.map(_joinRequestTile),
                      ],
                    ],
                  ],
                  const SizedBox(height: 20),
                  if (_conversation.isGroup) ...[
                    Text(
                      '${members.length} members',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...members.map(
                      (member) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(child: Text(member.initials)),
                        title: Text(member.name),
                        subtitle: Text(_memberSubtitle(member, myId)),
                        trailing: _conversation.canManage &&
                                member.id != myId &&
                                member.role != 'owner'
                            ? const Icon(Icons.more_vert)
                            : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ContactInfoScreen(user: member),
                          ),
                        ),
                        onLongPress: _conversation.canManage &&
                                member.id != myId &&
                                member.role != 'owner'
                            ? () => _manageMember(member)
                            : null,
                      ),
                    ),
                  ] else
                    _directContactCard(members, myId),
                  const SizedBox(height: 18),
                  _dangerActions(),
                ],
              ),
            ),
    );
  }

  Widget _directContactCard(List<AppUser> members, int? myId) {
    AppUser? contact;
    if (_conversation.isSelfChat) {
      for (final member in members) {
        if (member.id == myId) {
          contact = member;
          break;
        }
      }
    } else {
      for (final member in members) {
        if (member.id != myId) {
          contact = member;
          break;
        }
      }
    }

    if (_conversation.isSelfChat) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Your private chat'),
          subtitle: Text('Messages here are for your personal notes and self-assigned tasks.'),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              child: Text(contact?.initials ?? '?'),
            ),
            title: Text(contact?.name ?? _conversation.name),
            subtitle: Text(contact?.about?.trim().isNotEmpty == true
                ? contact!.about!
                : 'Taskly user'),
            trailing: contact == null
                ? null
                : IconButton.filledTonal(
                    tooltip: 'Message',
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    onPressed: () async {
                      final chat = context.read<ChatProvider>();
                      final navigator = Navigator.of(context);
                      final conversation = await chat.startDirectChat(contact!);
                      if (!mounted) return;
                      await navigator.push(
                        MaterialPageRoute(
                          builder: (_) => ChatRoomScreen(
                            conversation: conversation,
                          ),
                        ),
                      );
                    },
                  ),
            onTap: contact == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ContactInfoScreen(user: contact!),
                      ),
                    ),
          ),
          if ((contact?.phone ?? '').trim().isNotEmpty) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(contact!.phone!),
            ),
          ],
          if ((contact?.email ?? '').trim().isNotEmpty) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text(contact!.email),
            ),
          ],
        ],
      ),
    );
  }

  Widget _groupCodeCard() {
    final code = _conversation.joinCode ?? '';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.key_outlined),
        title: const Text('Group ID'),
        subtitle: Text(
          code,
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: 'Copy',
              onPressed: code.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Group ID copied')),
                        );
                      }
                    },
              icon: const Icon(Icons.copy),
            ),
            IconButton(
              tooltip: 'Share',
              onPressed: code.isEmpty ? null : _shareGroup,
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupMediaScreen(conversation: _conversation),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Media, links and docs',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text('${_latestMedia.length}', style: TextStyle(color: context.taskly.textMuted)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            if (_latestMedia.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _latestMedia.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final message = _latestMedia[index];
                    return _GroupMediaThumb(message: message, conversation: _conversation);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _adminActions() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.task_alt_outlined),
            title: const Text('Group tasks'),
            subtitle: const Text('All assignments and current statuses in this group'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupTasksScreen(conversation: _conversation),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: const Text('Add participant'),
            subtitle: const Text('Search phone contacts or registered Taskly users'),
            onTap: _addParticipant,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('Reset group ID'),
            subtitle: const Text('The old group ID will stop working'),
            onTap: _resetJoinCode,
          ),
        ],
      ),
    );
  }

  Widget _permissionsCard() {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Only admins can send'),
            subtitle: const Text('Members can read but cannot post messages'),
            value: _conversation.onlyAdminsCanSend,
            onChanged: (value) => _changePermission(
              onlyAdminsCanSend: value,
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Only admins can edit group info'),
            value: _conversation.onlyAdminsCanEdit,
            onChanged: (value) => _changePermission(
              onlyAdminsCanEdit: value,
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Approve new members'),
            subtitle: const Text('Admins must approve group-ID join requests'),
            value: _conversation.approveNewMembers,
            onChanged: (value) => _changePermission(
              approveNewMembers: value,
            ),
          ),
        ],
      ),
    );
  }

  Widget _joinRequestTile(Map<String, dynamic> request) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(_initials('${request['name'] ?? 'User'}')),
        ),
        title: Text('${request['name'] ?? 'Taskly user'}'),
        subtitle: Text('${request['email'] ?? request['phone'] ?? ''}'),
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: 'Reject',
              onPressed: () => _reviewRequest(_int(request['id']), false),
              icon: Icon(Icons.close, color: context.taskly.danger),
            ),
            IconButton(
              tooltip: 'Approve',
              onPressed: () => _reviewRequest(_int(request['id']), true),
              icon: Icon(Icons.check, color: context.taskly.success),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dangerActions() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear chat'),
            subtitle: const Text('Removes messages only from your view'),
            onTap: _clearChat,
          ),
          if (_conversation.isDirect) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: context.taskly.danger),
              title: Text(
                'Delete chat',
                style: TextStyle(color: context.taskly.danger),
              ),
              onTap: _deleteDirectChat,
            ),
          ],
          if (_conversation.isGroup) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.exit_to_app, color: context.taskly.danger),
              title: Text(
                'Leave group',
                style: TextStyle(color: context.taskly.danger),
              ),
              onTap: _leaveGroup,
            ),
            if (_conversation.isOwner) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: context.taskly.danger,
                ),
                title: Text(
                  'Delete group permanently',
                  style: TextStyle(color: context.taskly.danger),
                ),
                subtitle: const Text('Deletes its messages and tasks'),
                onTap: _deleteGroup,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _editGroup() async {
    final name = TextEditingController(text: _conversation.name);
    final description = TextEditingController(text: _conversation.description);
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit group info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save != true || name.text.trim().length < 2 || !mounted) return;
    final result = await context.read<ChatProvider>().updateGroup(
          workspaceId: _conversation.workspaceId,
          name: name.text.trim(),
          description: description.text,
        );
    if (!mounted) return;
    setState(() {
      _conversation = _conversation.copyWith(
        name: '${result['name'] ?? _conversation.name}',
        description: '${result['description'] ?? ''}',
      );
    });
  }

  Future<void> _changePermission({
    bool? onlyAdminsCanSend,
    bool? onlyAdminsCanEdit,
    bool? approveNewMembers,
  }) async {
    final result = await context.read<ChatProvider>().updateGroup(
          workspaceId: _conversation.workspaceId,
          onlyAdminsCanSend: onlyAdminsCanSend,
          onlyAdminsCanEdit: onlyAdminsCanEdit,
          approveNewMembers: approveNewMembers,
        );
    if (!mounted) return;
    setState(() {
      _conversation = _conversation.copyWith(
        onlyAdminsCanSend: result['only_admins_can_send'] == true,
        onlyAdminsCanEdit: result['only_admins_can_edit'] != false,
        approveNewMembers: result['approve_new_members'] == true,
      );
    });
  }

  Future<void> _addParticipant() async {
    final members = context.read<ChatProvider>().members[_conversation.channelId] ??
        const <AppUser>[];
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PeopleSearchScreen(
          mode: PeopleSearchMode.addToGroup,
          workspaceId: _conversation.workspaceId,
          channelId: _conversation.channelId,
          excludedProfileIds: members.map((member) => member.id).toSet(),
        ),
      ),
    );
    if (added == true && mounted) await _load();
  }

  Future<void> _manageMember(AppUser member) async {
    final isAdmin = member.role == 'admin';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                isAdmin
                    ? Icons.remove_moderator_outlined
                    : Icons.admin_panel_settings_outlined,
              ),
              title: Text(isAdmin ? 'Dismiss as admin' : 'Make group admin'),
              onTap: () => Navigator.pop(sheetContext, 'role'),
            ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined, color: context.taskly.danger),
              title: Text(
                'Remove ${member.name}',
                style: TextStyle(color: context.taskly.danger),
              ),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final provider = context.read<ChatProvider>();
    if (action == 'role') {
      await provider.setGroupMemberRole(
        workspaceId: _conversation.workspaceId,
        channelId: _conversation.channelId,
        profileId: member.id,
        role: isAdmin ? 'member' : 'admin',
      );
    } else if (action == 'remove') {
      final confirmed = await _confirm(
        'Remove ${member.name}?',
        'They will no longer see this group or its tasks.',
        'Remove',
      );
      if (!confirmed || !mounted) return;
      await provider.removeGroupMember(
        workspaceId: _conversation.workspaceId,
        channelId: _conversation.channelId,
        profileId: member.id,
      );
    }
    await _load();
  }

  Future<void> _reviewRequest(int requestId, bool approve) async {
    await context.read<ChatProvider>().reviewJoinRequest(
          requestId: requestId,
          approve: approve,
        );
    if (mounted) await _load();
  }

  Future<void> _resetJoinCode() async {
    final confirmed = await _confirm(
      'Reset group ID?',
      'The existing group ID will stop working.',
      'Reset',
    );
    if (!confirmed || !mounted) return;
    final code = await context
        .read<ChatProvider>()
        .resetGroupJoinCode(_conversation.workspaceId);
    if (mounted) setState(() => _conversation = _conversation.copyWith(joinCode: code));
  }

  Future<void> _shareGroup() async {
    await SharePlus.instance.share(
      ShareParams(
        title: 'Join ${_conversation.name} on Taskly',
        text:
            'Join “${_conversation.name}” on Taskly using group ID: ${_conversation.joinCode}',
      ),
    );
  }

  Future<void> _clearChat() async {
    final confirmed = await _confirm(
      'Clear this chat?',
      'Messages will be removed from your view only.',
      'Clear',
    );
    if (!confirmed || !mounted) return;
    await context.read<ChatProvider>().clearChat(_conversation);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteDirectChat() async {
    final confirmed = await _confirm(
      'Delete this chat?',
      'It will disappear until a new message is sent.',
      'Delete',
    );
    if (!confirmed || !mounted) return;
    await context.read<ChatProvider>().deleteChat(_conversation);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _leaveGroup() async {
    final confirmed = await _confirm(
      'Leave ${_conversation.name}?',
      'You will lose access to its messages and tasks.',
      'Leave',
    );
    if (!confirmed || !mounted) return;
    await context.read<ChatProvider>().leaveGroup(_conversation.workspaceId);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _deleteGroup() async {
    final confirmed = await _confirm(
      'Delete this group permanently?',
      'All group messages and tasks will be deleted. This cannot be undone.',
      'Delete permanently',
    );
    if (!confirmed || !mounted) return;
    await context.read<ChatProvider>().deleteGroup(_conversation.workspaceId);
    if (mounted) Navigator.pop(context, true);
  }

  Future<bool> _confirm(String title, String body, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _memberSubtitle(AppUser member, int? myId) {
    final labels = <String>[];
    if (member.id == myId) labels.add('You');
    if (member.role == 'owner') {
      labels.add('Owner');
    } else if (member.role == 'admin') {
      labels.add('Group admin');
    }
    if (labels.isEmpty) labels.add(member.about ?? member.email);
    return labels.join(' · ');
  }
}

class _GroupMediaThumb extends StatelessWidget {
  const _GroupMediaThumb({required this.message, required this.conversation});

  final MessageItem message;
  final ConversationItem conversation;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatProvider>();
    final isVideo = (message.attachmentMimeType ?? '').startsWith('video/');
    return FutureBuilder<String?>(
      future: chat.ensureMessageLocal(message),
      builder: (context, snapshot) {
        final path = snapshot.data;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupMediaScreen(conversation: conversation),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 68,
              color: context.taskly.panelSoft,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (path != null && !isVideo && File(path).existsSync())
                    Image.file(File(path), fit: BoxFit.cover, cacheWidth: 220)
                  else
                    Icon(
                      isVideo ? Icons.videocam_outlined : Icons.photo_outlined,
                      color: context.taskly.textFaint,
                    ),
                  if (isVideo)
                    const Center(child: Icon(Icons.play_circle_fill, color: Colors.white)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}
