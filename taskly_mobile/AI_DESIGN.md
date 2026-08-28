import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/taskly_supabase.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this.backend);

  final TasklySupabase backend;
  AppUser? user;
  bool initialising = true;
  bool busy = false;
  String? error;
  StreamSubscription<AuthState>? _authSubscription;

  bool get isAuthenticated => backend.client.auth.currentSession != null;

  Future<void> initialise() async {
    if (isAuthenticated) await _loadProfile();
    _authSubscription = backend.client.auth.onAuthStateChange.listen((state) async {
      if (state.session == null) {
        user = null;
      } else {
        await _loadProfile();
      }
      notifyListeners();
    });
    initialising = false;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    try {
      user = AppUser.fromJson(await backend.profile(refresh: true));
    } catch (_) {
      user = null;
    }
  }

  Future<bool> login(String email, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await backend.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _loadProfile();
      return true;
    } catch (exception) {
      error = _friendlyError(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final response = await backend.client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'name': name.trim(),
          'phone': phone.trim(),
          'email': email.trim(),
        },
      );
      if (response.session != null) await _loadProfile();
      return true;
    } catch (exception) {
      error = _friendlyError(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfile() async {
    await _loadProfile();
    notifyListeners();
  }

  Future<void> logout() async {
    await backend.client.auth.signOut();
    user = null;
    notifyListeners();
  }

  String _friendlyError(Object exception) {
    if (exception is AuthException) return exception.message;
    return '$exception';
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
