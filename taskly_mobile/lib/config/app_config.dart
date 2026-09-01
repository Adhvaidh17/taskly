import 'dart:convert';

import 'package:flutter/services.dart';

class AppConfig {
  static String supabaseUrl = '';
  static String supabasePublishableKey = '';

  static const defaultCountryIso = 'IN';
  static const defaultDialCode = '+91';

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  static Future<void> load() async {
    final raw = await rootBundle.loadString('config/prod.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid config/prod.json.');
    }

    supabaseUrl = (decoded['SUPABASE_URL'] as String? ?? '').trim();
    supabasePublishableKey =
        (decoded['SUPABASE_PUBLISHABLE_KEY'] as String? ?? '').trim();
    validate();
  }

  static void validate() {
    if (!isConfigured) {
      throw StateError(
        'Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY in config/prod.json.',
      );
    }
  }
}
