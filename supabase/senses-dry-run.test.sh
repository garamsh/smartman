#!/usr/bin/env bash
# Tests supabase/senses-dry-run.sh against a local stack of its own, or says why it did not: a
# fixture of a card in each recognised form, a mixed card, a note, an unrecognised label, a back of
# two blocks and a deleted card, then the report's counts, forms and bare-form list, that no row
# changed, and that the migration then converts as many cards as the report counts. The stack is
# stopped, with its data, however the run ends (ADR 0014).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "skipped the senses dry-run test: it needs Docker, and docker reached no daemon on this host"
  exit 0
fi

stack="the senses dry-run test stack"
. supabase/test-stack.sh
reserve port 54400 54499 || exit 1
export SUPABASE_PROJECT_ID="smartman_dryrun_$port" SUPABASE_DB_PORT="$port"
report=$(mktemp -d)
trap 'rm -rf "$report"; stop_stack $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

supabase start --exclude gotrue,realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >/dev/null
sql() { docker exec -i "supabase_db_$SUPABASE_PROJECT_ID" psql -U postgres -d postgres -X -q -A -t -v ON_ERROR_STOP=1; }

sql <<'SQL'
insert into auth.users (id, email) values ('00000000-0000-4000-8000-00000000000a', 'a@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at)
  values ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'Words', now(), now());
insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at, deleted_at)
select ('c0000000-0000-4000-8000-000000000' || id)::uuid, '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000a',
  jsonb_build_array(jsonb_build_object('type', 'text', 'payload', jsonb_build_object('text', id))),
  back::jsonb, id, 'manual', now(), now(), deleted
from (values
  ('c01', '[{"type":"text","payload":{"text":"[명] 사과\n[동] 먹다"}}]', null::timestamptz),
  ('c02', '[{"type":"text","payload":{"text":"(명) 사과"}}]', null),
  ('c03', '[{"type":"text","payload":{"text":"명. 사과"}}]', null),
  ('c04', '[{"type":"text","payload":{"text":"n. apple"}}]', null),
  ('c05', '[{"type":"text","payload":{"text":"명 사과"}}]', null),
  ('c06', '[{"type":"text","payload":{"text":"[명] 사과\n과일의 한 종류"}}]', null),
  ('c07', '[{"type":"text","payload":{"text":"빛 에너지로 포도당을 만드는 과정"}}]', null),
  ('c09', '[{"type":"text","payload":{"text":"[명] 사과"}},{"type":"text","payload":{"text":"[명] 능금"}}]', null),
  ('c10', '[{"type":"text","payload":{"text":"[명] 사과"}}]', now()),
  ('c11', '[{"type":"text","payload":{"text":"[명사] 사과"}}]', null),
  ('c12', '[{"type":"text","payload":{"text":"조동 can"}}]', null)
) as fixture (id, back, deleted);
SQL

before=$(echo "select md5(string_agg(c::text, '' order by id)) from public.cards c;" | sql)
supabase/senses-dry-run.sh "$SUPABASE_PROJECT_ID" "$report/report" >/dev/null
after=$(echo "select md5(string_agg(c::text, '' order by id)) from public.cards c;" | sql)

check() {
  if ! jq -e "$2" "$report/report.json" >/dev/null; then
    echo "the senses dry run's report fails: $1" >&2
    jq . "$report/report.json" >&2
    exit 1
  fi
}
check "the deleted card is not read, and the back of two blocks is left alone" \
  '.live_cards == 10 and .text_backs == 9 and .left_alone.not_one_text_block == 1'
check "a card of each form converts, and only those" '.convertible == 6'
check "the mixed card and the note are left alone, as is an unrecognised label" \
  '.left_alone.mixed == 1 and .left_alone.no_sense_line == 2'
check "each form counts its cards and lines" \
  '[.forms[] | [.form, .cards, .lines]]
   == [["bracket", 1, 2], ["paren", 1, 1], ["dot", 2, 2], ["bare", 2, 2]]'
check "every bare-form line is listed, the longest label first" \
  '[.bare[] | [.id[-3:], .label, .category, .meaning]]
   == [["c05", "명", "noun", "사과"], ["c12", "조동", "auxiliary", "can"]]'
check "the samples are the converting cards of each form" \
  '[.forms[] | select(.form == "dot") | .samples[] | [.id[-3:], .front]]
   == [["c03", "c03"], ["c04", "c04"]] and [.mixed_samples[].id[-3:]] == ["c06"]'
if [ "$before" != "$after" ]; then
  echo "the senses dry run changed public.cards" >&2
  exit 1
fi
grep -q "Would convert: 6" "$report/report.md" || { echo "the Markdown report does not state the count" >&2; exit 1; }
# The apply converts exactly what the dry run reported, on the same fixture.
applied=$(echo "select private.migrate_senses();" | sql)
if [ "$applied" != "$(jq .convertible "$report/report.json")" ]; then
  echo "the migration converted $applied cards where the dry run reported $(jq .convertible "$report/report.json")" >&2
  exit 1
fi
echo "checked the senses dry run's report on 11 fixture cards, 6 converting in each recognised form, the mixed card, the note, the unrecognised label, the two-block back and the deleted card left out, public.cards unchanged, and the migration converting the same 6"
