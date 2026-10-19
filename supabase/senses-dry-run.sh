#!/usr/bin/env bash
# Runs the read-only dry run of #228's senses migration, supabase/senses-dry-run.sql, against the
# Postgres of a running local stack, and writes its report: <out>.json as the query returns it, and
# <out>.md for review (#228). The query runs in a read-only transaction that is rolled back,
# so it writes nothing. To dry-run a copy of production, restore the copy into a local stack first.
#
# Usage: supabase/senses-dry-run.sh <project id of the running stack> <out path, without extension>
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <project id of the running local stack> <report path, without extension>" >&2
  exit 2
fi
project=$1
out=$2
container="supabase_db_$project"
if ! docker inspect "$container" >/dev/null 2>&1; then
  echo "no running local stack's database named $container; start one, or restore a copy into it" >&2
  exit 1
fi

report=$({
  echo 'begin transaction read only;'
  cat supabase/senses-dry-run.sql
  echo 'rollback;'
} | docker exec -i "$container" psql -U postgres -d postgres -X -q -A -t -v ON_ERROR_STOP=1)
report=$(echo "$report" | grep -v '^$')
echo "$report" | jq . >"$out.json"

jq -r '
  def cards: map("  - `\(.id)` \(.front): " + (.back | gsub("\n"; " / "))) | join("\n");
  [
    "# Senses migration dry run",
    "",
    "Read-only: nothing was written. The rules are those of supabase/senses-dry-run.sql (#228).",
    "",
    "- Live cards: \(.live_cards); with a back of one text block: \(.text_backs).",
    "- Would convert: \(.convertible).",
    "- Left alone: \(.left_alone.not_one_text_block) not one text block, \(.left_alone.mixed) mixed, \(.left_alone.no_sense_line) with no sense line.",
    "",
    "## Forms",
    "",
    (.forms | map(
      "- \(.form): \(.cards) cards, \(.lines) lines" +
      (if (.samples | length) > 0 then "\n" + (.samples | cards) else "" end)
    ) | join("\n")),
    "",
    "## Every bare-form line, for review",
    "",
    (if (.bare | length) == 0 then "None." else
      (.bare | map("- `\(.id)`: \(.line) -> [\(.label)] \(.category), \(.meaning)") | join("\n")) end),
    "",
    "## Mixed cards left alone, a sample",
    "",
    (if (.mixed_samples | length) == 0 then "None." else (.mixed_samples | cards) end)
  ] | join("\n")
' "$out.json" >"$out.md"

echo "wrote $out.json and $out.md: $(jq .convertible "$out.json") of $(jq .live_cards "$out.json") live cards would convert, read-only from $container"
