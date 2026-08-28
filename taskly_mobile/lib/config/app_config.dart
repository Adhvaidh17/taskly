class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const defaultCountryIso =
      String.fromEnvironment('DEFAULT_COUNTRY_ISO', defaultValue: 'IN');
  static const defaultDialCode =
      String.fromEnvironment('DEFAULT_DIAL_CODE', defaultValue: '+91');

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  static void validate() {
    if (!isConfigured) {
      throw StateError(
        'Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY. '
        'Run with --dart-define-from-file=config/prod.json.',
      );
    }
  }
}
