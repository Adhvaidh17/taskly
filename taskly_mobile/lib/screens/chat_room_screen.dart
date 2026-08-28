import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/files/attachment_policy.dart';
import '../core/theme/app_theme.dart';
import '../models/channel.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/task_provider.dart';
import '../providers/workspace_provider.dart';
import 'contact_info_screen.dart';
import 'forward_message_sheet.dart';
import 'group_details_screen.dart';
import 'media_viewer_screen.dart';
import 'tasks_screen.dart';
import '../local_chat/local_chat_runtime.dart';
import '../v62/chat_info_screen_v62.dart';
import '../v62/taskly_ai_theme_v62.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.conversation});

  final ConversationItem conversation;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final Set<int> _mentionedIds = {};
  MessageItem? _replyingTo;
  late ConversationItem _conversation;
  bool _opened = false;
  int? _lastRenderedNewestId;
  bool _initialScrollSettled = false;
  bool _loadingOlderFromScroll = false;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ChatProvider>().openConversation(_conversation);
      if (!mounted) return;
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll
            .animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              if (mounted) _initialScrollSettled = true;
            }),
      );
    });
  }

  void _onScroll() {
    if (!_initialScrollSettled ||
        !_scroll.hasClients ||
        _loadingOlderFromScroll ||
        _scroll.position.pixels > 140) {
      return;
    }
    unawaited(_loadOlderMessages());
  }

  Future<void> _loadOlderMessages() async {
    final provider = context.read<ChatProvider>();
    final channelId = _conversation.channelId;
    if (provider.hasOlderMessages[channelId] == false ||
        provider.loadingOlderChannels.contains(channelId)) {
      return;
    }
    _loadingOlderFromScroll = true;
    final oldExtent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    try {
      final added = await provider.loadOlderMessages(channelId);
      if (!mounted || added == 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final delta = _scroll.position.maxScrollExtent - oldExtent;
        _scroll.jumpTo(
          (oldOffset + delta)
              .clamp(
                _scroll.position.minScrollExtent,
                _scroll.position.maxScrollExtent,
              )
              .toDouble(),
        );
      });
    } finally {
      _loadingOlderFromScroll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final channelId = _conversation.channelId;
    final items = provider.messages[channelId] ?? const <MessageItem>[];
    final members = provider.members[channelId] ?? const <AppUser>[];
    final mentionQuery = _mentionQuery();
    final mentionMatches = mentionQuery == null
        ? const <AppUser>[]
        : members
            .where((member) => member.id != provider.currentProfileId)
            .where((member) => member.name.toLowerCase().contains(mentionQuery.toLowerCase()))
            .take(6)
            .toList();

    final newestId = items.isEmpty ? null : items.last.id;
    if (newestId != null && newestId != _lastRenderedNewestId) {
      final hadMessages = _lastRenderedNewestId != null;
      final nearBottom = !_scroll.hasClients ||
          (_scroll.position.maxScrollExtent - _scroll.position.pixels) < 180;
      final sentByMe = items.last.isMine(provider.currentProfileId ?? -1);
      _lastRenderedNewestId = newestId;
      if (!hadMessages || nearBottom || sentByMe) _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openInfo,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundImage: _conversation.avatarUrl == null
                      ? null
                      : NetworkImage(_conversation.avatarUrl!),
                  child: _conversation.avatarUrl == null
                      ? Icon(_conversation.isGroup ? Icons.groups : Icons.person)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _conversation.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        _conversation.isGroup
                            ? '${members.length} members'
                            : _conversation.isSelfChat
                                ? 'Message yourself to create personal tasks'
                                : (members
                                        .where((item) =>
                                            item.id != provider.currentProfileId)
                                        .firstOrNull
                                        ?.about ??
                                    'Taskly user'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: context.taskly.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Conversation info',
            onPressed: _openInfo,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: provider.loadingMessages && items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Text(
                          _conversation.isSelfChat
                              ? 'Message yourself naturally.\nTaskly will detect personal tasks for you.'
                              : 'Start the conversation.\nUse @name when assigning work.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.taskly.textFaint),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final message = items[index];
                          return _MessageSection(
                            message: message,
                            isMine: message.isMine(provider.currentProfileId ?? -1),
                            showSender: _conversation.isGroup,
                            onLongPress: () => _showMessageActions(message),
                            onSenderTap: () => _openContact(message.sender),
                            localAttachmentPath:
                                provider.localAttachmentPaths[message.id],
                            mediaUnavailable:
                                provider.unavailableAttachmentIds.contains(message.id),
                            mediaLoading:
                                provider.downloadingAttachmentIds.contains(message.id),
                            isTaskChecking:
                                provider.taskAnalysisPendingIds.contains(message.id),
                            onAttachmentTap: message.hasAttachment
                                ? () => _openAttachment(message)
                                : null,
                            onContactTap: message.isContact
                                ? () => _openSharedContact(message)
                                : null,
                            onJoinGroup: _joinSharedGroup,
                            onConfirmSuggestion: message.suggestion?.isPending == true &&
                                    message.isMine(provider.currentProfileId ?? -1)
                                ? () => _reviewSuggestion(message)
                                : null,
                            onDismissSuggestion: message.suggestion?.isPending == true &&
                                    message.isMine(provider.currentProfileId ?? -1)
                                ? () => provider.dismissSuggestion(channelId, message.suggestion!.id)
                                : null,
                            analysisError: provider.taskAnalysisErrors[message.id],
                            onRetryAnalysis: provider.taskAnalysisErrors.containsKey(message.id)
                                ? () => provider.retryTaskAnalysis(_conversation, message.id)
                                : null,
                          );
                        },
                      ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: mentionMatches.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey(mentionQuery),
                    constraints: const BoxConstraints(maxHeight: 190),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: context.taskly.panelStrong,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.taskly.border),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: mentionMatches.length,
                      itemBuilder: (context, index) {
                        final member = mentionMatches[index];
                        return Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(radius: 16, child: Text(member.initials)),
                            title: Text(member.name),
                            subtitle: Text(member.role ?? ''),
                            onTap: () => _insertMention(member),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: _replyingTo == null
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    decoration: BoxDecoration(
                      color: context.taskly.panelStrong,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_replyingTo!.sender.name, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                              Text(_replyingTo!.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => setState(() => _replyingTo = null), icon: const Icon(Icons.close, size: 20)),
                      ],
                    ),
                  ),
          ),
          if (!_conversation.canSend)
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Only group admins can send messages',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.taskly.textMuted),
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.taskly.panel,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: context.taskly.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Add',
                              onPressed:
                                  provider.sending ? null : _showAttachmentMenu,
                              icon: const Icon(Icons.add_rounded),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _input,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization: TextCapitalization.sentences,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'Message',
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 12,
                                  ),
                                  hintStyle: TextStyle(
                                    color: context.taskly.textFaint,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Camera',
                              onPressed: provider.sending
                                  ? null
                                  : () => _pickQuickPhoto(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_outlined),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton.filled(
                        onPressed: provider.sending || _input.text.trim().isEmpty
                            ? null
                            : _send,
                        icon: const Icon(Icons.send_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openInfo() async {
    final runtime = LocalChatRuntime.instance;
    await runtime.initialize(context.read<ChatProvider>().backend.client);
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    final members = provider.members[_conversation.channelId] ?? const <AppUser>[];
    final other = members.where((m) => m.id != provider.currentProfileId).firstOrNull;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatInfoScreenV62(
          database: runtime.database,
          channelId: _conversation.channelId,
          title: _conversation.name,
          isGroup: _conversation.isGroup,
          avatarUrl: _conversation.avatarUrl ?? other?.avatarUrl,
          status: other?.about,
          about: other?.about,
          isOwnProfile: _conversation.isSelfChat,
          canEditGroupInfo: _conversation.canManage,
          onEditProfilePhoto: _conversation.isSelfChat ? () => _editOwnProfile(context) : null,
          onEditStatus: _conversation.isSelfChat ? () => _editOwnProfile(context) : null,
          onEditGroupInfo: _conversation.isGroup ? () => _editGroupInfo(context) : null,
          onSearchChat: () => Navigator.pop(context),
          onOpenTasks: () {
            Navigator.pop(context);
            unawaited(Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TasksScreen())));
          },
          onChatWallpaper: () => _editChatWallpaper(context),
          onEncryptionDetails: () => _showInfoMessage('Messages and attachments are stored on this device.'),
          onAddContact: _conversation.isGroup ? null : () => _showInfoMessage('Contact management is handled from People.'),
          onGroupsInCommon: _conversation.isGroup ? null : () => _showInfoMessage('Groups in common will appear here.'),
          onExitGroup: _conversation.isGroup ? () => provider.leaveGroup(_conversation.workspaceId) : null,
          onDeleteChat: () => provider.deleteChat(_conversation),
        ),
      ),
    );
    if (!mounted || result != true) {
      await provider.loadConversations();
    }
  }

  Future<void> _editGroupInfo(BuildContext context) async {
    final name = TextEditingController(text: _conversation.name);
    final description = TextEditingController(text: _conversation.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Edit group info'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Group name')),
          const SizedBox(height: 10),
          TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted || name.text.trim().length < 2) return;
    final provider = context.read<ChatProvider>();
    await provider.updateGroup(
      workspaceId: _conversation.workspaceId,
      name: name.text.trim(),
      description: description.text.trim(),
    );
    if (mounted) setState(() => _conversation = _conversation.copyWith(name: name.text.trim(), description: description.text.trim()));
  }

  Future<void> _editChatWallpaper(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Chat theme & wallpaper')),
          ListTile(title: const Text('Aurora'), leading: const Icon(Icons.auto_awesome), onTap: () => Navigator.pop(sheet, 'aurora')),
          ListTile(title: const Text('Clean'), leading: const Icon(Icons.light_mode_outlined), onTap: () => Navigator.pop(sheet, 'clean')),
          ListTile(title: const Text('Midnight'), leading: const Icon(Icons.dark_mode_outlined), onTap: () => Navigator.pop(sheet, 'midnight')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null) return;
    final runtime = LocalChatRuntime.instance;
    await runtime.initialize(context.read<ChatProvider>().backend.client);
    await runtime.database.setConversationPreference(_conversation.channelId, wallpaper: choice);
  }

  Future<void> _showInfoMessage(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _editOwnProfile(BuildContext context) async {
    await _showInfoMessage('Edit your profile photo and status from Profile.');
  }

  String? _mentionQuery() {
    final cursor = _input.selection.baseOffset;
    if (cursor < 0 || cursor > _input.text.length) return null;
    final before = _input.text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
    return match?.group(1);
  }

  void _insertMention(AppUser user) {
    final cursor = _input.selection.baseOffset;
    final before = _input.text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
    if (match == null) return;
    final at = before.lastIndexOf('@');
    final replacement = '@${user.name} ';
    final text = _input.text.replaceRange(at, cursor, replacement);
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at + replacement.length),
    );
    _mentionedIds.add(user.id);
    setState(() {});
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    final replyId = _replyingTo?.id;
    _input.clear();
    setState(() => _replyingTo = null);
    final mentionIds = _mentionedIds.toList();
    _mentionedIds.clear();
    try {
      await context.read<ChatProvider>().send(
            conversation: _conversation,
            body: body,
            mentionedProfileIds: mentionIds,
            replyToMessageId: replyId,
          );
      if (!mounted) return;
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      _input.text = body;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _showAttachmentMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _AttachmentChoice(
                    icon: Icons.description_outlined,
                    label: 'Document',
                    onTap: () => Navigator.pop(sheetContext, 'file'),
                  ),
                  _AttachmentChoice(
                    icon: Icons.photo_camera_outlined,
                    label: 'Camera',
                    onTap: () => Navigator.pop(sheetContext, 'camera'),
                  ),
                  _AttachmentChoice(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => Navigator.pop(sheetContext, 'gallery'),
                  ),
                  _AttachmentChoice(
                    icon: Icons.person_outline_rounded,
                    label: 'Contact',
                    onTap: () => Navigator.pop(sheetContext, 'contact'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                AttachmentPolicy.supportedFormatsLabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: context.taskly.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'contact') {
      await _pickContact();
      return;
    }
    if (action == 'gallery') {
      await _pickQuickPhoto(ImageSource.gallery);
      return;
    }
    if (action == 'camera') {
      await _pickQuickPhoto(ImageSource.camera);
      return;
    }
    final file = await openFile();
    if (file != null && mounted) await _sendAttachment(file.path);
  }

  Future<void> _pickQuickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 76,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    if (file != null && mounted) await _sendAttachment(file.path);
  }

  Future<void> _sendAttachment(String path) async {
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final validation = await AttachmentPolicy.validate(path);
    if (!validation.isValid) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(validation.error ?? 'Unsupported file')),
        );
      }
      return;
    }
    try {
      await chat.sendAttachment(
            conversation: _conversation,
            filePath: path,
            replyToMessageId: _replyingTo?.id,
          );
      if (mounted) setState(() => _replyingTo = null);
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _pickContact() async {
    final provider = context.read<ContactProvider>();
    final chat = context.read<ChatProvider>();
    await provider.sync();
    if (!mounted) return;
    final groupMembers = chat.members[_conversation.channelId] ?? const <AppUser>[];
    final usersByKey = <String, AppUser>{};
    for (final user in provider.shareableDeviceContacts) {
      final phone = user.phone ?? '';
      final key = 'local:$phone:${user.email}:${user.name.toLowerCase()}';
      usersByKey[key] = user;
    }
    for (final match in provider.deviceMatches) {
      usersByKey['taskly:${match.match.user.id}'] = match.match.user;
    }
    for (final user in groupMembers) {
      usersByKey['taskly:${user.id}'] = user;
    }
    final users = usersByKey.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final selected = await showModalBottomSheet<AppUser>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .68,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Share contact', style: Theme.of(sheetContext).textTheme.titleLarge),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (_, index) {
                    final user = users[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text(user.initials)),
                      title: Text(user.name),
                      subtitle: Text(user.phone ?? user.email),
                      onTap: () => Navigator.pop(sheetContext, user),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await chat.sendContact(
      conversation: _conversation,
      contact: selected,
      replyToMessageId: _replyingTo?.id,
    );
    if (mounted) setState(() => _replyingTo = null);
  }

  Future<void> _openContact(AppUser user) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContactInfoScreen(user: user)),
    );
  }

  Future<void> _openSharedContact(MessageItem message) async {
    final contact = message.sharedTasklyContact ?? AppUser(
      id: message.sharedContactProfileId ?? 0,
      name: message.sharedContactName ?? message.body,
      email: message.sharedContactEmail ?? '',
      phone: message.sharedContactPhone,
    );
    await _openContact(contact);
  }

  Future<void> _openAttachment(MessageItem message) async {
    if (message.isImage) {
      await _openImage(message);
      return;
    }
    final provider = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    var path = provider.localAttachmentPaths[message.id];
    if (path == null && !provider.unavailableAttachmentIds.contains(message.id)) {
      await provider.refreshLocalMedia(_conversation.channelId, message.id);
      path = provider.localAttachmentPaths[message.id];
    }
    if (!mounted) return;
    if (path == null || !File(path).existsSync()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This file is not available on this device.')),
      );
      return;
    }
    try {
      await provider.media.openFile(
        path,
        mimeType: message.attachmentMimeType,
      );
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _openImage(MessageItem message) async {
    final provider = context.read<ChatProvider>();
    final navigator = Navigator.of(context);
    var path = provider.localAttachmentPaths[message.id];
    var unavailable = provider.unavailableAttachmentIds.contains(message.id);
    if (path == null && !unavailable) {
      await provider.refreshLocalMedia(_conversation.channelId, message.id);
      path = provider.localAttachmentPaths[message.id];
      unavailable = provider.unavailableAttachmentIds.contains(message.id);
    }
    if (!mounted) return;
    final action = await navigator.push<MediaViewerAction>(
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          message: message,
          localPath: path,
          unavailable: unavailable || path == null || !File(path).existsSync(),
        ),
      ),
    );
    if (action == MediaViewerAction.forward && mounted) {
      await _forwardMessage(message);
    }
  }

  Future<void> _forwardMessage(MessageItem message) async {
    final provider = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final targets = await showModalBottomSheet<List<ConversationItem>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ForwardMessageSheet(
        conversations: provider.conversations,
      ),
    );
    if (targets == null || targets.isEmpty || !mounted) return;
    await provider.forwardMessage(message: message, targets: targets);
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Forwarded to ${targets.length} chat${targets.length == 1 ? '' : 's'}',
          ),
        ),
      );
    }
  }

  Future<void> _joinSharedGroup(String code) async {
    final workspace = context.read<WorkspaceProvider>();
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await workspace.joinGroup(code);
      if (!mounted) return;
      await chat.loadConversations();
      if (!mounted) return;
      final status = '${result['status'] ?? 'joined'}';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            status == 'pending' ? 'Join request sent.' : 'Group joined.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }


  Future<void> _showMessageActions(MessageItem message) async {
    final provider = context.read<ChatProvider>();
    final mine = message.isMine(provider.currentProfileId ?? -1);
    final canModerate = _conversation.canManage;
    final canDelete = (mine || canModerate) && !message.isDeleted;
    final canPin = mine || canModerate;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () => Navigator.pop(sheetContext, 'reply')),
            ListTile(leading: const Icon(Icons.add_reaction_outlined), title: const Text('React'), onTap: () => Navigator.pop(sheetContext, 'react')),
            ListTile(leading: const Icon(Icons.forward_rounded), title: const Text('Forward'), onTap: () => Navigator.pop(sheetContext, 'forward')),
            if (message.body.trim().isNotEmpty && !message.isDeleted)
              ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy'), onTap: () => Navigator.pop(sheetContext, 'copy')),
            if (canPin)
              ListTile(leading: Icon(message.isPinned ? Icons.push_pin_outlined : Icons.push_pin), title: Text(message.isPinned ? 'Unpin' : 'Pin'), onTap: () => Navigator.pop(sheetContext, 'pin')),
            if (mine && !message.isDeleted)
              ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit'), onTap: () => Navigator.pop(sheetContext, 'edit')),
            if (canDelete)
              ListTile(leading: Icon(Icons.delete_outline, color: context.taskly.danger), title: Text(mine ? 'Delete message' : 'Delete as admin', style: TextStyle(color: context.taskly.danger)), onTap: () => Navigator.pop(sheetContext, 'delete')),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reply') {
      setState(() => _replyingTo = message);
    } else if (action == 'react') {
      await _chooseReaction(message);
    } else if (action == 'forward') {
      await _forwardMessage(message);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.body));
    } else if (action == 'pin') {
      await provider.pin(
        _conversation.channelId,
        message.id,
        !message.isPinned,
      );
    } else if (action == 'edit') {
      await _editMessage(message);
    } else if (action == 'delete') {
      await provider.deleteMessage(_conversation.channelId, message.id);
    }
  }

  Future<void> _chooseReaction(MessageItem message) async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('React'),
        content: Wrap(
          spacing: 8,
          children: ['👍', '❤️', '😂', '😮', '😢', '🙏']
              .map((item) => TextButton(
                    onPressed: () => Navigator.pop(dialogContext, item),
                    child: Text(item, style: const TextStyle(fontSize: 25)),
                  ))
              .toList(),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    await context.read<ChatProvider>().react(_conversation.channelId, message.id, emoji);
  }

  Future<void> _editMessage(MessageItem message) async {
    final controller = TextEditingController(text: message.body);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: controller, autofocus: true, maxLines: 5),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    await context.read<ChatProvider>().editMessage(_conversation.channelId, message.id, value);
  }

  Future<void> _reviewSuggestion(MessageItem message) async {
    final suggestion = message.suggestion!;
    final provider = context.read<ChatProvider>();
    final members = provider.members[_conversation.channelId] ?? const <AppUser>[];
    final title = TextEditingController(text: suggestion.title);
    final description = TextEditingController(text: suggestion.description);
    var priority = suggestion.priority;
    var assigneeId = suggestion.assignee?.id;
    var deadline = suggestion.deadline;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create this task?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Taskly detected a likely task. Review it before confirming.',
                  style: TextStyle(color: context.taskly.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Task name')),
                const SizedBox(height: 10),
                TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Details')),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: assigneeId,
                  decoration: const InputDecoration(labelText: 'Assigned to'),
                  items: members.map((member) => DropdownMenuItem(value: member.id, child: Text(member.name))).toList(),
                  onChanged: (value) => setDialogState(() => assigneeId = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (value) => setDialogState(() => priority = value ?? 'medium'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(deadline == null ? 'No deadline' : DateFormat('dd MMM yyyy, h:mm a').format(deadline!)),
                  trailing: deadline == null ? null : IconButton(onPressed: () => setDialogState(() => deadline = null), icon: const Icon(Icons.close)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: deadline ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(deadline ?? DateTime.now()),
                    );
                    if (time == null) return;
                    setDialogState(() => deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: title.text.trim().isEmpty || assigneeId == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(suggestion.actionType == 'create' ? 'Create task' : 'Confirm change'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true || !mounted) return;
    await provider.updateSuggestion(_conversation.channelId, suggestion.id, {
      'title': title.text.trim(),
      'description': description.text.trim().isEmpty ? null : description.text.trim(),
      'assignee_id': assigneeId,
      'priority': priority,
      'deadline': deadline?.toUtc().toIso8601String(),
    });
    await provider.confirmSuggestion(_conversation.channelId, suggestion.id);
    if (!mounted) return;
    final taskProvider = context.read<TaskProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await taskProvider.load();
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Task added')));
  }
}

class _MessageSection extends StatelessWidget {
  const _MessageSection({
    required this.message,
    required this.isMine,
    required this.showSender,
    required this.onLongPress,
    required this.onSenderTap,
    required this.localAttachmentPath,
    required this.mediaUnavailable,
    required this.mediaLoading,
    required this.isTaskChecking,
    this.onAttachmentTap,
    this.onContactTap,
    this.onJoinGroup,
    this.onConfirmSuggestion,
    this.onDismissSuggestion,
    this.analysisError,
    this.onRetryAnalysis,
  });

  final MessageItem message;
  final bool isMine;
  final bool showSender;
  final VoidCallback onLongPress;
  final VoidCallback onSenderTap;
  final String? localAttachmentPath;
  final bool mediaUnavailable;
  final bool mediaLoading;
  final bool isTaskChecking;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onContactTap;
  final Future<void> Function(String code)? onJoinGroup;
  final VoidCallback? onConfirmSuggestion;
  final VoidCallback? onDismissSuggestion;
  final String? analysisError;
  final VoidCallback? onRetryAnalysis;

  @override
  Widget build(BuildContext context) {
    final invite = _TasklyGroupInvite.tryParse(message.body);
    final soleLink =
        invite == null ? _SoleLinkPreview.tryParse(message.body) : null;
    final path = localAttachmentPath;
    final localAvailable =
        path != null && path.isNotEmpty && File(path).existsSync();

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: message.id > 0 ? onLongPress : null,
            child: _TaskCheckBubble(
              isMine: isMine,
              checking: isTaskChecking,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSender && !isMine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: GestureDetector(
                        onTap: onSenderTap,
                        child: Text(
                          message.sender.name,
                          style: TextStyle(
                            color: context.taskly.senderName,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (message.replyTo != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: context.taskly.replyBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.replyTo!.sender.name,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            message.replyTo!.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.taskly.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.isForwarded)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forward_rounded,
                            size: 14,
                            color: isMine ? Colors.white.withValues(alpha: .92) : context.taskly.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Forwarded',
                            style: TextStyle(
                              fontSize: 11,
                              color: isMine ? Colors.white.withValues(alpha: .92) : context.taskly.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.isDeleted)
                    const SizedBox.shrink()
                  else if (message.isImage)
                    _InlineImage(
                      path: localAvailable ? path : null,
                      loading: mediaLoading,
                      unavailable: mediaUnavailable ||
                          (!mediaLoading && path != null && !localAvailable),
                      onTap: onAttachmentTap,
                    )
                  else if (message.hasAttachment)
                    _AttachmentCard(
                      message: message,
                      available: localAvailable,
                      loading: mediaLoading,
                      unavailable: mediaUnavailable,
                      onTap: onAttachmentTap,
                    )
                  else if (message.isContact)
                    _ContactMessageCard(
                      message: message,
                      onTap: onContactTap,
                    )
                  else if (invite != null)
                    _GroupInviteMessageCard(
                      invite: invite,
                      onJoin: onJoinGroup == null
                          ? null
                          : () {
                              onJoinGroup!(invite.code);
                            },
                    )
                  else if (soleLink != null)
                    _LinkMessageCard(link: soleLink)
                  else
                    Text(
                      message.body,
                      style: TextStyle(fontSize: 14.5, color: isMine ? Colors.white : context.taskly.chatOtherText),
                    ),
                  if (!message.isDeleted &&
                      message.hasAttachment &&
                      message.body.trim().isNotEmpty &&
                      message.body.trim() !=
                          (message.attachmentName ?? '').trim()) ...[
                    const SizedBox(height: 6),
                    Text(
                      message.body,
                      style: TextStyle(fontSize: 14.5, color: isMine ? Colors.white : context.taskly.chatOtherText),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 11,
                            color: isMine ? Colors.white.withValues(alpha: .72) : context.taskly.textMuted,
                          ),
                        ),
                      if (message.editedAt != null)
                        Text(
                          'edited · ',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isMine ? Colors.white.withValues(alpha: .90) : context.taskly.textMuted,
                          ),
                        ),
                      Text(
                        DateFormat('h:mm a').format(message.createdAt),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isMine ? Colors.white.withValues(alpha: .90) : context.taskly.textMuted,
                        ),
                      ),
                      if (isMine)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.done_all,
                            size: 13,
                            color: isMine ? Colors.white.withValues(alpha: .94) : context.taskly.info,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (message.reactions.isNotEmpty)
            Wrap(
              spacing: 4,
              children: message.reactions
                  .map(
                    (reaction) => Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: reaction.mine
                            ? Theme.of(context).colorScheme.primaryContainer
                            : context.taskly.panelStrong,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${reaction.emoji} ${reaction.count}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (analysisError != null && onRetryAnalysis != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onRetryAnalysis,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: context.taskly.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: context.taskly.danger.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 15,
                          color: context.taskly.danger,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          analysisError!,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.taskly.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (message.suggestion?.isPending == true &&
              onConfirmSuggestion != null)
            _SuggestionCard(
              suggestion: message.suggestion!,
              onReview: onConfirmSuggestion!,
              onDismiss: onDismissSuggestion!,
            ),
        ],
      ),
    );
  }
}

class _TaskCheckBubble extends StatefulWidget {
  const _TaskCheckBubble({
    required this.isMine,
    required this.checking,
    required this.child,
  });

  final bool isMine;
  final bool checking;
  final Widget child;

  @override
  State<_TaskCheckBubble> createState() => _TaskCheckBubbleState();
}

class _TaskCheckBubbleState extends State<_TaskCheckBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );

  @override
  void initState() {
    super.initState();
    if (widget.checking) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _TaskCheckBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checking && !oldWidget.checking) {
      _controller.repeat();
    } else if (!widget.checking && oldWidget.checking) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base =
        widget.isMine ? context.taskly.chatMine : context.taskly.chatOther;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(15),
      topRight: const Radius.circular(15),
      bottomLeft: Radius.circular(widget.isMine ? 15 : 4),
      bottomRight: Radius.circular(widget.isMine ? 4 : 15),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final gradient = widget.isMine
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: widget.checking
                    ? GradientRotation(_controller.value * 6.28318)
                    : null,
                colors: [
                  TasklyAiThemeV62.electricViolet,
                  TasklyAiThemeV62.indigo,
                ],
              )
            : widget.checking
                ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(_controller.value * 6.28318),
                colors: [
                  Color.lerp(base, const Color(0xFF6F67FF), 0.20)!,
                  Color.lerp(base, const Color(0xFF42C8FF), 0.22)!,
                  Color.lerp(base, const Color(0xFFD65CFF), 0.16)!,
                  Color.lerp(base, const Color(0xFF4EF1C4), 0.15)!,
                ],
              )
            : null;
        return Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
          ),
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 5),
          decoration: BoxDecoration(
            color: gradient == null ? base : null,
            gradient: gradient,
            borderRadius: radius,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _InlineImage extends StatelessWidget {
  const _InlineImage({
    required this.path,
    required this.loading,
    required this.unavailable,
    required this.onTap,
  });

  final String? path;
  final bool loading;
  final bool unavailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 258,
          height: 212,
          child: path != null
              ? Image.file(
                  File(path!),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) =>
                      const _MediaPlaceholder(loading: false),
                )
              : _MediaPlaceholder(loading: loading && !unavailable),
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF9AA3AF),
            Color(0xFF6B7280),
            Color(0xFFADB5C0),
          ],
        ),
      ),
      child: Center(
        child: loading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            : const Icon(
                Icons.image_outlined,
                color: Colors.white70,
                size: 30,
              ),
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.message,
    required this.available,
    required this.loading,
    required this.unavailable,
    required this.onTap,
  });

  final MessageItem message;
  final bool available;
  final bool loading;
  final bool unavailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = message.attachmentName ?? 'Attachment';
    final extension =
        name.contains('.') ? name.split('.').last.toUpperCase() : 'FILE';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 285),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: context.taskly.replyBackground,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.insert_drive_file_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$extension · ${_humanBytes(message.attachmentSizeBytes)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.taskly.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (loading)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                available
                    ? Icons.check_circle_outline
                    : Icons.file_download_outlined,
                size: 20,
                color: unavailable
                    ? context.taskly.textFaint
                    : context.taskly.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

class _ContactMessageCard extends StatelessWidget {
  const _ContactMessageCard({required this.message, required this.onTap});

  final MessageItem message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = message.sharedContactName ?? message.body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 285),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: context.taskly.replyBackground,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              child: Text(
                name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    message.sharedContactPhone ??
                        message.sharedContactEmail ??
                        'Taskly contact',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.taskly.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.message_outlined, size: 20),
          ],
        ),
      ),
    );
  }
}

