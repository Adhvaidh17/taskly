import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  static const _key = 'taskly_source_device_id_v1';
  static const _proofKey = 'taskly_source_device_proof_v1';
  static String? _cached;
  static String? _cachedProof;

  static Future<String> id() async {
    final existing = _cached;
    if (existing != null && existing.isNotEmpty) return existing;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key)?.trim();
    if (stored != null && stored.length >= 8) {
      _cached = stored;
      return stored;
    }

    final created = 'mobile:${const Uuid().v4()}';
    await prefs.setString(_key, created);
    _cached = created;
    return created;
  }

  static Future<String> proof() async {
    final existing = _cachedProof;
    if (existing != null && existing.length >= 40) return existing;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_proofKey)?.trim();
    if (stored != null && stored.length >= 40) {
      _cachedProof = stored;
      return stored;
    }

    // This is deliberately NOT sent back in message JSON. The server stores
    // only its SHA-256 hash, so another phone on the same account cannot spoof
    // the originating device just by reading attachment metadata.
    final uuid = const Uuid();
    final created = 'proof:${uuid.v4()}:${uuid.v4()}';
    await prefs.setString(_proofKey, created);
    _cachedProof = created;
    return created;
  }
}

