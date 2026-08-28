import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PrimaryDeviceGateV63 {
  PrimaryDeviceGateV63({
    SupabaseClient? client,
    FlutterSecureStorage? storage,
  }) : _client = client ?? Supabase.instance.client,
       _storage = storage ?? const FlutterSecureStorage();

  final SupabaseClient _client;
  final FlutterSecureStorage _storage;
  static const _deviceKey = 'taskly.v63.device_id';

  static const blockedMessage =
      'This account is already connected to another device. '
      'Chat backup and device switching are coming soon.';

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await _storage.write(key: _deviceKey, value: id);
    return id;
  }

  Future<bool> registerCurrentDevice() async {
    final raw = await _client.rpc(
      'taskly_register_primary_device_v63',
      params: {
        'p_device_id': await deviceId(),
        'p_device_name': 'Android device',
        'p_platform': Platform.isAndroid ? 'android' : Platform.operatingSystem,
      },
    );
    final result = Map<String, dynamic>.from(raw as Map);
    return result['allowed'] == true;
  }

  Future<void> touch() async {
    await _client.rpc(
      'taskly_touch_primary_device_v63',
      params: {'p_device_id': await deviceId()},
    );
  }
}
