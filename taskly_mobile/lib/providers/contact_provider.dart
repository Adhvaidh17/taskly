import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../config/app_config.dart';
import '../core/supabase/taskly_supabase.dart';
import '../core/utils/phone_number.dart';
import '../models/contact_match.dart';
import '../models/people_search_result.dart';
import '../models/user.dart';

class ContactProvider extends ChangeNotifier {
  ContactProvider(this.backend);

  final TasklySupabase backend;

  List<ContactMatch> matches = [];
  List<DeviceTasklyContact> deviceMatches = [];
  List<ContactMatch> directoryResults = [];
  List<AppUser> shareableDeviceContacts = [];

  bool loading = false;
  bool loadingDirectory = false;
  bool permissionDenied = false;
  String? error;
  String? directoryError;
  int _directoryRequestId = 0;

  Future<void> sync({bool force = false}) async {
    if (loading) return;
    if (!force && deviceMatches.isNotEmpty) return;

    loading = true;
    permissionDenied = false;
    error = null;
    notifyListeners();

    try {
      final permission =
          await FlutterContacts.permissions.request(PermissionType.read);
      if (permission != PermissionStatus.granted) {
        permissionDenied = true;
        matches = [];
        deviceMatches = [];
        shareableDeviceContacts = [];
        return;
      }

      final profile = await backend.profile();
      final defaultCountryIso =
          '${profile['phone_country_iso'] ?? ''}'.trim().isNotEmpty
              ? '${profile['phone_country_iso']}'.toUpperCase()
              : TasklyPhoneNumber.countryIso('${profile['phone'] ?? ''}') ??
                  AppConfig.defaultCountryIso;

      final contacts = await FlutterContacts.getAll(
        properties: {
          ContactProperty.name,
          ContactProperty.phone,
          ContactProperty.email,
        },
      );

      final phones = <String>{};
      final emails = <String>{};
      final localContacts = <AppUser>[];
      final phoneOwners = <String, ({String name, String phone})>{};
      final emailOwners = <String, ({String name, String phone})>{};

      for (final contact in contacts) {
        final rawDisplayName = (contact.displayName ?? '').trim();
        final displayName = rawDisplayName.isEmpty ? 'Phone contact' : rawDisplayName;
        final firstPhone = contact.phones.isEmpty
            ? ''
            : contact.phones.first.number.trim();
        final firstEmail = contact.emails.isEmpty
            ? ''
            : contact.emails.first.address.trim();
        if (firstPhone.isNotEmpty || firstEmail.isNotEmpty) {
          localContacts.add(
            AppUser(
              id: 0,
              name: displayName,
              email: firstEmail,
              phone: firstPhone.isEmpty ? null : firstPhone,
            ),
          );
        }

        for (final phone in contact.phones) {
          final normalized = TasklyPhoneNumber.normalize(
            phone.number,
            countryIso: defaultCountryIso,
          );
          if (!TasklyPhoneNumber.isValid(normalized)) continue;
          final hash = _hash(normalized);
          phones.add(hash);
          phoneOwners.putIfAbsent(
            hash,
            () => (name: displayName, phone: phone.number.trim()),
          );
        }

        for (final email in contact.emails) {
          final normalized = email.address.trim().toLowerCase();
          if (normalized.isEmpty) continue;
          final hash = _hash(normalized);
          emails.add(hash);
          emailOwners.putIfAbsent(
            hash,
            () => (name: displayName, phone: firstPhone),
          );
        }
      }

      final rows = await backend.findContacts(
        phoneHashes: phones.toList(),
        emailHashes: emails.toList(),
      );
      final parsed = rows.map(ContactMatch.fromJson).toList();
      final byProfile = <int, DeviceTasklyContact>{};

      for (final match in parsed) {
        final user = match.user;
        ({String name, String phone})? owner;

        final phone = user.phone;
        if (phone != null && phone.trim().isNotEmpty) {
          owner = phoneOwners[_hash(phone.trim())];
        }
        if (owner == null && user.email.trim().isNotEmpty) {
          owner = emailOwners[_hash(user.email.trim().toLowerCase())];
        }

        byProfile[user.id] = DeviceTasklyContact(
          match: match,
          deviceName: owner?.name ?? user.name,
          devicePhone: owner?.phone ?? user.phone ?? '',
        );
      }

      matches = parsed;
      shareableDeviceContacts = localContacts
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      deviceMatches = byProfile.values.toList()
        ..sort(
          (a, b) => a.deviceName.toLowerCase().compareTo(
                b.deviceName.toLowerCase(),
              ),
        );
    } catch (exception) {
      error = '$exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<List<ContactMatch>> searchDirectoryByPhone({
    required String query,
    required String countryIso,
  }) async {
    final requestId = ++_directoryRequestId;
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) {
      directoryResults = [];
      directoryError = null;
      loadingDirectory = false;
      notifyListeners();
      return directoryResults;
    }

    loadingDirectory = true;
    directoryResults = [];
    directoryError = null;
    notifyListeners();

    try {
      final normalized = TasklyPhoneNumber.isValid(
        query,
        countryIso: countryIso,
      )
          ? TasklyPhoneNumber.normalize(query, countryIso: countryIso)
          : digits;
      final rows = await backend.searchPeopleByPhone(normalized);
      if (requestId != _directoryRequestId) return const <ContactMatch>[];
      directoryResults = rows.map(ContactMatch.fromJson).toList();
      return directoryResults;
    } catch (exception) {
      if (requestId != _directoryRequestId) return const <ContactMatch>[];
      directoryError = '$exception';
      directoryResults = [];
      return directoryResults;
    } finally {
      if (requestId == _directoryRequestId) {
        loadingDirectory = false;
        notifyListeners();
      }
    }
  }

  void clearDirectoryResults() {
    _directoryRequestId += 1;
    loadingDirectory = false;
    directoryResults = [];
    directoryError = null;
    notifyListeners();
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
}
