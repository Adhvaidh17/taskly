class ConversationItem {
  const ConversationItem({
    required this.channelId,
    required this.workspaceId,
    required this.kind,
    required this.name,
    this.description,
    this.avatarUrl,
    this.joinCode,
    this.memberCount = 0,
    this.lastMessage,
    this.lastSenderName,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isArchived = false,
    this.currentRole = 'member',
    this.onlyAdminsCanSend = false,
    this.onlyAdminsCanEdit = true,
    this.approveNewMembers = false,
    this.pendingJoinRequests = 0,
    this.isSelfChat = false,
  });

  final int channelId;
  final int workspaceId;
  final String kind;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String? joinCode;
  final int memberCount;
  final String? lastMessage;
  final String? lastSenderName;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isMuted;
  final bool isArchived;
  final String currentRole;
  final bool onlyAdminsCanSend;
  final bool onlyAdminsCanEdit;
  final bool approveNewMembers;
  final int pendingJoinRequests;
  final bool isSelfChat;

  bool get isGroup => kind == 'group';
  bool get isDirect => kind == 'direct';
  bool get isOwner => currentRole == 'owner';
  bool get canManage => currentRole == 'owner' || currentRole == 'admin';
  bool get canSend => !isGroup || !onlyAdminsCanSend || canManage;

  ConversationItem copyWith({
    String? name,
    String? description,
    String? joinCode,
    int? memberCount,
    String? currentRole,
    bool? onlyAdminsCanSend,
    bool? onlyAdminsCanEdit,
    bool? approveNewMembers,
    int? pendingJoinRequests,
    String? lastMessage,
    String? lastSenderName,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? isMuted,
    bool? isArchived,
  }) =>
      ConversationItem(
        channelId: channelId,
        workspaceId: workspaceId,
        kind: kind,
        name: name ?? this.name,
        description: description ?? this.description,
        avatarUrl: avatarUrl,
        joinCode: joinCode ?? this.joinCode,
        memberCount: memberCount ?? this.memberCount,
        lastMessage: lastMessage ?? this.lastMessage,
        lastSenderName: lastSenderName ?? this.lastSenderName,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        unreadCount: unreadCount ?? this.unreadCount,
        isMuted: isMuted ?? this.isMuted,
        isArchived: isArchived ?? this.isArchived,
        currentRole: currentRole ?? this.currentRole,
        onlyAdminsCanSend: onlyAdminsCanSend ?? this.onlyAdminsCanSend,
        onlyAdminsCanEdit: onlyAdminsCanEdit ?? this.onlyAdminsCanEdit,
        approveNewMembers: approveNewMembers ?? this.approveNewMembers,
        pendingJoinRequests: pendingJoinRequests ?? this.pendingJoinRequests,
        isSelfChat: isSelfChat,
      );

  factory ConversationItem.fromJson(Map<String, dynamic> json) => ConversationItem(
        channelId: _int(json['channel_id'] ?? json['id']),
        workspaceId: _int(json['workspace_id']),
        kind: '${json['kind'] ?? json['type'] ?? 'group'}',
        name: '${json['name'] ?? ''}',
        description: json['description'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        joinCode: json['join_code'] as String?,
        memberCount: _int(json['member_count']),
        lastMessage: json['last_message'] as String?,
        lastSenderName: json['last_sender_name'] as String?,
        lastMessageAt: DateTime.tryParse('${json['last_message_at'] ?? ''}')?.toLocal(),
        unreadCount: _int(json['unread_count']),
        isMuted: json['is_muted'] == true,
        isArchived: json['is_archived'] == true,
        currentRole: '${json['current_role'] ?? json['role'] ?? 'member'}',
        onlyAdminsCanSend: json['only_admins_can_send'] == true,
        onlyAdminsCanEdit: json['only_admins_can_edit'] != false,
        approveNewMembers: json['approve_new_members'] == true,
        pendingJoinRequests: _int(json['pending_join_requests']),
        isSelfChat: json['is_self_chat'] == true,
      );
}

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
