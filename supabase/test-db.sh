#!/usr/bin/env bash
# Runs the pgTAP tests in supabase/tests/ against a local stack of its own, or says why it did not.
# The stack gets its own project id and database port, so concurrent runs and the shared
# smartman stack never meet; it is stopped, with its data, however the run ends.
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

# A port is this run's once mkdir creates its directory, which is atomic between concurrent runs,
# and nothing on the host listens on it.
reservations="${TMPDIR:-/tmp}/smartman-test-db"
mkdir -p "$reservations"
port=""
for candidate in $(seq 54400 54499); do
  if mkdir "$reservations/$candidate" 2>/dev/null; then
    if (exec 3<>"/dev/tcp/127.0.0.1/$candidate") 2>/dev/null; then
      rmdir "$reservations/$candidate"
    else
      port=$candidate
      break
    fi
  fi
done
if [ -z "$port" ]; then
  echo "found no free database port in 54400-54499 for the test stack; reservations are under $reservations" >&2
  exit 1
fi

export SUPABASE_PROJECT_ID="smartman_test_$port" SUPABASE_DB_PORT="$port"

# Stop prunes containers, volumes and networks, and Docker refuses a prune while another stack's
# stop is pruning, so a failed stop is retried. A stack left behind fails the run.
stop_stack() {
  local status=$? attempt stopped
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if stopped=$(supabase stop --no-backup 2>&1); then
      rmdir "$reservations/$port"
      exit "$status"
    fi
    sleep 2
  done
  echo "$stopped" >&2
  echo "could not stop the test stack $SUPABASE_PROJECT_ID after $attempt attempts; remove it with: supabase stop --no-backup --project-id $SUPABASE_PROJECT_ID" >&2
  rmdir "$reservations/$port"
  [ "$status" -ne 0 ] || status=1
  exit "$status"
}
trap stop_stack EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The tests need only Postgres. Start applies the migrations; its output, which carries the local
# keys, is not printed.
supabase start --exclude gotrue,realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >/dev/null
output=$(supabase test db --local) || { echo "$output"; exit 1; }
echo "$output"

tests=$(echo "$output" | sed -n 's/^Files=\([0-9]*\), Tests=\([0-9]*\),.*/\2 \1/p')
if [ -z "$tests" ] || [ "${tests%% *}" -eq 0 ]; then
  echo "supabase test db ran no pgTAP test" >&2
  exit 1
fi
echo "ran ${tests%% *} pgTAP tests in ${tests##* } files against the stack $SUPABASE_PROJECT_ID, selected by supabase test db: every file under supabase/tests/"
