import 'package:flutter/foundation.dart';

import '../core/supabase/taskly_supabase.dart';

class DashboardProvider extends ChangeNotifier {
  DashboardProvider(this.backend);

  final TasklySupabase backend;
  Map<String, dynamic> summary = const {};
  List<Map<String, dynamic>> members = const [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await backend.dashboard();
      summary = Map<String, dynamic>.from(data['summary'] as Map? ?? const {});
      members = (data['members'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (exception) {
      error = '$exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