class _GroupInviteMessageCard extends StatelessWidget {
  const _GroupInviteMessageCard({required this.invite, required this.onJoin});

  final _TasklyGroupInvite invite;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 235, maxWidth: 290),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.taskly.replyBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(child: Icon(Icons.groups_2_outlined)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Taskly group',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.taskly.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onJoin,
              child: const Text('Join group'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkMessageCard extends StatelessWidget {
  const _LinkMessageCard({required this.link});

  final _SoleLinkPreview link;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        launchUrl(link.uri, mode: LaunchMode.externalApplication);
      },
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 285),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.taskly.replyBackground,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Icon(
              link.looksLikeFile
                  ? Icons.insert_drive_file_outlined
                  : Icons.link_rounded,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.looksLikeFile
                        ? 'Shared attachment'
                        : 'Shared link',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    link.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.taskly.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TasklyGroupInvite {
  const _TasklyGroupInvite(this.name, this.code);

  final String name;
  final String code;

  static _TasklyGroupInvite? tryParse(String text) {
    final match = RegExp(
      r'Join\s+[“"](.+?)[”"]\s+on\s+Taskly\s+using\s+group\s+ID:\s*([A-Za-z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (match == null) return null;
    final name = match.group(1)?.trim() ?? '';
    final code = match.group(2)?.trim() ?? '';
    if (name.isEmpty || code.isEmpty) return null;
    return _TasklyGroupInvite(name, code);
  }
}

class _SoleLinkPreview {
  const _SoleLinkPreview(this.uri, this.label, this.looksLikeFile);

  final Uri uri;
  final String label;
  final bool looksLikeFile;

  static _SoleLinkPreview? tryParse(String text) {
    final value = text.trim();
    if (value.contains(RegExp(r'\s'))) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final last = uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
    final fileLike = RegExp(
          r'\.(jpg|jpeg|png|gif|webp|heic|heif|pdf|docx?|xlsx?|pptx?|zip|rar|7z|mp3|m4a|wav|mp4|mov|webm)$',
          caseSensitive: false,
        ).hasMatch(uri.path) ||
        uri.path.contains('/storage/v1/object/');
    return _SoleLinkPreview(
      uri,
      last.isEmpty ? uri.host : last,
      fileLike,
    );
  }
}

String _humanBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return 'file';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

class _AttachmentChoice extends StatelessWidget {
  const _AttachmentChoice({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.onReview, required this.onDismiss});

  final TaskSuggestionItem suggestion;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primaryContainer, context.taskly.success.withValues(alpha: 0.10)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(suggestion.title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(
            [
              if (suggestion.assignee != null) 'To ${suggestion.assignee!.name}',
              if (suggestion.deadline != null) DateFormat('dd MMM, h:mm a').format(suggestion.deadline!),
              suggestion.priority,
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: context.taskly.textMuted),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(child: FilledButton(onPressed: onReview, child: const Text('Review'))),
              const SizedBox(width: 8),
              TextButton(onPressed: onDismiss, child: const Text('Not a task')),
            ],
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
