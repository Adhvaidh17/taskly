param(
  [string]$RepoRoot = "C:\Projects\taskly_flutter_supabase"
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $PSScriptRoot
$Mobile = Join-Path $RepoRoot "taskly_mobile"
$Supabase = Join-Path $RepoRoot "supabase"

if (-not (Test-Path $Mobile)) { throw "taskly_mobile not found at $Mobile" }
if (-not (Test-Path $Supabase)) { throw "supabase not found at $Supabase" }

$V61 = Join-Path $Mobile "lib\v61"
$V62 = Join-Path $Mobile "lib\v62"
$Migrations = Join-Path $Supabase "migrations"
$Verify = Join-Path $Supabase "verify"
$PurgeFunction = Join-Path $Supabase "functions\purge-legacy-chat-storage-v61"

New-Item -ItemType Directory -Force -Path $V61,$V62,$Migrations,$Verify,$PurgeFunction | Out-Null
Copy-Item -Force (Join-Path $Here "taskly_mobile\lib\v61\*") $V61
Copy-Item -Force (Join-Path $Here "taskly_mobile\lib\v62\*") $V62
Copy-Item -Force (Join-Path $Here "supabase\migrations\20260828093000_taskly_v61_private_chat_cleanup.sql") $Migrations
Copy-Item -Force (Join-Path $Here "supabase\verify\verify_taskly_v61_privacy.sql") $Verify
Copy-Item -Force (Join-Path $Here "supabase\functions\purge-legacy-chat-storage-v61\*") $PurgeFunction

Write-Host "Taskly v62 UI + v61 privacy files staged." -ForegroundColor Green
Write-Host "Next: wire the screens using PATCH_INTEGRATION_V62.md." -ForegroundColor Yellow
Write-Host "Do NOT run the permanent chat-media purge until the local chat path is verified on-device." -ForegroundColor Red
