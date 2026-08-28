class GroupItem {
  const GroupItem({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.role,
    required this.channelId,
    this.description,
    this.avatarUrl,
    this.memberCount = 0,
    this.onlyAdminsCanSend = false,
    this.onlyAdminsCanEdit = true,
    this.approveNewMembers = false,
    this.pendingJoinRequests = 0,
  });

  final int id;
  final String name;
  final String joinCode;
  final String role;
  final int channelId;
  final String? description;
  final String? avatarUrl;
  final int memberCount;
  final bool onlyAdminsCanSend;
  final bool onlyAdminsCanEdit;
  final bool approveNewMembers;
  final int pendingJoinRequests;

  bool get canManage => role == 'owner' || role == 'admin';

  factory GroupItem.fromJson(Map<String, dynamic> json) => GroupItem(
        id: _int(json['id'] ?? json['workspace_id']),
        name: '${json['name'] ?? ''}',
        joinCode: '${json['join_code'] ?? ''}',
        role: '${json['role'] ?? 'member'}',
        channelId: _int(json['channel_id']),
        description: json['description'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        memberCount: _int(json['member_count']),
        onlyAdminsCanSend: json['only_admins_can_send'] == true,
        onlyAdminsCanEdit: json['only_admins_can_edit'] != false,
        approveNewMembers: json['approve_new_members'] == true,
        pendingJoinRequests: _int(json['pending_join_requests']),
      );
}

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
