param(
  [Parameter(Mandatory=$true)][string]$SupabaseUrl,
  [Parameter(Mandatory=$true)][string]$SupabaseAnonKey,
  [string]$DeviceId = ""
)
$device = if ($DeviceId) { "-d `"$DeviceId`"" } else { "" }
Invoke-Expression "flutter run $device --dart-define=SUPABASE_URL=$SupabaseUrl --dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
