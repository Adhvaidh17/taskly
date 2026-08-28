import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/taskly_supabase.dart';
import '../core/utils/phone_number.dart';
import '../models/user.dart';
import '../services/primary_device_gate_v63.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this.backend);

  final TasklySupabase backend;
  late final PrimaryDeviceGateV63 _deviceGate = PrimaryDeviceGateV63(client: backend.client);
  AppUser? user;
  bool initialising = true;
  bool busy = false;
  String? error;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _deviceGateTimer;

  bool get isAuthenticated => backend.client.auth.currentSession != null;
  String? get verifiedAuthPhone => backend.client.auth.currentUser?.phone;

  Future<void> initialise() async {
    if (isAuthenticated) {
      await _loadProfile();
      await _enforceDeviceGate();
    }
    _authSubscription = backend.client.auth.onAuthStateChange.listen(
      (state) async {
        if (state.session == null) {
          user = null;
        } else {
          await _loadProfile();
          await _enforceDeviceGate();
        }
        notifyListeners();
      },
      onError: (Object exception, StackTrace stackTrace) {
        error = _friendlyError(exception);
        notifyListeners();
      },
    );
    _deviceGateTimer?.cancel();
    _deviceGateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isAuthenticated) unawaited(_enforceDeviceGate());
    });
    initialising = false;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    try {
      user = AppUser.fromJson(await backend.profile(refresh: true));
      error = null;
    } catch (exception) {
      user = null;
      error = _friendlyError(exception);
    }
  }

  Future<bool> loginWithEmail({
    required String email,
    required String password,
  }) async {
    return _runAuth(() async {
      await backend.client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      await _loadProfile();
      await _enforceDeviceGate();
    });
  }

  Future<bool> loginWithPhone({
    required String phone,
    required String countryIso,
    required String password,
  }) async {
    return _runAuth(() async {
      final normalizedPhone = TasklyPhoneNumber.normalize(
        phone,
        countryIso: countryIso,
      );
      if (!TasklyPhoneNumber.isValid(normalizedPhone)) {
        throw const AuthException('Enter a valid mobile number');
      }
      await backend.client.auth.signInWithPassword(
        phone: normalizedPhone,
        password: password,
      );
      await _loadProfile();
      await _enforceDeviceGate();
    }, phoneLogin: true);
  }

  Future<bool> register({
    required String name,
    required String phone,
    required String countryIso,
    required String email,
    required String password,
  }) async {
    return _runAuth(() async {
      final normalizedPhone = TasklyPhoneNumber.normalize(
        phone,
        countryIso: countryIso,
      );
      if (!TasklyPhoneNumber.isValid(normalizedPhone)) {
        throw const AuthException('A valid mobile number is required');
      }
      final response = await backend.client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {
          'name': name.trim(),
          'phone': normalizedPhone,
          'phone_country_iso': countryIso.toUpperCase(),
          'email': email.trim().toLowerCase(),
        },
      );
      if (response.session != null) {
        await _loadProfile();
        await _enforceDeviceGate();
      }
    });
  }

  Future<bool> completeMandatoryProfile({
    required String name,
    required String phone,
    required String countryIso,
    String? about,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      user = AppUser.fromJson(
        await backend.updateProfile(
          name: name,
          phone: phone,
          phoneCountryIso: countryIso,
          about: about,
        ),
      );
      return true;
    } catch (exception) {
      error = _friendlyError(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> requestPhoneVerification(
    String phone, {
    String? countryIso,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final normalizedPhone = TasklyPhoneNumber.normalize(
        phone,
        countryIso: countryIso,
      );
      if (!TasklyPhoneNumber.isValid(normalizedPhone)) {
        throw const AuthException('Enter a valid mobile number');
      }
      if (verifiedAuthPhone == normalizedPhone) return true;
      await backend.client.auth.updateUser(
        UserAttributes(phone: normalizedPhone),
      );
      return true;
    } catch (exception) {
      error = _friendlyError(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> verifyPhoneChange({
    required String phone,
    required String otp,
    String? countryIso,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final normalizedPhone = TasklyPhoneNumber.normalize(
        phone,
        countryIso: countryIso,
      );
      await backend.client.auth.verifyOTP(
        type: OtpType.phoneChange,
        token: otp.trim(),
        phone: normalizedPhone,
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

  Future<void> _enforceDeviceGate() async {
    if (!isAuthenticated || user == null) return;
    try {
      final allowed = await _deviceGate.registerCurrentDevice();
      if (allowed) {
        unawaited(_deviceGate.touch());
        return;
      }
      error = PrimaryDeviceGateV63.blockedMessage;
      await backend.client.auth.signOut();
      user = null;
    } catch (exception) {
      // A network outage must not strand an already-authenticated primary
      // device. New logins are gated by the server RPC when connectivity exists.
      debugPrint('TASKLY_DEVICE_GATE_ERROR $exception');
    }
  }

  Future<bool> _runAuth(
    Future<void> Function() action, {
    bool phoneLogin = false,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (exception) {
      if (phoneLogin && exception is AuthException) {
        error = '${exception.message}. Sign in with email first and verify this mobile number from Profile if needed.';
      } else {
        error = _friendlyError(exception);
      }
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
    _deviceGateTimer?.cancel();
    super.dispose();
  }
}
