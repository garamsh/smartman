#!/usr/bin/env bash
# Runs the tests that need Auth and PostgREST, the two-device sync test
# app/test/sync/two_devices_test.dart and the sharing server test app/test/sharing/sharing_server_test.dart,
# against a local stack of its own, or says why it did not. The stack follows ADR 0014's pattern for the database tests: its own
# project id and reserved ports, stopped with its data however the run ends. It runs Postgres, Auth,
# PostgREST and the API gateway, which the test signs in and syncs through.
set -euo pipefail
cd "$(dirname "$0")/.."

test_files="test/sync/two_devices_test.dart test/sharing/sharing_server_test.dart"

if ! command -v docker >/dev/null 2>&1; then
  echo "skipped the stack tests in app/ ($test_files): they need Docker, and this host has no docker command"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "skipped the stack tests in app/ ($test_files): they need Docker, and docker info reached no daemon on this host"
  exit 0
fi

# A port is this run's once mkdir creates its directory, which is atomic between concurrent runs,
# and nothing on the host listens on it. The directory is the one supabase/test-db.sh reserves in.
reservations="${TMPDIR:-/tmp}/smartman-test-db"
mkdir -p "$reservations"
reserved=()
# Prints the first port from $1 to $2 this run reserves; run in a subshell, the caller records it.
reserve() {
  local candidate
  for candidate in $(seq "$1" "$2"); do
    if mkdir "$reservations/$candidate" 2>/dev/null; then
      if (exec 3<>"/dev/tcp/127.0.0.1/$candidate") 2>/dev/null; then
        rmdir "$reservations/$candidate"
      else
        echo "$candidate"
        return 0
      fi
    fi
  done
  echo "found no free port in $1-$2 for the sync test stack; reservations are under $reservations" >&2
  return 1
}
release() {
  local port
  for port in "${reserved[@]}"; do
    rmdir "$reservations/$port" 2>/dev/null || true
  done
}
db_port=$(reserve 54400 54499) || exit 1
reserved+=("$db_port")
api_port=$(reserve 54500 54599) || { release; exit 1; }
reserved+=("$api_port")

export SUPABASE_PROJECT_ID="smartman_sync_$db_port" SUPABASE_DB_PORT="$db_port" SUPABASE_API_PORT="$api_port"

# Stop prunes containers, volumes and networks, and Docker refuses a prune while another stack's
# stop is pruning, so a failed stop is retried. A stack left behind fails the run.
stop_stack() {
  local status=$? attempt stopped
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if stopped=$(supabase stop --no-backup 2>&1); then
      release
      exit "$status"
    fi
    sleep 2
  done
  echo "$stopped" >&2
  echo "could not stop the sync test stack $SUPABASE_PROJECT_ID after $attempt attempts; remove it with: supabase stop --no-backup --project-id $SUPABASE_PROJECT_ID" >&2
  release
  [ "$status" -ne 0 ] || status=1
  exit "$status"
}
trap stop_stack EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Start applies the migrations. Its output and the status below carry the local keys, so neither
# is printed.
supabase start --exclude realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >/dev/null
status=$(supabase status --output env)
url=$(echo "$status" | sed -n 's/^API_URL="\(.*\)"$/\1/p')
key=$(echo "$status" | sed -n 's/^PUBLISHABLE_KEY="\(.*\)"$/\1/p')
if [ -z "$url" ] || [ -z "$key" ]; then
  echo "supabase status gave no API_URL or PUBLISHABLE_KEY for the stack $SUPABASE_PROJECT_ID" >&2
  exit 1
fi

output=$(cd app && SMARTMAN_SYNC_TEST_URL="$url" SMARTMAN_SYNC_TEST_KEY="$key" \
  flutter test --concurrency=1 --reporter expanded --dart-define-from-file=config/dev.json $test_files) ||
  { echo "$output"; exit 1; }
echo "$output"

# The last line reads "+<passed>: All tests passed!", with "~<skipped>" when any test skipped.
summary=$(echo "$output" | tail -n 1)
passed=$(echo "$summary" | sed -n 's/^[0-9:]* +\([0-9]*\): All tests passed!$/\1/p')
if [ -z "$passed" ] || [ "$passed" -eq 0 ]; then
  echo "the stack tests skipped or ran no test: $summary" >&2
  exit 1
fi
echo "ran $passed stack tests against the stack $SUPABASE_PROJECT_ID, selected by: every test in app/ $test_files"
