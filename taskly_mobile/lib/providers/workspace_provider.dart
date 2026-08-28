import 'package:flutter/foundation.dart';

import '../core/supabase/taskly_supabase.dart';
import '../models/group.dart';
import '../models/task.dart';
import '../models/user.dart';

class WorkspaceProvider extends ChangeNotifier {
  WorkspaceProvider(this.backend);

  final TasklySupabase backend;
  AppUser? profile;
  List<GroupItem> groups = [];
  List<AppUser> members = [];
  List<TaskClient> clients = [];
  List<TaskChannel> channels = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      try {
        await backend.ensureSelfChat();
      } catch (_) {
        // The rest of Taskly remains usable if the self-chat migration is pending.
      }
      final data = await backend.bootstrap();
      profile = AppUser.fromJson(Map<String, dynamic>.from(data['profile'] as Map));
      groups = (data['groups'] as List? ?? const [])
          .map((item) => GroupItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      members = (data['members'] as List? ?? const [])
          .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      clients = (data['clients'] as List? ?? const [])
          .map((item) => TaskClient.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      channels = (data['channels'] as List? ?? const [])
          .map((item) => TaskChannel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (exception) {
      error = '$exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<GroupItem> createGroup(String name, String description) async {
    final result = GroupItem.fromJson(await backend.createGroup(name, description));
    await load();
    return groups.firstWhere(
      (group) => group.id == result.id,
      orElse: () => result,
    );
  }

  Future<Map<String, dynamic>> joinGroup(String code) async {
    final result = await backend.joinGroup(code);
    if ('${result['status'] ?? 'joined'}' == 'joined') {
      await load();
    }
    return result;
  }

  Future<void> updateMyProfile({
    required String name,
    required String phone,
    String? phoneCountryIso,
    String? about,
  }) async {
    profile = AppUser.fromJson(
      await backend.updateProfile(
        name: name,
        phone: phone,
        phoneCountryIso: phoneCountryIso,
        about: about,
      ),
    );
    notifyListeners();
  }
}
