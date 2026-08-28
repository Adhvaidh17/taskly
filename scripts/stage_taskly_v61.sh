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
  "$SUPABASE/migrations" \
  "$SUPABASE/verify" \
  "$SUPABASE/functions/purge-legacy-chat-storage-v61"

cp -f "$HERE"/taskly_mobile/lib/v61/*.dart "$MOBILE/lib/v61/"
cp -f "$HERE/supabase/migrations/20260828093000_taskly_v61_private_chat_cleanup.sql" "$SUPABASE/migrations/"
cp -f "$HERE/supabase/verify/verify_taskly_v61_privacy.sql" "$SUPABASE/verify/"
cp -f "$HERE"/supabase/functions/purge-legacy-chat-storage-v61/* "$SUPABASE/functions/purge-legacy-chat-storage-v61/"

printf '%s\n' "Taskly v61 files staged."
printf '%s\n' "IMPORTANT: purge legacy Storage chat media BEFORE running the DB migration."
printf '%s\n' "Next: read PATCH_INTEGRATION.md and DESIGN_SYSTEM_V61.md."
