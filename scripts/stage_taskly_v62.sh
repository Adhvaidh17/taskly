#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="$REPO_ROOT/taskly_mobile"
SUPABASE="$REPO_ROOT/supabase"

[[ -d "$MOBILE" ]] || { echo "taskly_mobile not found at $MOBILE" >&2; exit 1; }
[[ -d "$SUPABASE" ]] || { echo "supabase not found at $SUPABASE" >&2; exit 1; }

mkdir -p \
  "$MOBILE/lib/v61" \
  "$MOBILE/lib/v62" \
  "$SUPABASE/migrations" \
  "$SUPABASE/verify" \
  "$SUPABASE/functions/purge-legacy-chat-storage-v61"

cp -f "$HERE"/taskly_mobile/lib/v61/*.dart "$MOBILE/lib/v61/"
cp -f "$HERE"/taskly_mobile/lib/v62/*.dart "$MOBILE/lib/v62/"
cp -f "$HERE/supabase/migrations/20260828093000_taskly_v61_private_chat_cleanup.sql" "$SUPABASE/migrations/"
cp -f "$HERE/supabase/verify/verify_taskly_v61_privacy.sql" "$SUPABASE/verify/"
cp -f "$HERE"/supabase/functions/purge-legacy-chat-storage-v61/* "$SUPABASE/functions/purge-legacy-chat-storage-v61/"

printf '%s\n' "Taskly v62 UI + v61 privacy files staged."
printf '%s\n' "Next: wire the screens using PATCH_INTEGRATION_V62.md."
printf '%s\n' "Do NOT run the permanent chat-media purge until local chat is verified on-device."
