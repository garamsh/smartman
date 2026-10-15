#!/usr/bin/env bash
# Runs the web app's study e2e spec, web/e2e/study.spec.ts, against the built web app and a local
# stack of its own, or says why it did not. The stack follows ADR 0014's pattern for the database
# tests: its own project id and reserved ports, stopped with its data however the run ends. It
# runs Postgres, Auth, PostgREST and the API gateway; the app is built with the stack's URL and
# publishable key, which a build freezes, and served as the image serves it, by its standalone
# server.
set -euo pipefail
cd "$(dirname "$0")/.."

spec=e2e/study.spec.ts

if ! command -v docker >/dev/null 2>&1; then
  echo "skipped the web e2e spec web/$spec: it needs Docker, and this host has no docker command"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "skipped the web e2e spec web/$spec: it needs Docker, and docker info reached no daemon on this host"
  exit 0
fi
if ! command -v node >/dev/null 2>&1; then
  echo "skipped the web e2e spec web/$spec: this host has no node command"
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
  echo "found no free port in $1-$2 for the web e2e run; reservations are under $reservations" >&2
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
web_port=$(reserve 54600 54699) || { release; exit 1; }
reserved+=("$web_port")

export SUPABASE_PROJECT_ID="smartman_web_$db_port" SUPABASE_DB_PORT="$db_port" SUPABASE_API_PORT="$api_port"

server=""
# Stop prunes containers, volumes and networks, and Docker refuses a prune while another stack's
# stop is pruning, so a failed stop is retried. A stack left behind fails the run.
stop() {
  local status=$? attempt stopped
  if [ -n "$server" ]; then
    kill "$server" 2>/dev/null || true
    wait "$server" 2>/dev/null || true
    rm -f "$server_log"
  fi
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if stopped=$(supabase stop --no-backup 2>&1); then
      release
      exit "$status"
    fi
    sleep 2
  done
  echo "$stopped" >&2
  echo "could not stop the web e2e stack $SUPABASE_PROJECT_ID after $attempt attempts; remove it with: supabase stop --no-backup --project-id $SUPABASE_PROJECT_ID" >&2
  release
  [ "$status" -ne 0 ] || status=1
  exit "$status"
}
trap stop EXIT
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

# The image copies the static files beside the standalone server; so does this run.
(cd web && NEXT_PUBLIC_SUPABASE_URL="$url" NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="$key" \
  NEXT_TELEMETRY_DISABLED=1 npx next build >/dev/null)
rm -rf web/.next/standalone/.next/static
cp -R web/.next/static web/.next/standalone/.next/static
server_log=$(mktemp)
PORT="$web_port" HOSTNAME=127.0.0.1 NODE_ENV=production node web/.next/standalone/server.js >"$server_log" 2>&1 &
server=$!
base="http://127.0.0.1:$web_port"
tries=0
until curl --silent --fail --output /dev/null "$base/api/health"; do
  tries=$((tries + 1))
  if [ "$tries" -gt 60 ]; then
    cat "$server_log" >&2
    echo "the web app built for the stack did not answer $base/api/health within 60 s" >&2
    exit 1
  fi
  sleep 1
done

output=$(cd web && npx playwright install chromium >/dev/null &&
  E2E_BASE_URL="$base" E2E_SUPABASE_URL="$url" E2E_SUPABASE_KEY="$key" \
    npx playwright test "$spec" 2>&1) || { echo "$output"; echo "the web app's log:"; cat "$server_log"; exit 1; }
echo "$output"

# Playwright's list reporter ends with "<n> passed", and names any skipped test "<n> skipped".
passed=$(echo "$output" | sed -n 's/^ *\([0-9]*\) passed.*$/\1/p' | tail -n 1)
if [ -z "$passed" ] || [ "$passed" -eq 0 ] || echo "$output" | grep -qE '^ *[0-9]+ skipped'; then
  echo "the web e2e spec skipped or ran no test against the stack $SUPABASE_PROJECT_ID" >&2
  exit 1
fi
echo "ran $passed web e2e tests against the web app built for the stack $SUPABASE_PROJECT_ID, selected by: every test in web/$spec"
