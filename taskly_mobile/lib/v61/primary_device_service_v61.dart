import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PrimaryDeviceRegistrationV61 {
  const PrimaryDeviceRegistrationV61({
    required this.deviceId,
    required this.isNewDevice,
    this.replacedDeviceId,
  });

  final String deviceId;
  final bool isNewDevice;
  final String? replacedDeviceId;
}

/// Account/device metadata only. No message body or media is sent here.
class PrimaryDeviceServiceV61 {
  PrimaryDeviceServiceV61({
    SupabaseClient? client,
    FlutterSecureStorage? secureStorage,
  })  : _client = client ?? Supabase.instance.client,
        _storage = secureStorage ?? const FlutterSecureStorage();

  final SupabaseClient _client;
  final FlutterSecureStorage _storage;
  static const _deviceKey = 'taskly_v61_primary_device_id';

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final value = const Uuid().v4();
    await _storage.write(key: _deviceKey, value: value);
    return value;
  }

  Future<PrimaryDeviceRegistrationV61> register({
    required String deviceName,
    required String platform,
  }) async {
    final id = await deviceId();
    final raw = await _client.rpc(
      'taskly_register_primary_device_v61',
      params: {
        'p_device_id': id,
        'p_device_name': deviceName,
        'p_platform': platform,
      },
    );
    final map = Map<String, dynamic>.from(raw as Map);
    return PrimaryDeviceRegistrationV61(
      deviceId: id,
      isNewDevice: map['is_new_device'] == true,
      replacedDeviceId: map['replaced_device_id'] as String?,
    );
  }

  Future<bool> isCurrentPrimary() async {
    final raw = await _client.rpc(
      'taskly_primary_device_status_v61',
      params: {'p_device_id': await deviceId()},
    );
    return raw == true;
  }

  Future<void> touch() async {
    await _client.rpc(
      'taskly_touch_primary_device_v61',
      params: {'p_device_id': await deviceId()},
    );
  }

  /// Subscribe while the app is alive. If [onReplaced] fires, route the old
  /// primary phone to the signed-out/replaced screen and clear its local auth
  /// session using the app's existing auth controller.
  Future<RealtimeChannel> watchReplacement({
    required Future<void> Function() onReplaced,
  }) async {
    final id = await deviceId();
    final channel = _client.channel('taskly-primary-device-$id');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'taskly_primary_devices_v61',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'device_id',
            value: id,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            final current = row['is_primary'] == true && row['is_active'] == true;
            if (!current) await onReplaced();
          },
        )
        .subscribe();
    return channel;
  }
}
