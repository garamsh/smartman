#!/usr/bin/env bash
# Runs the pgTAP tests in supabase/tests/ against a local stack of its own, or says why it did not.
# The stack gets its own project id and database port, so concurrent runs and the shared
# smartman stack never meet; it is stopped, with its data, however the run ends.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/skip.sh

if ! command -v docker >/dev/null 2>&1; then
  skip "the database tests in supabase/tests/: they need Docker, and this host has no docker command"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  skip "the database tests in supabase/tests/: they need Docker, and docker info reached no daemon on this host"
  exit 0
fi

stack="the test stack"
. scripts/test-stack.sh
reserve port 54400 54499 || exit 1

export SUPABASE_PROJECT_ID="smartman_test_$port" SUPABASE_DB_PORT="$port"

trap 'stop_stack $?' EXIT
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
