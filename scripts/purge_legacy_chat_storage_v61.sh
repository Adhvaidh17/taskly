#!/usr/bin/env bash
set -euo pipefail

PROJECT_REF="${1:-}"
MAINTENANCE_SECRET="${2:-}"
if [[ -z "$PROJECT_REF" || -z "$MAINTENANCE_SECRET" ]]; then
  echo "Usage: $0 <project-ref> <maintenance-secret>" >&2
  exit 2
fi

curl --fail-with-body --silent --show-error \
  -X POST "https://${PROJECT_REF}.supabase.co/functions/v1/purge-legacy-chat-storage-v61" \
  -H "content-type: application/json" \
  -H "x-taskly-maintenance-secret: ${MAINTENANCE_SECRET}" \
  -d '{}'

echo
echo "If the JSON says ok=true, run the v61 DB migration next."
