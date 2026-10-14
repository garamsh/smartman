#!/usr/bin/env bash
# Runs the pgTAP tests in supabase/tests/ against the local stack, or says why it did not.
# Resets the local database first; stops the stack afterwards when this script started it.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1; then
  echo "skipped the database tests in supabase/tests/: they need Docker, and this host has no docker command"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "skipped the database tests in supabase/tests/: they need Docker, and docker info reached no daemon on this host"
  exit 0
fi

if ! supabase status >/dev/null 2>&1; then
  # The tests need only Postgres. Status output, which carries the local keys, is not printed.
  supabase start --exclude gotrue,realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >/dev/null
  trap 'supabase stop --no-backup >/dev/null' EXIT
fi

supabase db reset --local
output=$(supabase test db --local) || { echo "$output"; exit 1; }
echo "$output"

tests=$(echo "$output" | sed -n 's/^Files=\([0-9]*\), Tests=\([0-9]*\),.*/\2 \1/p')
if [ -z "$tests" ] || [ "${tests%% *}" -eq 0 ]; then
  echo "supabase test db ran no pgTAP test" >&2
  exit 1
fi
echo "ran ${tests%% *} pgTAP tests in ${tests##* } files against the local stack, selected by supabase test db: every file under supabase/tests/"
