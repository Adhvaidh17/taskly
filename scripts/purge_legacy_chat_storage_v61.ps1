param(
  [Parameter(Mandatory=$true)][string]$ProjectRef,
  [Parameter(Mandatory=$true)][string]$MaintenanceSecret
)

$ErrorActionPreference = "Stop"
$uri = "https://$ProjectRef.supabase.co/functions/v1/purge-legacy-chat-storage-v61"
$headers = @{ "x-taskly-maintenance-secret" = $MaintenanceSecret }

Write-Host "Purging legacy Taskly chat media from Supabase Storage..." -ForegroundColor Cyan
$result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body "{}"
$result | ConvertTo-Json -Depth 8

if ($result.ok -ne $true) {
  throw "Storage cleanup returned failures. Do NOT run the v61 message purge migration until they are resolved."
}

Write-Host "Storage cleanup succeeded. You can now run: npx supabase db push" -ForegroundColor Green
