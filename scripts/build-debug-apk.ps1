param(
  [Parameter(Mandatory=$true)][string]$SupabaseUrl,
  [Parameter(Mandatory=$true)][string]$SupabaseAnonKey
)
flutter clean
flutter pub get
flutter build apk --debug --dart-define=SUPABASE_URL=$SupabaseUrl --dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey
Write-Host "APK: build\app\outputs\flutter-apk\app-debug.apk"
