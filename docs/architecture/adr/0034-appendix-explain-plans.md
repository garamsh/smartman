# EXPLAIN plans for ADR 0034

The measurements behind [ADR 0034](0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md): the scripts that seeded a local stack and an SQLite file, the queries timed, and every plan before and after the target schema. Taken on 2026-10-16 at `b4958d2`, and for the queries #95 added at `cf494ca`; frozen with the ADR.

## Setup

- Server: a throwaway Postgres-only stack started as `supabase/test-db.sh` starts one, under a `smartman_test_<port>` project id, with the port reserved through `supabase/test-stack.sh` and stopped on exit. Supabase CLI 2.120.0, PostgreSQL 17.11 (aarch64). The migrations on `main` were applied, then the seed below.
- Each server query ran as `authenticated` under row-level security, with the JWT claims of the user named in it, through `EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)`. Writes roll back.
- The query file ran twice before the target schema and twice after it. The plans below are each second, warm run; the first, cold run is discarded.
- "After" is the target schema of ADR 0034 applied to the same seed: the uuid conversion, the new indexes and the merged select policies (the target DDL below).
- The probe ran once, as `supabase_admin` (`CHECKPOINT` needs `pg_checkpoint`), on a separate seed of the same script. It covers the locale, the text search configurations, pg_trgm on Korean, and the v4 against v7 insert benchmark.
- Phone: `sqlite3` 3.51.0 (macOS), on schema v5 as drift creates it, with the seed below, before and after the proposed indexes. Rows the queries return are left out; plans and times are kept.

## Seed

```sql
-- Seed: user 0 (the subject) is a heavy user; 1,999 others are ordinary. Triggers and FK checks
-- are off while seeding (replica role); revisions are drawn from the real sequence.
\timing on
set session_replication_role = replica;
insert into auth.users (id, email)
select ('00000000-0000-4000-8000-' || lpad(to_hex(u), 12, '0'))::uuid, 'u' || u || '@example.com'
from generate_series(0, 1999) u;

create temporary table seed_decks as
select gen_random_uuid()::text as id,
       ('00000000-0000-4000-8000-' || lpad(to_hex(u), 12, '0'))::uuid as user_id,
       u, d,
       case when u = 0 then 500 else 100 end as cards
from generate_series(0, 1999) u
cross join lateral generate_series(1, case when u = 0 then 20 else 3 end) d;

insert into public.decks (id, user_id, name, created_at, updated_at, deleted_at, revision,
  visibility, published_at, description, import_count)
select id, user_id, 'deck ' || u || '-' || d,
  now() - interval '400 days', now() - (random() * interval '300 days'),
  case when u > 0 and random() < 0.05 then now() - (random() * interval '200 days') end,
  nextval('private.revision'),
  case when u > 0 and u % 3 = 0 then 'public' else 'private' end,
  case when u > 0 and u % 3 = 0 then now() - (random() * interval '300 days') end,
  case when u > 0 and u % 3 = 0 then '영단어 단어장 ' || u end,
  case when u > 0 and u % 3 = 0 then (random() * 50)::int else 0 end
from seed_decks;

insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at,
  updated_at, deleted_at, revision)
select gen_random_uuid()::text, s.user_id, s.id,
  jsonb_build_array(jsonb_build_object('type', 'text', 'text', 'word ' || c)),
  jsonb_build_array(jsonb_build_object('type', 'text', 'text', '뜻 ' || c)),
  'word ' || c, 'manual',
  now() - interval '390 days' + c * interval '1 minute', now() - (random() * interval '300 days'),
  case when random() < 0.10 then now() - (random() * interval '200 days') end,
  nextval('private.revision')
from seed_decks s cross join lateral generate_series(1, s.cards) c;

insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at,
  revision, fuzz_factor)
select gen_random_uuid()::text, c.user_id, c.id,
  case when random() < 0.8 then 'good' else 'again' end, t, (2000 + random() * 15000)::int, t,
  nextval('private.revision'), random() * 0.999
from public.cards c
cross join lateral (
  select now() - (random() * interval '365 days') as t
  from generate_series(1, case when c.user_id = '00000000-0000-4000-8000-000000000000' then 10 else 3 end)
) r;

insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due,
  updated_at, revision)
select c.user_id, c.id, 1 + random() * 100, 1 + random() * 9, now() - interval '3 days',
  now() + (random() * interval '60 days') - interval '10 days', now() - interval '3 days',
  nextval('private.revision')
from public.cards c;

insert into public.profiles (user_id, display_name)
select ('00000000-0000-4000-8000-' || lpad(to_hex(u), 12, '0'))::uuid, '사용자' || u
from generate_series(0, 1999) u;

insert into public.user_blocks (blocker_id, blocked_id)
select distinct ('00000000-0000-4000-8000-' || lpad(to_hex(a), 12, '0'))::uuid,
  ('00000000-0000-4000-8000-' || lpad(to_hex(b), 12, '0'))::uuid
from (select (random() * 1999)::int as a, (random() * 1999)::int as b from generate_series(1, 20000)) x
where a <> b;

insert into public.deck_reports (deck_id, reporter_id, reason)
select distinct on (d.id, r.u) d.id, ('00000000-0000-4000-8000-' || lpad(to_hex(r.u), 12, '0'))::uuid, 'spam'
from (select id from public.decks where visibility = 'public' order by random() limit 2000) d
cross join lateral (select 1 + (random() * 1998)::int as u from generate_series(1, 3)) r;

insert into public.deck_imports (deck_id, user_id)
select distinct on (d.id, r.u) d.id, ('00000000-0000-4000-8000-' || lpad(to_hex(r.u), 12, '0'))::uuid
from (select id from public.decks where visibility = 'public') d
cross join lateral (select 1 + (random() * 1998)::int as u from generate_series(1, 10)) r;

insert into public.extraction_usage (user_id, created_at)
select ('00000000-0000-4000-8000-' || lpad(to_hex((random() * 1999)::int), 12, '0'))::uuid,
  now() - (random() * interval '90 days')
from generate_series(1, 50000);

set session_replication_role = origin;
vacuum analyze;
select relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) as total
from pg_stat_user_tables where schemaname = 'public' order by relname;
```

Table sizes after seeding:

```text
     relname      | n_live_tup |  total  
------------------+------------+---------
 card_states      |     609700 | 165 MB
 cards            |     609700 | 286 MB
 deck_imports     |      19980 | 3352 kB
 deck_reports     |       5994 | 1096 kB
 decks            |       6017 | 2248 kB
 extraction_usage |      50000 | 6584 kB
 profiles         |       2000 | 256 kB
 reviews          |    1899129 | 612 MB
 user_blocks      |      19943 | 2560 kB
(9 rows)

Time: 92.328 ms
```

## Queries

```sql
-- The real queries, each as its client sends it (file:line in the label), run as the
-- authenticated user under row-level security. EXPLAIN (ANALYZE, BUFFERS); writes roll back.
\pset pager off
select id as public_deck from public.decks
  where visibility = 'public' and not hidden and deleted_at is null order by id limit 1 \gset
select id as review_id from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' order by id limit 1 \gset
select max(revision) - 5000 as cursor from public.cards
  where user_id = '00000000-0000-4000-8000-000000000000' \gset
select '{' || array_to_string(array(select id::text from public.decks
  where user_id = '00000000-0000-4000-8000-000000000000' order by id limit 3), ',') || '}' as three_decks \gset

begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-000000000000","role":"authenticated"}';

\echo '### Q1 pull a page: app/lib/sync/src/supabase_sync_server.dart:56-62 (cards)'
explain (analyze, buffers, costs off, summary on)
select * from public.cards where user_id = '00000000-0000-4000-8000-000000000000'
  and revision > :cursor order by revision limit 500;

\echo '### Q2 pace: web/src/features/study/read-pace.ts:28-34'
explain (analyze, buffers, costs off, summary on)
select duration_ms from public.reviews where user_id = '00000000-0000-4000-8000-000000000000'
  and deleted_at is null order by reviewed_at desc limit 200;

\echo '### Q3 reviews of one study day (#87, #89, #90 on the web)'
explain (analyze, buffers, costs off, summary on)
select card_id, rating, reviewed_at from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  and reviewed_at >= now() - interval '1 day' and reviewed_at < now();

\echo '### Q4 deck list, decks page and count: web/src/features/decks/read-library.ts:48-56'
explain (analyze, buffers, costs off, summary on)
select id, name, visibility from public.decks
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  order by id limit 1000 offset 0;
explain (analyze, buffers, costs off, summary on)
select count(*) from public.decks
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null;

\echo '### Q5 deck list, cards page and count: web/src/features/decks/read-library.ts:59-67'
explain (analyze, buffers, costs off, summary on)
select id, deck_id, created_at from public.cards
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  order by id limit 1000 offset 0;
explain (analyze, buffers, costs off, summary on)
select count(*) from public.cards
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null;

\echo '### Q6 a study selection, cards of three decks: web/src/features/decks/read-library.ts:64'
explain (analyze, buffers, costs off, summary on)
select id, deck_id, front, back, created_at from public.cards
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  and deck_id = any (:'three_decks')
  order by id limit 1000 offset 0;

\echo '### Q7 card states: web/src/features/study/read-states.ts:24-32'
explain (analyze, buffers, costs off, summary on)
select card_id, stability, difficulty, last_review, due from public.card_states
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  order by card_id limit 1000 offset 0;

\echo '### Q8 toggle a review: app/lib/sync/src/supabase_sync_server.dart:152-156, web/src/features/study/record-answer.ts:53-57'
explain (analyze, buffers, costs off, summary on)
update public.reviews set rating = 'good', updated_at = now()
  where id = :'review_id' and updated_at < now();
commit;

begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';
\echo '### Q9 preview a public deck as another user: app/lib/sharing/src/supabase_sharing_server.dart:62-69'
explain (analyze, buffers, costs off, summary on)
select front, back from public.cards where deck_id = :'public_deck' and deleted_at is null
  order by created_at, id limit 50 offset 0;

\echo '### Q10 list public decks, newest: list_public_decks body (app/lib/sharing/src/supabase_sharing_server.dart:34-45)'
explain (analyze, buffers, costs off, summary on)
select d.id, d.user_id, d.name, d.description, p.display_name,
  (select count(*) from public.cards as c
    where c.user_id = d.user_id and c.deck_id = d.id and c.deleted_at is null),
  d.import_count, d.published_at
from public.decks as d join public.profiles as p on p.user_id = d.user_id
where d.visibility = 'public' and not d.hidden and d.deleted_at is null
  and not exists (select 1 from public.user_blocks as b
    where b.blocker_id = (select auth.uid()) and b.blocked_id = d.user_id)
order by d.published_at desc, d.id limit 50 offset 0;

\echo '### Q11 list public decks, most copied, searching 단어'
explain (analyze, buffers, costs off, summary on)
select d.id, d.user_id, d.name, d.description, p.display_name,
  (select count(*) from public.cards as c
    where c.user_id = d.user_id and c.deck_id = d.id and c.deleted_at is null),
  d.import_count, d.published_at
from public.decks as d join public.profiles as p on p.user_id = d.user_id
where d.visibility = 'public' and not d.hidden and d.deleted_at is null
  and not exists (select 1 from public.user_blocks as b
    where b.blocker_id = (select auth.uid()) and b.blocked_id = d.user_id)
  and (strpos(lower(d.name), lower('단어')) > 0
    or strpos(lower(coalesce(d.description, '')), lower('단어')) > 0)
order by d.import_count desc nulls last, d.published_at desc, d.id limit 50 offset 0;
commit;

\echo '### Q12 delete an account: the auth.users cascade (ADR 0026), as the admin API runs it'
begin;
explain (analyze, buffers, costs off, summary on)
delete from auth.users where id = '00000000-0000-4000-8000-000000000003';
rollback;

\echo '### Q13 purge tombstones older than the horizon (proposed; cards)'
begin;
explain (analyze, buffers, costs off, summary on)
delete from public.cards where deleted_at is not null and revision <= :cursor;
rollback;
```

## Target DDL

```sql
-- The proposed target, applied to the seeded stack: the keys' check, the conversion to uuid in one
-- transaction, then the new indexes. \timing gives each step's time.
\timing on
\pset pager off
\echo '### check: every id column holds canonical lowercase uuids that round-trip losslessly'
select 'decks.id' as col, count(*) filter (where not (id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and pg_input_is_valid(id, 'uuid'))) as bad from public.decks
union all select 'cards.id', count(*) filter (where not (id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) from public.cards
union all select 'cards.deck_id', count(*) filter (where not (deck_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) from public.cards
union all select 'cards.origin_deck_id', count(*) filter (where origin_deck_id is not null and not (origin_deck_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) from public.cards
union all select 'reviews.id', count(*) filter (where not (id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) from public.reviews
union all select 'reviews.card_id', count(*) filter (where not (card_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) from public.reviews
union all select 'card_states.card_id', count(*) filter (where not (card_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) from public.card_states
union all select 'deck_reports.deck_id', count(*) filter (where not (deck_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) from public.deck_reports
union all select 'deck_imports.deck_id', count(*) filter (where not (deck_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) from public.deck_imports;

\echo '### fingerprint'
select 'reviews' as t, count(*), md5(string_agg(id::text || '/' || card_id::text, ',' order by id::text)) from public.reviews
union all select 'cards', count(*), md5(string_agg(id::text || '/' || deck_id::text, ',' order by id::text)) from public.cards
union all select 'decks', count(*), md5(string_agg(id::text, ',' order by id::text)) from public.decks;

\echo '### probe: a plain ALTER COLUMN TYPE with the policies in place'
do $$
begin
  begin
    alter table public.cards alter column deck_id type uuid using deck_id::uuid;
  exception when others then
    raise notice 'policies in place: % (%)', sqlerrm, sqlstate;
  end;
  begin
    drop policy cards_select_public on public.cards;
    drop policy deck_reports_insert on public.deck_reports;
    alter table public.decks alter column id type uuid using id::uuid;
    raise exception 'no error';
  exception when others then
    raise notice 'policies dropped, foreign keys in place: % (%)', sqlerrm, sqlstate;
  end;
end;
$$;

\echo '### convert: one transaction'
begin;
alter table public.cards drop constraint cards_user_id_deck_id_fkey;
alter table public.reviews drop constraint reviews_user_id_card_id_fkey;
alter table public.card_states drop constraint card_states_user_id_card_id_fkey;
alter table public.deck_reports drop constraint deck_reports_deck_id_fkey;
alter table public.deck_imports drop constraint deck_imports_deck_id_fkey;
drop policy cards_select_public on public.cards;
drop policy deck_reports_insert on public.deck_reports;
alter table public.decks alter column id type uuid using id::uuid;
alter table public.cards alter column id type uuid using id::uuid,
  alter column deck_id type uuid using deck_id::uuid,
  alter column origin_deck_id type uuid using origin_deck_id::uuid;
alter table public.reviews alter column id type uuid using id::uuid,
  alter column card_id type uuid using card_id::uuid;
alter table public.card_states alter column card_id type uuid using card_id::uuid;
alter table public.deck_reports alter column deck_id type uuid using deck_id::uuid;
alter table public.deck_imports alter column deck_id type uuid using deck_id::uuid;
alter table public.cards add constraint cards_user_id_deck_id_fkey foreign key (user_id, deck_id)
  references public.decks (user_id, id) on delete cascade;
alter table public.reviews add constraint reviews_user_id_card_id_fkey foreign key (user_id, card_id)
  references public.cards (user_id, id) on delete cascade;
alter table public.card_states add constraint card_states_user_id_card_id_fkey foreign key (user_id, card_id)
  references public.cards (user_id, id) on delete cascade;
alter table public.deck_reports add constraint deck_reports_deck_id_fkey foreign key (deck_id)
  references public.decks on delete cascade;
alter table public.deck_imports add constraint deck_imports_deck_id_fkey foreign key (deck_id)
  references public.decks on delete cascade;
create policy cards_select_public on public.cards for select to authenticated
  using (
    deleted_at is null
    and exists (
      select 1 from public.decks as d
      where d.user_id = cards.user_id and d.id = cards.deck_id
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null
    )
  );
create policy deck_reports_insert on public.deck_reports for insert to authenticated
  with check (
    (select auth.uid()) = reporter_id
    and exists (
      select 1 from public.decks as d
      where d.id = deck_reports.deck_id and d.user_id <> (select auth.uid())
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null
    )
  );
drop function public.list_public_decks(text, text, integer, integer);
drop function public.record_deck_import(text);
create function public.list_public_decks(
  search text default '',
  sort text default 'newest',
  page_size integer default 50,
  page_offset integer default 0
) returns table (
  id uuid,
  user_id uuid,
  name text,
  description text,
  display_name text,
  card_count bigint,
  import_count integer,
  published_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if sort not in ('newest', 'copied') then
    raise exception 'sort must be newest or copied, not %', sort using errcode = '22023';
  end if;
  return query
  select d.id, d.user_id, d.name, d.description, p.display_name,
    (select count(*) from public.cards as c
      where c.user_id = d.user_id and c.deck_id = d.id and c.deleted_at is null),
    d.import_count, d.published_at
  from public.decks as d
  join public.profiles as p on p.user_id = d.user_id
  where d.visibility = 'public' and not d.hidden and d.deleted_at is null
    and not exists (
      select 1 from public.user_blocks as b
      where b.blocker_id = (select auth.uid()) and b.blocked_id = d.user_id
    )
    and (
      search = ''
      or strpos(lower(d.name), lower(search)) > 0
      or strpos(lower(coalesce(d.description, '')), lower(search)) > 0
    )
  order by
    case when sort = 'copied' then d.import_count end desc nulls last,
    d.published_at desc,
    d.id
  limit page_size offset page_offset;
end;
$$;

create function public.record_deck_import(deck_id uuid) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.decks as d
    where d.id = record_deck_import.deck_id
      and d.visibility = 'public' and not d.hidden and d.deleted_at is null
  ) then
    return false;
  end if;
  insert into public.deck_imports (deck_id, user_id)
    select d.id, (select auth.uid()) from public.decks as d
    where d.id = record_deck_import.deck_id and d.user_id <> (select auth.uid())
    on conflict do nothing;
  if found then
    update public.decks as d set import_count = d.import_count + 1
      where d.id = record_deck_import.deck_id;
  end if;
  return true;
end;
$$;

create or replace function private.hide_reported_deck() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.deck_id::text, 2));
  if (select count(*) from public.deck_reports as r where r.deck_id = new.deck_id) >= 3 then
    update public.decks set hidden = true where id = new.deck_id and not hidden;
  end if;
  return null;
end;
$$;


commit;
\echo '### fingerprint'
select 'reviews' as t, count(*), md5(string_agg(id::text || '/' || card_id::text, ',' order by id::text)) from public.reviews
union all select 'cards', count(*), md5(string_agg(id::text || '/' || deck_id::text, ',' order by id::text)) from public.cards
union all select 'decks', count(*), md5(string_agg(id::text, ',' order by id::text)) from public.decks;

select count(*) as listed from public.list_public_decks();
\echo '### indexes'
create index cards_deck_id_created_at_id on public.cards (deck_id, created_at, id);
drop index public.cards_user_id_deck_id;
create index reviews_live_user_id_reviewed_at on public.reviews (user_id, reviewed_at)
  where deleted_at is null;
create index deck_reports_reporter_id on public.deck_reports (reporter_id);
create index user_blocks_blocked_id on public.user_blocks (blocked_id);
create index deck_imports_user_id on public.deck_imports (user_id);
create index decks_tombstone_revision on public.decks (revision) where deleted_at is not null;
create index cards_tombstone_revision on public.cards (revision) where deleted_at is not null;
create index card_states_tombstone_revision on public.card_states (revision) where deleted_at is not null;
\echo '### one select policy per table, the owner first'
drop policy decks_select on public.decks;
drop policy decks_select_public on public.decks;
create policy decks_select on public.decks for select to authenticated
  using ((select auth.uid()) = user_id or (visibility = 'public' and not hidden and deleted_at is null));
drop policy cards_select on public.cards;
drop policy cards_select_public on public.cards;
create policy cards_select on public.cards for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (deleted_at is null and exists (
      select 1 from public.decks as d
      where d.user_id = cards.user_id and d.id = cards.deck_id
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null))
  );
drop policy profiles_select on public.profiles;
drop policy profiles_select_public on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1 from public.decks as d
      where d.user_id = profiles.user_id
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null)
  );
analyze;
select relname, pg_size_pretty(pg_total_relation_size(relid)) as total
from pg_stat_user_tables where schemaname = 'public' order by relname;
```

Its output, with each statement's time:

```text
Timing is on.
Pager usage is off.
### check: every id column holds canonical lowercase uuids that round-trip losslessly
         col          | bad
----------------------+-----
 deck_reports.deck_id |   0
 decks.id             |   0
 deck_imports.deck_id |   0
 cards.deck_id        |   0
 card_states.card_id  |   0
 cards.origin_deck_id |   0
 cards.id             |   0
 reviews.id           |   0
 reviews.card_id      |   0
(9 rows)
Time: 16410.260 ms (00:16.410)
### fingerprint
    t    |  count  |               md5
---------+---------+----------------------------------
 decks   |    6017 | 0f4a3f839e7c61fb6054dbaa94bf0d41
 cards   |  609700 | 28a591b725008ea89d5d9cfb88276491
 reviews | 1899100 | fdf27e59679f48fb1978af5ac82e5e0d
(3 rows)
Time: 13446.421 ms (00:13.446)
### probe: a plain ALTER COLUMN TYPE with the policies in place
NOTICE:  policies in place: cannot alter type of a column used in a policy definition (0A000)
NOTICE:  policies dropped, foreign keys in place: foreign key constraint "cards_user_id_deck_id_fkey" cannot be implemented (42804)
DO
Time: 163.589 ms
### convert: one transaction
BEGIN
Time: 0.260 ms
ALTER TABLE
Time: 2.398 ms
ALTER TABLE
Time: 1.226 ms
ALTER TABLE
Time: 0.629 ms
ALTER TABLE
Time: 0.630 ms
ALTER TABLE
Time: 0.425 ms
DROP POLICY
Time: 0.319 ms
DROP POLICY
Time: 0.515 ms
ALTER TABLE
Time: 78.023 ms
ALTER TABLE
Time: 7261.779 ms (00:07.262)
ALTER TABLE
Time: 20202.414 ms (00:20.202)
ALTER TABLE
Time: 2639.747 ms (00:02.640)
ALTER TABLE
Time: 17.955 ms
ALTER TABLE
Time: 27.034 ms
ALTER TABLE
Time: 859.137 ms
ALTER TABLE
Time: 1350.097 ms (00:01.350)
ALTER TABLE
Time: 814.219 ms
ALTER TABLE
Time: 5.562 ms
ALTER TABLE
Time: 5.434 ms
CREATE POLICY
Time: 4.490 ms
CREATE POLICY
Time: 2.596 ms
DROP FUNCTION
Time: 7.307 ms
DROP FUNCTION
Time: 1.230 ms
CREATE FUNCTION
Time: 6.179 ms
CREATE FUNCTION
Time: 0.860 ms
CREATE FUNCTION
Time: 0.783 ms
COMMIT
Time: 298.830 ms
### fingerprint
    t    |  count  |               md5
---------+---------+----------------------------------
 decks   |    6017 | 0f4a3f839e7c61fb6054dbaa94bf0d41
 cards   |  609700 | 28a591b725008ea89d5d9cfb88276491
 reviews | 1899100 | fdf27e59679f48fb1978af5ac82e5e0d
(3 rows)
Time: 11241.702 ms (00:11.242)
 listed
--------
     50
(1 row)
Time: 116.781 ms
### indexes
CREATE INDEX
Time: 1333.520 ms (00:01.334)
DROP INDEX
Time: 14.008 ms
CREATE INDEX
Time: 2600.225 ms (00:02.600)
CREATE INDEX
Time: 10.451 ms
CREATE INDEX
Time: 39.029 ms
CREATE INDEX
Time: 32.711 ms
CREATE INDEX
Time: 5.767 ms
CREATE INDEX
Time: 394.799 ms
CREATE INDEX
Time: 267.605 ms
### one select policy per table, the owner first
DROP POLICY
Time: 2.650 ms
DROP POLICY
Time: 1.529 ms
CREATE POLICY
Time: 5.186 ms
DROP POLICY
Time: 1.094 ms
DROP POLICY
Time: 0.837 ms
CREATE POLICY
Time: 2.804 ms
DROP POLICY
Time: 1.177 ms
DROP POLICY
Time: 0.845 ms
CREATE POLICY
Time: 2.061 ms
ANALYZE
Time: 1810.325 ms (00:01.810)
     relname      |  total
------------------+---------
 card_states      | 121 MB
 cards            | 238 MB
 deck_imports     | 2680 kB
 deck_reports     | 896 kB
 decks            | 1888 kB
 extraction_usage | 6584 kB
 profiles         | 256 kB
 reviews          | 493 MB
 user_blocks      | 2776 kB
(9 rows)
Time: 18.298 ms
```

## Server plans

Before:

```text
BEGIN
SET
SET
### Q1 pull a page: app/lib/sync/src/supabase_sync_server.dart:56-62 (cards)
                                                                            QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=4.032..4.467 rows=500 loops=1)
   Buffers: shared hit=151
   InitPlan 5
     ->  Result (actual time=0.103..0.104 rows=1 loops=1)
   ->  Index Scan using cards_user_id_revision on cards (actual time=4.031..4.409 rows=500 loops=1)
         Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (revision > 11017))
         Filter: (((deleted_at IS NULL) AND (ANY ((user_id = (hashed SubPlan 4).col1) AND (deck_id = (hashed SubPlan 4).col2)))) OR ((InitPlan 5).col1 = user_id))
         Buffers: shared hit=151
         SubPlan 4
           ->  Bitmap Heap Scan on decks d (actual time=0.229..2.720 rows=1885 loops=1)
                 Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                 Heap Blocks: exact=115
                 Buffers: shared hit=124
                 InitPlan 3
                   ->  Result (never executed)
                 ->  Bitmap Index Scan on decks_public_published_at (actual time=0.208..0.208 rows=1885 loops=1)
                       Buffers: shared hit=9
 Planning:
   Buffers: shared hit=90 read=2
 Planning Time: 1.076 ms
 Execution Time: 4.728 ms
(21 rows)

### Q2 pace: web/src/features/study/read-pace.ts:28-34
                                                      QUERY PLAN
----------------------------------------------------------------------------------------------------------------------
 Limit (actual time=100.285..100.316 rows=200 loops=1)
   Buffers: shared hit=2627
   InitPlan 1
     ->  Result (actual time=0.008..0.008 rows=1 loops=1)
   ->  Sort (actual time=100.284..100.296 rows=200 loops=1)
         Sort Key: reviews.reviewed_at DESC
         Sort Method: top-N heapsort  Memory: 37kB
         Buffers: shared hit=2627
         ->  Result (actual time=9.375..85.962 rows=100000 loops=1)
               One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=2624
               ->  Bitmap Heap Scan on reviews (actual time=9.363..73.210 rows=100000 loops=1)
                     Recheck Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                     Filter: (deleted_at IS NULL)
                     Heap Blocks: exact=2129
                     Buffers: shared hit=2624
                     ->  Bitmap Index Scan on reviews_user_id_revision (actual time=9.063..9.063 rows=100001 loops=1)
                           Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                           Buffers: shared hit=495
 Planning:
   Buffers: shared hit=14
 Planning Time: 0.276 ms
 Execution Time: 101.341 ms
(23 rows)

### Q3 reviews of one study day (#87, #89, #90 on the web)
                                                    QUERY PLAN
-------------------------------------------------------------------------------------------------------------------
 Result (actual time=5.858..36.447 rows=284 loops=1)
   One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
   Buffers: shared hit=2624
   InitPlan 1
     ->  Result (actual time=0.012..0.012 rows=1 loops=1)
   ->  Bitmap Heap Scan on reviews (actual time=5.843..36.317 rows=284 loops=1)
         Recheck Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (reviewed_at < now()) AND (reviewed_at >= (now() - '1 day'::interval)))
         Rows Removed by Filter: 99716
         Heap Blocks: exact=2129
         Buffers: shared hit=2624
         ->  Bitmap Index Scan on reviews_user_id_revision (actual time=4.998..4.998 rows=100001 loops=1)
               Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=495
 Planning:
   Buffers: shared hit=17
 Planning Time: 0.329 ms
 Execution Time: 36.905 ms
(18 rows)

### Q4 deck list, decks page and count: web/src/features/decks/read-library.ts:48-56
                                                                       QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.028..0.036 rows=20 loops=1)
   Buffers: shared hit=3
   InitPlan 1
     ->  Result (actual time=0.012..0.012 rows=1 loops=1)
   ->  Index Scan using decks_user_id_id_key on decks (actual time=0.027..0.032 rows=20 loops=1)
         Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL)) OR ((InitPlan 1).col1 = user_id)))
         Buffers: shared hit=3
 Planning:
   Buffers: shared hit=3
 Planning Time: 0.226 ms
 Execution Time: 0.067 ms
(12 rows)

                                                                       QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=0.044..0.045 rows=1 loops=1)
   Buffers: shared hit=3
   InitPlan 1
     ->  Result (actual time=0.007..0.007 rows=1 loops=1)
   ->  Index Scan using decks_user_id_revision on decks (actual time=0.035..0.040 rows=20 loops=1)
         Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL)) OR ((InitPlan 1).col1 = user_id)))
         Buffers: shared hit=3
 Planning:
   Buffers: shared hit=3
 Planning Time: 0.135 ms
 Execution Time: 0.107 ms
(12 rows)

### Q5 deck list, cards page and count: web/src/features/decks/read-library.ts:59-67
                                                                                          QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=1.439..8.259 rows=1000 loops=1)
   Buffers: shared hit=1256
   InitPlan 5
     ->  Result (actual time=0.017..0.017 rows=1 loops=1)
   ->  Index Scan using cards_user_id_id_key on cards (actual time=1.438..8.113 rows=1000 loops=1)
         Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (((deleted_at IS NULL) AND (ANY ((user_id = (hashed SubPlan 4).col1) AND (deck_id = (hashed SubPlan 4).col2)))) OR ((InitPlan 5).col1 = user_id)))
         Rows Removed by Filter: 120
         Buffers: shared hit=1256
         SubPlan 4
           ->  Bitmap Heap Scan on decks d (actual time=0.126..0.601 rows=1885 loops=1)
                 Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                 Heap Blocks: exact=115
                 Buffers: shared hit=124
                 InitPlan 3
                   ->  Result (never executed)
                 ->  Bitmap Index Scan on decks_public_published_at (actual time=0.106..0.106 rows=1885 loops=1)
                       Buffers: shared hit=9
 Planning Time: 0.240 ms
 Execution Time: 8.454 ms
(20 rows)

                                                                                          QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=9.243..9.246 rows=1 loops=1)
   Buffers: shared hit=488
   InitPlan 5
     ->  Result (actual time=0.011..0.012 rows=1 loops=1)
   ->  Index Scan using cards_user_id_deck_id on cards (actual time=1.344..8.303 rows=9004 loops=1)
         Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (((deleted_at IS NULL) AND (ANY ((user_id = (hashed SubPlan 4).col1) AND (deck_id = (hashed SubPlan 4).col2)))) OR ((InitPlan 5).col1 = user_id)))
         Rows Removed by Filter: 996
         Buffers: shared hit=488
         SubPlan 4
           ->  Bitmap Heap Scan on decks d (actual time=0.151..0.611 rows=1885 loops=1)
                 Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                 Heap Blocks: exact=115
                 Buffers: shared hit=124
                 InitPlan 3
                   ->  Result (never executed)
                 ->  Bitmap Index Scan on decks_public_published_at (actual time=0.132..0.133 rows=1885 loops=1)
                       Buffers: shared hit=9
 Planning Time: 0.299 ms
 Execution Time: 9.385 ms
(20 rows)

### Q6 a study selection, cards of three decks: web/src/features/decks/read-library.ts:64
                                                                                                              QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=4.684..4.869 rows=1000 loops=1)
   Buffers: shared hit=4077
   InitPlan 5
     ->  Result (actual time=0.013..0.013 rows=1 loops=1)
   ->  Sort (actual time=4.682..4.763 rows=1000 loops=1)
         Sort Key: cards.id
         Sort Method: quicksort  Memory: 394kB
         Buffers: shared hit=4077
         ->  Index Scan using cards_user_id_deck_id on cards (actual time=0.079..2.704 rows=1339 loops=1)
               Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (deck_id = ANY ('{065c96b7-812e-41a3-a4ba-53221ddc5a95,0886ef45-c9b4-4dd1-845f-93ef94e581ff,0add0283-f28b-47ab-99f7-7c8f26e72abc}'::text[])))
               Filter: ((deleted_at IS NULL) AND (((deleted_at IS NULL) AND EXISTS(SubPlan 2)) OR ((InitPlan 5).col1 = user_id)))
               Rows Removed by Filter: 161
               Buffers: shared hit=4074
               SubPlan 2
                 ->  Index Scan using decks_user_id_id_key on decks d (actual time=0.001..0.001 rows=0 loops=1339)
                       Index Cond: ((user_id = cards.user_id) AND (id = cards.deck_id))
                       Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL)) OR ((InitPlan 1).col1 = user_id)))
                       Rows Removed by Filter: 1
                       Buffers: shared hit=4017
                       InitPlan 1
                         ->  Result (never executed)
 Planning Time: 0.377 ms
 Execution Time: 4.995 ms
(23 rows)

### Q7 card states: web/src/features/study/read-states.ts:24-32
                                                QUERY PLAN
-----------------------------------------------------------------------------------------------------------
 Limit (actual time=0.075..3.368 rows=1000 loops=1)
   Buffers: shared hit=1006
   InitPlan 1
     ->  Result (actual time=0.011..0.011 rows=1 loops=1)
   ->  Result (actual time=0.074..3.260 rows=1000 loops=1)
         One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
         Buffers: shared hit=1006
         ->  Index Scan using card_states_pkey on card_states (actual time=0.061..3.107 rows=1000 loops=1)
               Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
               Filter: (deleted_at IS NULL)
               Buffers: shared hit=1006
 Planning:
   Buffers: shared hit=60
 Planning Time: 0.658 ms
 Execution Time: 3.467 ms
(15 rows)

### Q8 toggle a review: app/lib/sync/src/supabase_sync_server.dart:152-156, web/src/features/study/record-answer.ts:53-57
                                        QUERY PLAN
------------------------------------------------------------------------------------------
 Update on reviews (actual time=8.476..8.477 rows=0 loops=1)
   Buffers: shared hit=110 read=2
   InitPlan 1
     ->  Result (actual time=0.015..0.016 rows=1 loops=1)
   InitPlan 2
     ->  Result (actual time=0.012..0.012 rows=1 loops=1)
   ->  Index Scan using reviews_pkey on reviews (actual time=0.033..0.036 rows=1 loops=1)
         Index Cond: (id = '0000603d-d464-469f-a1bc-adc2f6ce66c4'::text)
         Filter: (((InitPlan 2).col1 = user_id) AND (updated_at < now()))
         Buffers: shared hit=5
 Planning:
   Buffers: shared hit=6
 Planning Time: 0.231 ms
 Trigger set_revision: time=5.959 calls=1
 Execution Time: 8.751 ms
(15 rows)

COMMIT
BEGIN
SET
SET
### Q9 preview a public deck as another user: app/lib/sharing/src/supabase_sharing_server.dart:62-69
                                                                                             QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=6.858..6.869 rows=50 loops=1)
   Buffers: shared hit=682
   InitPlan 5
     ->  Result (never executed)
   ->  Sort (actual time=6.857..6.861 rows=50 loops=1)
         Sort Key: cards.created_at, cards.id
         Sort Method: quicksort  Memory: 49kB
         Buffers: shared hit=682
         ->  Index Scan using cards_user_id_deck_id on cards (actual time=6.466..6.820 rows=94 loops=1)
               Index Cond: (deck_id = '0021c21d-85fe-45eb-9d6a-6a5fd2ccfb67'::text)
               Filter: ((deleted_at IS NULL) AND (((deleted_at IS NULL) AND (ANY ((user_id = (hashed SubPlan 4).col1) AND (deck_id = (hashed SubPlan 4).col2)))) OR ((InitPlan 5).col1 = user_id)))
               Rows Removed by Filter: 6
               Buffers: shared hit=682
               SubPlan 4
                 ->  Bitmap Heap Scan on decks d (actual time=0.128..0.614 rows=1885 loops=1)
                       Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                       Heap Blocks: exact=115
                       Buffers: shared hit=124
                       InitPlan 3
                         ->  Result (never executed)
                       ->  Bitmap Index Scan on decks_public_published_at (actual time=0.100..0.100 rows=1885 loops=1)
                             Buffers: shared hit=9
 Planning Time: 0.309 ms
 Execution Time: 6.930 ms
(24 rows)

### Q10 list public decks, newest: list_public_decks body (app/lib/sharing/src/supabase_sharing_server.dart:34-45)
                                                                                                                    QUERY PLAN
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=1.141..14.492 rows=50 loops=1)
   Buffers: shared hit=14182
   InitPlan 7
     ->  Result (actual time=0.002..0.003 rows=1 loops=1)
   InitPlan 8
     ->  Result (never executed)
   InitPlan 13
     ->  Result (never executed)
   InitPlan 14
     ->  Result (actual time=0.012..0.013 rows=1 loops=1)
   ->  Result (actual time=1.140..14.479 rows=50 loops=1)
         Buffers: shared hit=14182
         ->  Incremental Sort (actual time=0.884..1.189 rows=50 loops=1)
               Sort Key: d.published_at DESC, d.id
               Presorted Key: d.published_at
               Full-sort Groups: 2  Sort Method: quicksort  Average Memory: 33kB  Peak Memory: 33kB
               Buffers: shared hit=372
               ->  Nested Loop Anti Join (actual time=0.196..1.103 rows=51 loops=1)
                     Join Filter: (b.blocked_id = d.user_id)
                     Rows Removed by Join Filter: 258
                     Buffers: shared hit=369
                     ->  Nested Loop (actual time=0.072..0.919 rows=52 loops=1)
                           Buffers: shared hit=366
                           ->  Index Scan using decks_public_published_at on decks d (actual time=0.014..0.084 rows=52 loops=1)
                                 Buffers: shared hit=54
                           ->  Memoize (actual time=0.016..0.016 rows=1 loops=52)
                                 Cache Key: d.user_id
                                 Cache Mode: logical
                                 Hits: 0  Misses: 52  Evictions: 0  Overflows: 0  Memory Usage: 8kB
                                 Buffers: shared hit=312
                                 ->  Index Scan using profiles_pkey on profiles p (actual time=0.014..0.014 rows=1 loops=52)
                                       Index Cond: (user_id = d.user_id)
                                       Filter: (EXISTS(SubPlan 10) OR ((InitPlan 13).col1 = user_id))
                                       Buffers: shared hit=312
                                       SubPlan 10
                                         ->  Index Scan using decks_user_id_revision on decks d_2 (actual time=0.007..0.007 rows=1 loops=52)
                                               Index Cond: (user_id = p.user_id)
                                               Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL)) OR ((InitPlan 9).col1 = user_id)))
                                               Buffers: shared hit=156
                                               InitPlan 9
                                                 ->  Result (never executed)
                     ->  Materialize (actual time=0.002..0.003 rows=5 loops=52)
                           Buffers: shared hit=3
                           ->  Result (actual time=0.116..0.118 rows=5 loops=1)
                                 One-Time Filter: ((InitPlan 14).col1 = (InitPlan 7).col1)
                                 Buffers: shared hit=3
                                 ->  Index Only Scan using user_blocks_pkey on user_blocks b (actual time=0.099..0.101 rows=5 loops=1)
                                       Index Cond: (blocker_id = (InitPlan 7).col1)
                                       Heap Fetches: 0
                                       Buffers: shared hit=3
         SubPlan 6
           ->  Aggregate (actual time=0.265..0.265 rows=1 loops=50)
                 Buffers: shared hit=13810
                 InitPlan 5
                   ->  Result (never executed)
                 ->  Index Scan using cards_user_id_deck_id on cards c (actual time=0.034..0.257 rows=90 loops=50)
                       Index Cond: ((user_id = d.user_id) AND (deck_id = d.id))
                       Filter: ((deleted_at IS NULL) AND (((deleted_at IS NULL) AND EXISTS(SubPlan 2)) OR ((InitPlan 5).col1 = user_id)))
                       Rows Removed by Filter: 10
                       Buffers: shared hit=13810
                       SubPlan 2
                         ->  Index Scan using decks_user_id_id_key on decks d_1 (actual time=0.002..0.002 rows=1 loops=4483)
                               Index Cond: ((user_id = c.user_id) AND (id = c.deck_id))
                               Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL)) OR ((InitPlan 1).col1 = user_id)))
                               Buffers: shared hit=13449
                               InitPlan 1
                                 ->  Result (never executed)
 Planning:
   Buffers: shared hit=188
 Planning Time: 1.520 ms
 Execution Time: 14.761 ms
(71 rows)

### Q11 list public decks, most copied, searching 단어
                                                                                                                    QUERY PLAN
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=8.807..31.291 rows=50 loops=1)
   Buffers: shared hit=17915
   InitPlan 7
     ->  Result (actual time=0.002..0.003 rows=1 loops=1)
   InitPlan 8
     ->  Result (never executed)
   InitPlan 13
     ->  Result (never executed)
   InitPlan 14
     ->  Result (actual time=0.012..0.013 rows=1 loops=1)
   ->  Result (actual time=8.806..31.275 rows=50 loops=1)
         Buffers: shared hit=17915
         ->  Sort (actual time=8.599..8.625 rows=50 loops=1)
               Sort Key: d.import_count DESC NULLS LAST, d.published_at DESC, d.id
               Sort Method: top-N heapsort  Memory: 42kB
               Buffers: shared hit=4130
               ->  Nested Loop Anti Join (actual time=0.245..7.979 rows=1879 loops=1)
                     Join Filter: (b.blocked_id = d.user_id)
                     Rows Removed by Join Filter: 9416
                     Buffers: shared hit=4127
                     ->  Nested Loop (actual time=0.214..6.073 rows=1885 loops=1)
                           Buffers: shared hit=4124
                           ->  Bitmap Heap Scan on decks d (actual time=0.188..3.025 rows=1885 loops=1)
                                 Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                                 Filter: ((strpos(lower(name), '단어'::text) > 0) OR (strpos(lower(COALESCE(description, ''::text)), '단어'::text) > 0))
                                 Heap Blocks: exact=115
                                 Buffers: shared hit=124
                                 ->  Bitmap Index Scan on decks_public_published_at (actual time=0.100..0.100 rows=1885 loops=1)
                                       Buffers: shared hit=9
                           ->  Memoize (actual time=0.001..0.001 rows=1 loops=1885)
                                 Cache Key: d.user_id
                                 Cache Mode: logical
                                 Hits: 1219  Misses: 666  Evictions: 0  Overflows: 0  Memory Usage: 92kB
                                 Buffers: shared hit=4000
                                 ->  Index Scan using profiles_pkey on profiles p (actual time=0.003..0.003 rows=1 loops=666)
                                       Index Cond: (user_id = d.user_id)
                                       Filter: (EXISTS(SubPlan 10) OR ((InitPlan 13).col1 = user_id))
                                       Buffers: shared hit=4000
                                       SubPlan 10
                                         ->  Index Scan using decks_user_id_revision on decks d_2 (actual time=0.001..0.001 rows=1 loops=666)
                                               Index Cond: (user_id = p.user_id)
                                               Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL)) OR ((InitPlan 9).col1 = user_id)))
                                               Rows Removed by Filter: 0
                                               Buffers: shared hit=2002
                                               InitPlan 9
                                                 ->  Result (never executed)
                     ->  Materialize (actual time=0.000..0.000 rows=5 loops=1885)
                           Buffers: shared hit=3
                           ->  Result (actual time=0.025..0.027 rows=5 loops=1)
                                 One-Time Filter: ((InitPlan 14).col1 = (InitPlan 7).col1)
                                 Buffers: shared hit=3
                                 ->  Index Only Scan using user_blocks_pkey on user_blocks b (actual time=0.008..0.009 rows=5 loops=1)
                                       Index Cond: (blocker_id = (InitPlan 7).col1)
                                       Heap Fetches: 0
                                       Buffers: shared hit=3
         SubPlan 6
           ->  Aggregate (actual time=0.451..0.451 rows=1 loops=50)
                 Buffers: shared hit=13785
                 InitPlan 5
                   ->  Result (never executed)
                 ->  Index Scan using cards_user_id_deck_id on cards c (actual time=0.051..0.440 rows=89 loops=50)
                       Index Cond: ((user_id = d.user_id) AND (deck_id = d.id))
                       Filter: ((deleted_at IS NULL) AND (((deleted_at IS NULL) AND EXISTS(SubPlan 2)) OR ((InitPlan 5).col1 = user_id)))
                       Rows Removed by Filter: 11
                       Buffers: shared hit=13785
                       SubPlan 2
                         ->  Index Scan using decks_user_id_id_key on decks d_1 (actual time=0.002..0.002 rows=1 loops=4473)
                               Index Cond: ((user_id = c.user_id) AND (id = c.deck_id))
                               Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL)) OR ((InitPlan 1).col1 = user_id)))
                               Buffers: shared hit=13419
                               InitPlan 1
                                 ->  Result (never executed)
 Planning:
   Buffers: shared hit=30
 Planning Time: 1.443 ms
 Execution Time: 31.462 ms
(76 rows)

COMMIT
### Q12 delete an account: the auth.users cascade (ADR 0026), as the admin API runs it
BEGIN
                                       QUERY PLAN
-----------------------------------------------------------------------------------------
 Delete on users (actual time=0.229..0.229 rows=0 loops=1)
   Buffers: shared hit=43
   ->  Index Scan using users_pkey on users (actual time=0.070..0.071 rows=1 loops=1)
         Index Cond: (id = '00000000-0000-4000-8000-000000000003'::uuid)
         Buffers: shared hit=3
 Planning:
   Buffers: shared hit=178
 Planning Time: 1.046 ms
 Trigger for constraint identities_user_id_fkey on users: time=0.516 calls=1
 Trigger for constraint sessions_user_id_fkey on users: time=0.477 calls=1
 Trigger for constraint mfa_factors_user_id_fkey on users: time=0.581 calls=1
 Trigger for constraint one_time_tokens_user_id_fkey on users: time=0.364 calls=1
 Trigger for constraint oauth_authorizations_user_id_fkey on users: time=0.380 calls=1
 Trigger for constraint oauth_consents_user_id_fkey on users: time=0.436 calls=1
 Trigger for constraint webauthn_credentials_user_id_fkey on users: time=0.401 calls=1
 Trigger for constraint webauthn_challenges_user_id_fkey on users: time=0.292 calls=1
 Trigger for constraint scim_users_user_id_fkey on users: time=0.603 calls=1
 Trigger for constraint mfa_recovery_code_sets_user_id_fkey on users: time=0.262 calls=1
 Trigger for constraint decks_user_id_fkey on users: time=0.118 calls=1
 Trigger for constraint cards_user_id_fkey on users: time=0.838 calls=1
 Trigger for constraint reviews_user_id_fkey on users: time=1.881 calls=1
 Trigger for constraint card_states_user_id_fkey on users: time=0.688 calls=1
 Trigger for constraint extraction_usage_user_id_fkey on users: time=1.274 calls=1
 Trigger for constraint profiles_user_id_fkey on users: time=0.130 calls=1
 Trigger for constraint deck_reports_reporter_id_fkey on users: time=8.618 calls=1
 Trigger for constraint user_blocks_blocker_id_fkey on users: time=0.622 calls=1
 Trigger for constraint user_blocks_blocked_id_fkey on users: time=4.312 calls=1
 Trigger for constraint deck_imports_user_id_fkey on users: time=5.453 calls=1
 Trigger for constraint cards_user_id_deck_id_fkey on decks: time=0.343 calls=3
 Trigger for constraint deck_reports_deck_id_fkey on decks: time=0.218 calls=3
 Trigger for constraint deck_imports_deck_id_fkey on decks: time=0.238 calls=3
 Trigger for constraint reviews_user_id_card_id_fkey on cards: time=2.826 calls=300
 Trigger for constraint card_states_user_id_card_id_fkey on cards: time=2.709 calls=300
 Execution Time: 34.926 ms
(34 rows)

ROLLBACK
### Q13 purge tombstones older than the horizon (proposed; cards)
BEGIN
                                             QUERY PLAN
-----------------------------------------------------------------------------------------------------
 Delete on cards (actual time=54.200..54.200 rows=0 loops=1)
   Buffers: shared hit=4154
   ->  Index Scan using cards_user_id_revision on cards (actual time=0.035..53.541 rows=469 loops=1)
         Index Cond: (revision <= 11017)
         Filter: (deleted_at IS NOT NULL)
         Rows Removed by Filter: 4531
         Buffers: shared hit=3216
 Planning:
   Buffers: shared hit=3
 Planning Time: 0.075 ms
 Trigger for constraint reviews_user_id_card_id_fkey: time=9.123 calls=469
 Trigger for constraint card_states_user_id_card_id_fkey: time=5.292 calls=469
 Execution Time: 68.729 ms
(13 rows)

ROLLBACK
```

After:

```text
BEGIN
SET
SET
### Q1 pull a page: app/lib/sync/src/supabase_sync_server.dart:56-62 (cards)
                                                                            QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.040..0.186 rows=500 loops=1)
   Buffers: shared hit=24
   InitPlan 1
     ->  Result (actual time=0.011..0.012 rows=1 loops=1)
   ->  Index Scan using cards_user_id_revision on cards (actual time=0.040..0.152 rows=500 loops=1)
         Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (revision > 11017))
         Filter: (((InitPlan 1).col1 = user_id) OR ((deleted_at IS NULL) AND (ANY ((user_id = (hashed SubPlan 5).col1) AND (deck_id = (hashed SubPlan 5).col2)))))
         Buffers: shared hit=24
         SubPlan 5
           ->  Bitmap Heap Scan on decks d (never executed)
                 Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                 InitPlan 4
                   ->  Result (never executed)
                 ->  Bitmap Index Scan on decks_public_published_at (never executed)
 Planning:
   Buffers: shared hit=119
 Planning Time: 0.646 ms
 Execution Time: 0.242 ms
(18 rows)

### Q2 pace: web/src/features/study/read-pace.ts:28-34
                                                          QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.018..0.543 rows=200 loops=1)
   Buffers: shared hit=205
   InitPlan 1
     ->  Result (actual time=0.004..0.004 rows=1 loops=1)
   ->  Result (actual time=0.017..0.529 rows=200 loops=1)
         One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
         Buffers: shared hit=205
         ->  Index Scan Backward using reviews_live_user_id_reviewed_at on reviews (actual time=0.012..0.499 rows=200 loops=1)
               Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=205
 Planning:
   Buffers: shared hit=14
 Planning Time: 0.117 ms
 Execution Time: 0.574 ms
(14 rows)

### Q3 reviews of one study day (#87, #89, #90 on the web)
                                                                        QUERY PLAN
-----------------------------------------------------------------------------------------------------------------------------------------------------------
 Result (actual time=0.028..0.217 rows=284 loops=1)
   One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
   Buffers: shared hit=288
   InitPlan 1
     ->  Result (actual time=0.004..0.004 rows=1 loops=1)
   ->  Index Scan using reviews_live_user_id_reviewed_at on reviews (actual time=0.022..0.186 rows=284 loops=1)
         Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (reviewed_at >= (now() - '1 day'::interval)) AND (reviewed_at < now()))
         Buffers: shared hit=288
 Planning:
   Buffers: shared hit=14
 Planning Time: 0.093 ms
 Execution Time: 0.241 ms
(12 rows)

### Q4 deck list, decks page and count: web/src/features/decks/read-library.ts:48-56
                                                                       QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.009..0.013 rows=20 loops=1)
   Buffers: shared hit=3
   InitPlan 1
     ->  Result (actual time=0.003..0.003 rows=1 loops=1)
   ->  Index Scan using decks_user_id_id_key on decks (actual time=0.008..0.012 rows=20 loops=1)
         Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (((InitPlan 1).col1 = user_id) OR ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))))
         Buffers: shared hit=3
 Planning:
   Buffers: shared hit=3
 Planning Time: 0.065 ms
 Execution Time: 0.025 ms
(12 rows)

                                                                       QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=0.010..0.010 rows=1 loops=1)
   Buffers: shared hit=3
   InitPlan 1
     ->  Result (actual time=0.002..0.002 rows=1 loops=1)
   ->  Index Scan using decks_user_id_id_key on decks (actual time=0.005..0.007 rows=20 loops=1)
         Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (((InitPlan 1).col1 = user_id) OR ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))))
         Buffers: shared hit=3
 Planning:
   Buffers: shared hit=3
 Planning Time: 0.052 ms
 Execution Time: 0.026 ms
(12 rows)

### Q5 deck list, cards page and count: web/src/features/decks/read-library.ts:59-67
                                                                                          QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.012..0.940 rows=1000 loops=1)
   Buffers: shared hit=1123
   InitPlan 1
     ->  Result (actual time=0.003..0.003 rows=1 loops=1)
   ->  Index Scan using cards_user_id_id_key on cards (actual time=0.012..0.876 rows=1000 loops=1)
         Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (((InitPlan 1).col1 = user_id) OR ((deleted_at IS NULL) AND (ANY ((user_id = (hashed SubPlan 5).col1) AND (deck_id = (hashed SubPlan 5).col2))))))
         Rows Removed by Filter: 120
         Buffers: shared hit=1123
         SubPlan 5
           ->  Bitmap Heap Scan on decks d (never executed)
                 Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                 InitPlan 4
                   ->  Result (never executed)
                 ->  Bitmap Index Scan on decks_public_published_at (never executed)
 Planning Time: 0.170 ms
 Execution Time: 0.995 ms
(17 rows)

                                                                                          QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=2.042..2.043 rows=1 loops=1)
   Buffers: shared hit=336
   InitPlan 1
     ->  Result (actual time=0.003..0.003 rows=1 loops=1)
   ->  Index Scan using cards_user_id_revision on cards (actual time=0.011..1.523 rows=9004 loops=1)
         Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
         Filter: ((deleted_at IS NULL) AND (((InitPlan 1).col1 = user_id) OR ((deleted_at IS NULL) AND (ANY ((user_id = (hashed SubPlan 5).col1) AND (deck_id = (hashed SubPlan 5).col2))))))
         Rows Removed by Filter: 996
         Buffers: shared hit=336
         SubPlan 5
           ->  Bitmap Heap Scan on decks d (never executed)
                 Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                 InitPlan 4
                   ->  Result (never executed)
                 ->  Bitmap Index Scan on decks_public_published_at (never executed)
 Planning Time: 0.144 ms
 Execution Time: 2.062 ms
(17 rows)

### Q6 a study selection, cards of three decks: web/src/features/decks/read-library.ts:64
                                                                                                               QUERY PLAN
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.888..0.993 rows=1000 loops=1)
   Buffers: shared hit=119
   InitPlan 1
     ->  Result (actual time=0.004..0.004 rows=1 loops=1)
   ->  Sort (actual time=0.887..0.927 rows=1000 loops=1)
         Sort Key: cards.id
         Sort Method: quicksort  Memory: 394kB
         Buffers: shared hit=119
         ->  Bitmap Heap Scan on cards (actual time=0.307..0.518 rows=1339 loops=1)
               Recheck Cond: ((deck_id = ANY ('{065c96b7-812e-41a3-a4ba-53221ddc5a95,0886ef45-c9b4-4dd1-845f-93ef94e581ff,0add0283-f28b-47ab-99f7-7c8f26e72abc}'::uuid[])) AND (user_id = '00000000-0000-4000-8000-000000000000'::uuid))
               Filter: ((deleted_at IS NULL) AND (((InitPlan 1).col1 = user_id) OR ((deleted_at IS NULL) AND EXISTS(SubPlan 3))))
               Rows Removed by Filter: 161
               Heap Blocks: exact=44
               Buffers: shared hit=116
               ->  BitmapAnd (actual time=0.294..0.294 rows=0 loops=1)
                     Buffers: shared hit=72
                     ->  Bitmap Index Scan on cards_deck_id_created_at_id (actual time=0.063..0.063 rows=1500 loops=1)
                           Index Cond: (deck_id = ANY ('{065c96b7-812e-41a3-a4ba-53221ddc5a95,0886ef45-c9b4-4dd1-845f-93ef94e581ff,0add0283-f28b-47ab-99f7-7c8f26e72abc}'::uuid[]))
                           Buffers: shared hit=20
                     ->  Bitmap Index Scan on cards_user_id_revision (actual time=0.229..0.229 rows=10000 loops=1)
                           Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                           Buffers: shared hit=52
               SubPlan 3
                 ->  Index Scan using decks_user_id_id_key on decks d (never executed)
                       Index Cond: ((user_id = cards.user_id) AND (id = cards.deck_id))
                       Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((InitPlan 2).col1 = user_id) OR ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))))
                       InitPlan 2
                         ->  Result (never executed)
 Planning Time: 0.240 ms
 Execution Time: 1.087 ms
(30 rows)

### Q7 card states: web/src/features/study/read-states.ts:24-32
                                                QUERY PLAN
-----------------------------------------------------------------------------------------------------------
 Limit (actual time=0.017..0.702 rows=1000 loops=1)
   Buffers: shared hit=999
   InitPlan 1
     ->  Result (actual time=0.003..0.003 rows=1 loops=1)
   ->  Result (actual time=0.016..0.638 rows=1000 loops=1)
         One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
         Buffers: shared hit=999
         ->  Index Scan using card_states_pkey on card_states (actual time=0.012..0.557 rows=1000 loops=1)
               Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
               Filter: (deleted_at IS NULL)
               Buffers: shared hit=999
 Planning:
   Buffers: shared hit=73
 Planning Time: 0.179 ms
 Execution Time: 0.748 ms
(15 rows)

### Q8 toggle a review: app/lib/sync/src/supabase_sync_server.dart:152-156, web/src/features/study/record-answer.ts:53-57
                                        QUERY PLAN
------------------------------------------------------------------------------------------
 Update on reviews (actual time=0.385..0.385 rows=0 loops=1)
   Buffers: shared hit=106
   InitPlan 1
     ->  Result (actual time=0.002..0.002 rows=1 loops=1)
   InitPlan 2
     ->  Result (actual time=0.003..0.003 rows=1 loops=1)
   ->  Index Scan using reviews_pkey on reviews (actual time=0.010..0.010 rows=1 loops=1)
         Index Cond: (id = '0000603d-d464-469f-a1bc-adc2f6ce66c4'::uuid)
         Filter: (((InitPlan 2).col1 = user_id) AND (updated_at < now()))
         Buffers: shared hit=4
 Planning:
   Buffers: shared hit=6
 Planning Time: 0.084 ms
 Trigger set_revision: time=0.249 calls=1
 Execution Time: 0.437 ms
(15 rows)

COMMIT
BEGIN
SET
SET
### Q9 preview a public deck as another user: app/lib/sharing/src/supabase_sharing_server.dart:62-69
                                                                                             QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=1.022..1.028 rows=50 loops=1)
   Buffers: shared hit=119
   InitPlan 1
     ->  Result (actual time=0.003..0.003 rows=1 loops=1)
   ->  Sort (actual time=1.022..1.024 rows=50 loops=1)
         Sort Key: cards.created_at, cards.id
         Sort Method: quicksort  Memory: 49kB
         Buffers: shared hit=119
         ->  Bitmap Heap Scan on cards (actual time=0.974..0.999 rows=94 loops=1)
               Recheck Cond: (deck_id = '0021c21d-85fe-45eb-9d6a-6a5fd2ccfb67'::uuid)
               Filter: ((deleted_at IS NULL) AND (((InitPlan 1).col1 = user_id) OR ((deleted_at IS NULL) AND (ANY ((user_id = (hashed SubPlan 5).col1) AND (deck_id = (hashed SubPlan 5).col2))))))
               Rows Removed by Filter: 6
               Heap Blocks: exact=4
               Buffers: shared hit=116
               ->  Bitmap Index Scan on cards_deck_id_created_at_id (actual time=0.009..0.009 rows=100 loops=1)
                     Index Cond: (deck_id = '0021c21d-85fe-45eb-9d6a-6a5fd2ccfb67'::uuid)
                     Buffers: shared hit=4
               SubPlan 5
                 ->  Bitmap Heap Scan on decks d (actual time=0.075..0.558 rows=1885 loops=1)
                       Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                       Heap Blocks: exact=101
                       Buffers: shared hit=108
                       InitPlan 4
                         ->  Result (never executed)
                       ->  Bitmap Index Scan on decks_public_published_at (actual time=0.064..0.064 rows=1885 loops=1)
                             Buffers: shared hit=7
 Planning Time: 0.169 ms
 Execution Time: 1.055 ms
(28 rows)

### Q10 list public decks, newest: list_public_decks body (app/lib/sharing/src/supabase_sharing_server.dart:34-45)
                                                                                                                    QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.360..6.414 rows=50 loops=1)
   Buffers: shared hit=14426
   InitPlan 7
     ->  Result (actual time=0.001..0.001 rows=1 loops=1)
   InitPlan 8
     ->  Result (never executed)
   InitPlan 9
     ->  Result (actual time=0.006..0.006 rows=1 loops=1)
   InitPlan 14
     ->  Result (actual time=0.002..0.002 rows=1 loops=1)
   ->  Result (actual time=0.360..6.408 rows=50 loops=1)
         Buffers: shared hit=14426
         ->  Incremental Sort (actual time=0.219..0.315 rows=50 loops=1)
               Sort Key: d.published_at DESC, d.id
               Presorted Key: d.published_at
               Full-sort Groups: 2  Sort Method: quicksort  Average Memory: 29kB  Peak Memory: 29kB
               Buffers: shared hit=372
               ->  Nested Loop Anti Join (actual time=0.049..0.286 rows=51 loops=1)
                     Join Filter: (b.blocked_id = d.user_id)
                     Rows Removed by Join Filter: 258
                     Buffers: shared hit=369
                     ->  Nested Loop (actual time=0.035..0.238 rows=52 loops=1)
                           Buffers: shared hit=366
                           ->  Index Scan using decks_public_published_at on decks d (actual time=0.008..0.031 rows=52 loops=1)
                                 Buffers: shared hit=54
                           ->  Memoize (actual time=0.004..0.004 rows=1 loops=52)
                                 Cache Key: d.user_id
                                 Cache Mode: logical
                                 Hits: 0  Misses: 52  Evictions: 0  Overflows: 0  Memory Usage: 8kB
                                 Buffers: shared hit=312
                                 ->  Index Scan using profiles_pkey on profiles p (actual time=0.003..0.003 rows=1 loops=52)
                                       Index Cond: (user_id = d.user_id)
                                       Filter: (((InitPlan 9).col1 = user_id) OR EXISTS(SubPlan 11))
                                       Buffers: shared hit=312
                                       SubPlan 11
                                         ->  Index Scan using decks_user_id_id_key on decks d_2 (actual time=0.002..0.002 rows=1 loops=52)
                                               Index Cond: (user_id = p.user_id)
                                               Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((InitPlan 10).col1 = user_id) OR ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))))
                                               Rows Removed by Filter: 0
                                               Buffers: shared hit=156
                                               InitPlan 10
                                                 ->  Result (actual time=0.002..0.002 rows=1 loops=1)
                     ->  Materialize (actual time=0.000..0.000 rows=5 loops=52)
                           Buffers: shared hit=3
                           ->  Result (actual time=0.010..0.011 rows=5 loops=1)
                                 One-Time Filter: ((InitPlan 14).col1 = (InitPlan 7).col1)
                                 Buffers: shared hit=3
                                 ->  Index Only Scan using user_blocks_pkey on user_blocks b (actual time=0.007..0.007 rows=5 loops=1)
                                       Index Cond: (blocker_id = (InitPlan 7).col1)
                                       Heap Fetches: 0
                                       Buffers: shared hit=3
         SubPlan 6
           ->  Aggregate (actual time=0.121..0.121 rows=1 loops=50)
                 Buffers: shared hit=14054
                 InitPlan 1
                   ->  Result (actual time=0.001..0.002 rows=1 loops=1)
                 ->  Bitmap Heap Scan on cards c (actual time=0.025..0.115 rows=90 loops=50)
                       Recheck Cond: ((deck_id = d.id) AND (user_id = d.user_id))
                       Filter: ((deleted_at IS NULL) AND (((InitPlan 1).col1 = user_id) OR ((deleted_at IS NULL) AND EXISTS(SubPlan 3))))
                       Rows Removed by Filter: 10
                       Heap Blocks: exact=185
                       Buffers: shared hit=14054
                       ->  BitmapAnd (actual time=0.019..0.019 rows=0 loops=50)
                             Buffers: shared hit=420
                             ->  Bitmap Index Scan on cards_deck_id_created_at_id (actual time=0.006..0.006 rows=100 loops=50)
                                   Index Cond: (deck_id = d.id)
                                   Buffers: shared hit=180
                             ->  Bitmap Index Scan on cards_user_id_id_key (actual time=0.012..0.012 rows=300 loops=50)
                                   Index Cond: (user_id = d.user_id)
                                   Buffers: shared hit=240
                       SubPlan 3
                         ->  Index Scan using decks_user_id_id_key on decks d_1 (actual time=0.001..0.001 rows=1 loops=4483)
                               Index Cond: ((user_id = c.user_id) AND (id = c.deck_id))
                               Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((InitPlan 2).col1 = user_id) OR ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))))
                               Buffers: shared hit=13449
                               InitPlan 2
                                 ->  Result (actual time=0.001..0.001 rows=1 loops=1)
 Planning:
   Buffers: shared hit=125
 Planning Time: 0.752 ms
 Execution Time: 6.514 ms
(81 rows)

### Q11 list public decks, most copied, searching 단어
                                                                                                                    QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=6.795..12.749 rows=50 loops=1)
   Buffers: shared hit=18145
   InitPlan 7
     ->  Result (actual time=0.001..0.001 rows=1 loops=1)
   InitPlan 8
     ->  Result (never executed)
   InitPlan 9
     ->  Result (actual time=0.005..0.006 rows=1 loops=1)
   InitPlan 14
     ->  Result (actual time=0.001..0.001 rows=1 loops=1)
   ->  Result (actual time=6.794..12.741 rows=50 loops=1)
         Buffers: shared hit=18145
         ->  Sort (actual time=6.634..6.645 rows=50 loops=1)
               Sort Key: d.import_count DESC NULLS LAST, d.published_at DESC, d.id
               Sort Method: top-N heapsort  Memory: 36kB
               Buffers: shared hit=4111
               ->  Nested Loop Anti Join (actual time=0.095..6.254 rows=1879 loops=1)
                     Join Filter: (b.blocked_id = d.user_id)
                     Rows Removed by Join Filter: 9416
                     Buffers: shared hit=4108
                     ->  Nested Loop (actual time=0.086..5.031 rows=1885 loops=1)
                           Buffers: shared hit=4105
                           ->  Bitmap Heap Scan on decks d (actual time=0.070..1.789 rows=1885 loops=1)
                                 Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
                                 Filter: ((strpos(lower(name), '단어'::text) > 0) OR (strpos(lower(COALESCE(description, ''::text)), '단어'::text) > 0))
                                 Heap Blocks: exact=101
                                 Buffers: shared hit=108
                                 ->  Bitmap Index Scan on decks_public_published_at (actual time=0.054..0.054 rows=1885 loops=1)
                                       Buffers: shared hit=7
                           ->  Memoize (actual time=0.002..0.002 rows=1 loops=1885)
                                 Cache Key: d.user_id
                                 Cache Mode: logical
                                 Hits: 1219  Misses: 666  Evictions: 0  Overflows: 0  Memory Usage: 92kB
                                 Buffers: shared hit=3997
                                 ->  Index Scan using profiles_pkey on profiles p (actual time=0.002..0.002 rows=1 loops=666)
                                       Index Cond: (user_id = d.user_id)
                                       Filter: (((InitPlan 9).col1 = user_id) OR EXISTS(SubPlan 11))
                                       Buffers: shared hit=3997
                                       SubPlan 11
                                         ->  Index Scan using decks_user_id_id_key on decks d_2 (actual time=0.001..0.001 rows=1 loops=666)
                                               Index Cond: (user_id = p.user_id)
                                               Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((InitPlan 10).col1 = user_id) OR ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))))
                                               Rows Removed by Filter: 0
                                               Buffers: shared hit=1999
                                               InitPlan 10
                                                 ->  Result (actual time=0.002..0.002 rows=1 loops=1)
                     ->  Materialize (actual time=0.000..0.000 rows=5 loops=1885)
                           Buffers: shared hit=3
                           ->  Result (actual time=0.006..0.007 rows=5 loops=1)
                                 One-Time Filter: ((InitPlan 14).col1 = (InitPlan 7).col1)
                                 Buffers: shared hit=3
                                 ->  Index Only Scan using user_blocks_pkey on user_blocks b (actual time=0.003..0.003 rows=5 loops=1)
                                       Index Cond: (blocker_id = (InitPlan 7).col1)
                                       Heap Fetches: 0
                                       Buffers: shared hit=3
         SubPlan 6
           ->  Aggregate (actual time=0.121..0.121 rows=1 loops=50)
                 Buffers: shared hit=14034
                 InitPlan 1
                   ->  Result (actual time=0.003..0.003 rows=1 loops=1)
                 ->  Bitmap Heap Scan on cards c (actual time=0.026..0.116 rows=89 loops=50)
                       Recheck Cond: ((deck_id = d.id) AND (user_id = d.user_id))
                       Filter: ((deleted_at IS NULL) AND (((InitPlan 1).col1 = user_id) OR ((deleted_at IS NULL) AND EXISTS(SubPlan 3))))
                       Rows Removed by Filter: 11
                       Heap Blocks: exact=183
                       Buffers: shared hit=14034
                       ->  BitmapAnd (actual time=0.021..0.021 rows=0 loops=50)
                             Buffers: shared hit=432
                             ->  Bitmap Index Scan on cards_deck_id_created_at_id (actual time=0.007..0.007 rows=100 loops=50)
                                   Index Cond: (deck_id = d.id)
                                   Buffers: shared hit=186
                             ->  Bitmap Index Scan on cards_user_id_id_key (actual time=0.013..0.013 rows=300 loops=50)
                                   Index Cond: (user_id = d.user_id)
                                   Buffers: shared hit=246
                       SubPlan 3
                         ->  Index Scan using decks_user_id_id_key on decks d_1 (actual time=0.001..0.001 rows=1 loops=4473)
                               Index Cond: ((user_id = c.user_id) AND (id = c.deck_id))
                               Filter: ((NOT hidden) AND (deleted_at IS NULL) AND (visibility = 'public'::text) AND (((InitPlan 2).col1 = user_id) OR ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))))
                               Buffers: shared hit=13419
                               InitPlan 2
                                 ->  Result (actual time=0.001..0.002 rows=1 loops=1)
 Planning:
   Buffers: shared hit=34
 Planning Time: 0.899 ms
 Execution Time: 12.865 ms
(85 rows)

COMMIT
### Q12 delete an account: the auth.users cascade (ADR 0026), as the admin API runs it
BEGIN
                                       QUERY PLAN
-----------------------------------------------------------------------------------------
 Delete on users (actual time=0.233..0.233 rows=0 loops=1)
   Buffers: shared hit=43
   ->  Index Scan using users_pkey on users (actual time=0.070..0.070 rows=1 loops=1)
         Index Cond: (id = '00000000-0000-4000-8000-000000000003'::uuid)
         Buffers: shared hit=3
 Planning:
   Buffers: shared hit=183
 Planning Time: 0.752 ms
 Trigger for constraint identities_user_id_fkey on users: time=0.347 calls=1
 Trigger for constraint sessions_user_id_fkey on users: time=0.394 calls=1
 Trigger for constraint mfa_factors_user_id_fkey on users: time=1.321 calls=1
 Trigger for constraint one_time_tokens_user_id_fkey on users: time=0.427 calls=1
 Trigger for constraint oauth_authorizations_user_id_fkey on users: time=0.210 calls=1
 Trigger for constraint oauth_consents_user_id_fkey on users: time=0.205 calls=1
 Trigger for constraint webauthn_credentials_user_id_fkey on users: time=0.175 calls=1
 Trigger for constraint webauthn_challenges_user_id_fkey on users: time=0.145 calls=1
 Trigger for constraint scim_users_user_id_fkey on users: time=0.239 calls=1
 Trigger for constraint mfa_recovery_code_sets_user_id_fkey on users: time=0.084 calls=1
 Trigger for constraint decks_user_id_fkey on users: time=0.068 calls=1
 Trigger for constraint cards_user_id_fkey on users: time=0.298 calls=1
 Trigger for constraint reviews_user_id_fkey on users: time=0.508 calls=1
 Trigger for constraint card_states_user_id_fkey on users: time=0.219 calls=1
 Trigger for constraint extraction_usage_user_id_fkey on users: time=0.311 calls=1
 Trigger for constraint profiles_user_id_fkey on users: time=0.040 calls=1
 Trigger for constraint deck_reports_reporter_id_fkey on users: time=0.174 calls=1
 Trigger for constraint user_blocks_blocker_id_fkey on users: time=0.118 calls=1
 Trigger for constraint user_blocks_blocked_id_fkey on users: time=0.088 calls=1
 Trigger for constraint deck_imports_user_id_fkey on users: time=0.098 calls=1
 Trigger for constraint cards_user_id_deck_id_fkey on decks: time=0.157 calls=3
 Trigger for constraint deck_reports_deck_id_fkey on decks: time=0.100 calls=3
 Trigger for constraint deck_imports_deck_id_fkey on decks: time=0.115 calls=3
 Trigger for constraint reviews_user_id_card_id_fkey on cards: time=1.520 calls=300
 Trigger for constraint card_states_user_id_card_id_fkey on cards: time=1.437 calls=300
 Execution Time: 9.106 ms
(34 rows)

ROLLBACK
### Q13 purge tombstones older than the horizon (proposed; cards)
BEGIN
                                              QUERY PLAN
------------------------------------------------------------------------------------------------------
 Delete on cards (actual time=0.516..0.516 rows=0 loops=1)
   Buffers: shared hit=1077
   ->  Index Scan using cards_tombstone_revision on cards (actual time=0.012..0.206 rows=469 loops=1)
         Index Cond: (revision <= 11017)
         Filter: (deleted_at IS NOT NULL)
         Buffers: shared hit=139
 Planning:
   Buffers: shared hit=3
 Planning Time: 0.061 ms
 Trigger for constraint reviews_user_id_card_id_fkey: time=7.027 calls=469
 Trigger for constraint card_states_user_id_card_id_fkey: time=3.419 calls=469
 Execution Time: 11.035 ms
(12 rows)

ROLLBACK
```

## Probe

```sql
\pset pager off
\timing on
\echo '### locale and text search configurations'
select datname, datcollate, datctype from pg_database where datname = 'postgres';
select cfgname from pg_ts_config order by 1;
\echo '### pg_trgm on Korean'
create extension if not exists pg_trgm with schema extensions;
select extensions.show_trgm('영단어 단어장') as korean, extensions.show_trgm('word list') as latin;
select extensions.similarity('영단어 단어장', '단어') as sim;
\echo '### pg_trgm index on the public listing search'
create index decks_public_search_trgm on public.decks using gin
  ((lower(name) || ' ' || lower(coalesce(description, ''))) extensions.gin_trgm_ops)
  where visibility = 'public' and not hidden and deleted_at is null;
analyze public.decks;
explain (analyze, buffers, costs off)
select id from public.decks
where visibility = 'public' and not hidden and deleted_at is null
  and (lower(name) || ' ' || lower(coalesce(description, ''))) like '%단어장%';
explain (analyze, buffers, costs off)
select id from public.decks
where visibility = 'public' and not hidden and deleted_at is null
  and (lower(name) || ' ' || lower(coalesce(description, ''))) like '%단어%';
drop index public.decks_public_search_trgm;

\echo '### v4 against v7 primary keys: 4 x 500,000 inserts in separate transactions'
create function pg_temp.uuid_v7() returns uuid language sql volatile as $$
  select encode(
    set_bit(set_bit(
      overlay(uuid_send(gen_random_uuid())
        placing substring(int8send((extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
        from 1 for 6),
      52, 1), 53, 1), 'hex')::uuid
$$;
select pg_temp.uuid_v7() as sample_v7, uuid_extract_version(pg_temp.uuid_v7()) as version;
create schema bench;
create table bench.k4 (id uuid primary key, user_id uuid not null, at timestamptz not null);
create table bench.k7 (id uuid primary key, user_id uuid not null, at timestamptz not null);
checkpoint;
select pg_current_wal_lsn() as lsn0 \gset
insert into bench.k4 select gen_random_uuid(), gen_random_uuid(), now() from generate_series(1, 500000);
checkpoint;
insert into bench.k4 select gen_random_uuid(), gen_random_uuid(), now() from generate_series(1, 500000);
checkpoint;
insert into bench.k4 select gen_random_uuid(), gen_random_uuid(), now() from generate_series(1, 500000);
checkpoint;
insert into bench.k4 select gen_random_uuid(), gen_random_uuid(), now() from generate_series(1, 500000);
select pg_current_wal_lsn() as lsn1 \gset
checkpoint;
select pg_current_wal_lsn() as lsn2 \gset
insert into bench.k7 select pg_temp.uuid_v7(), gen_random_uuid(), now() from generate_series(1, 500000);
checkpoint;
insert into bench.k7 select pg_temp.uuid_v7(), gen_random_uuid(), now() from generate_series(1, 500000);
checkpoint;
insert into bench.k7 select pg_temp.uuid_v7(), gen_random_uuid(), now() from generate_series(1, 500000);
checkpoint;
insert into bench.k7 select pg_temp.uuid_v7(), gen_random_uuid(), now() from generate_series(1, 500000);
select pg_current_wal_lsn() as lsn3 \gset
select pg_size_pretty(pg_wal_lsn_diff(:'lsn1', :'lsn0')) as wal_v4,
       pg_size_pretty(pg_wal_lsn_diff(:'lsn3', :'lsn2')) as wal_v7,
       pg_size_pretty(pg_relation_size('bench.k4_pkey')) as pkey_v4,
       pg_size_pretty(pg_relation_size('bench.k7_pkey')) as pkey_v7;
```

Its output:

```text
Pager usage is off.
Timing is on.
### locale and text search configurations
 datname  | datcollate  |  datctype
----------+-------------+-------------
 postgres | en_US.UTF-8 | en_US.UTF-8
(1 row)
Time: 13.027 ms
  cfgname
------------
 arabic
 armenian
 basque
 catalan
 danish
 dutch
 english
 finnish
 french
 german
 greek
 hindi
 hungarian
 indonesian
 irish
 italian
 lithuanian
 nepali
 norwegian
 portuguese
 romanian
 russian
 serbian
 simple
 spanish
 swedish
 tamil
 turkish
 yiddish
(29 rows)
Time: 1.949 ms
### pg_trgm on Korean
CREATE EXTENSION
Time: 378.287 ms
                                korean                                |                         latin
----------------------------------------------------------------------+-------------------------------------------------------
 {89k,0x5d0adc,0x60557c,0x6f822d,0x869092,0xeb5b5c,0xf08d96,0xf5a6a2} | {"  l","  w"," li"," wo",ist,lis,ord,"rd ","st ",wor}
(1 row)
Time: 13.654 ms
  sim
-------
 0.375
(1 row)
Time: 4.276 ms
### pg_trgm index on the public listing search
CREATE INDEX
Time: 60.805 ms
ANALYZE
Time: 68.263 ms
                                                                                         QUERY PLAN
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on decks (actual time=1.325..7.267 rows=1893 loops=1)
   Recheck Cond: ((((lower(name) || ' '::text) || lower(COALESCE(description, ''::text))) ~~ '%단어장%'::text) AND (visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
   Heap Blocks: exact=115
   Buffers: shared hit=118
   ->  Bitmap Index Scan on decks_public_search_trgm (actual time=0.722..0.722 rows=1893 loops=1)
         Index Cond: (((lower(name) || ' '::text) || lower(COALESCE(description, ''::text))) ~~ '%단어장%'::text)
         Buffers: shared hit=3
 Planning:
   Buffers: shared hit=43
 Planning Time: 0.677 ms
 Execution Time: 7.535 ms
(11 rows)
Time: 9.407 ms
                                              QUERY PLAN
------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on decks (actual time=1.055..6.696 rows=1893 loops=1)
   Recheck Cond: ((visibility = 'public'::text) AND (NOT hidden) AND (deleted_at IS NULL))
   Filter: (((lower(name) || ' '::text) || lower(COALESCE(description, ''::text))) ~~ '%단어%'::text)
   Heap Blocks: exact=115
   Buffers: shared hit=124
   ->  Bitmap Index Scan on decks_public_published_at (actual time=1.013..1.014 rows=1893 loops=1)
         Buffers: shared hit=9
 Planning:
   Buffers: shared hit=1
 Planning Time: 0.171 ms
 Execution Time: 7.187 ms
(11 rows)
Time: 8.711 ms
DROP INDEX
Time: 10.002 ms
### v4 against v7 primary keys: 4 x 500,000 inserts in separate transactions
CREATE FUNCTION
Time: 13.768 ms
              sample_v7               | version
--------------------------------------+---------
 01a1435e-5ba1-7a91-b96f-bfbaaecc21cb |       7
(1 row)
Time: 26.052 ms
CREATE SCHEMA
Time: 3.555 ms
CREATE TABLE
Time: 46.903 ms
CREATE TABLE
Time: 9.697 ms
Time: 2033.605 ms (00:02.034)
Time: 4.473 ms
INSERT 0 500000
Time: 14242.466 ms (00:14.242)
Time: 1410.221 ms (00:01.410)
INSERT 0 500000
Time: 13403.900 ms (00:13.404)
Time: 1218.345 ms (00:01.218)
INSERT 0 500000
Time: 12203.194 ms (00:12.203)
Time: 1534.489 ms (00:01.534)
INSERT 0 500000
Time: 15661.531 ms (00:15.662)
Time: 6.914 ms
Time: 1352.429 ms (00:01.352)
Time: 2.932 ms
INSERT 0 500000
Time: 8780.589 ms (00:08.781)
Time: 343.337 ms
INSERT 0 500000
Time: 6765.227 ms (00:06.765)
Time: 343.666 ms
INSERT 0 500000
Time: 7039.032 ms (00:07.039)
Time: 475.442 ms
INSERT 0 500000
Time: 8245.843 ms (00:08.246)
Time: 4.789 ms
 wal_v4 | wal_v7 | pkey_v4 | pkey_v7
--------+--------+---------+---------
 438 MB | 329 MB | 77 MB   | 60 MB
(1 row)
Time: 37.939 ms
```

## Phone plans

Schema, seed, queries and the proposed indexes:

```sql
-- Schema v5 as drift creates it (app/lib/shared/database.dart; datetimes as unix seconds).
PRAGMA foreign_keys = ON;
CREATE TABLE decks (id TEXT NOT NULL, name TEXT NOT NULL,
  visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'public')),
  published_at INTEGER NULL, description TEXT NULL, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, deleted_at INTEGER NULL,
  dirty INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), PRIMARY KEY (id));
CREATE TABLE cards (id TEXT NOT NULL, deck_id TEXT NOT NULL REFERENCES decks (id) ON DELETE CASCADE,
  front TEXT NOT NULL, back TEXT NOT NULL, card_key TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('manual', 'import', 'shared')), origin_deck_id TEXT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER NULL,
  dirty INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), PRIMARY KEY (id));
CREATE TABLE reviews (id TEXT NOT NULL, card_id TEXT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
  rating TEXT NOT NULL CHECK (rating IN ('again', 'good')), reviewed_at INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL, fuzz_factor REAL NULL CHECK (fuzz_factor >= 0 AND fuzz_factor < 1),
  updated_at INTEGER NOT NULL, deleted_at INTEGER NULL,
  dirty INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), PRIMARY KEY (id));
CREATE TABLE card_states (card_id TEXT NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
  stability REAL NOT NULL, difficulty REAL NOT NULL, last_review INTEGER NOT NULL, due INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, deleted_at INTEGER NULL,
  dirty INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), PRIMARY KEY (card_id));
CREATE INDEX cards_deck_id_card_key ON cards (deck_id, card_key);
```

```sql
-- One heavy user: 20 decks x 500 cards, 10 reviews per card, a state per card; 10% of cards
-- tombstoned; 20 rows of each table unsynced.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 100000) SELECT 1;
CREATE TEMP TABLE n AS WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 100000) SELECT i FROM n;
BEGIN;
INSERT INTO decks SELECT printf('d%04d', i), 'deck ' || i, 'private', NULL, NULL, 1700000000, 1700000000, NULL, 0 FROM n WHERE i <= 20;
INSERT INTO cards SELECT printf('c%06d', i), printf('d%04d', 1 + (i - 1) / 500), '[]', '[]', 'word ' || i, 'manual', NULL,
  1700000000 + i * 60, 1700000000 + i * 60, CASE WHEN i % 10 = 0 THEN 1750000000 END, 0 FROM n WHERE i <= 10000;
INSERT INTO reviews SELECT printf('r%07d', i), printf('c%06d', 1 + (i - 1) % 10000), 'good', 1700000000 + abs(random() % 31536000),
  5000, 0.5, 1700000000, NULL, 0 FROM n;
INSERT INTO card_states SELECT printf('c%06d', i), 10, 5, 1760000000, 1760000000 + abs(random() % 5000000), 1760000000, NULL, 0 FROM n WHERE i <= 10000;
UPDATE decks SET dirty = 1 WHERE id IN (SELECT id FROM decks LIMIT 2);
UPDATE cards SET dirty = 1 WHERE rowid % 500 = 0;
UPDATE reviews SET dirty = 1 WHERE rowid % 5000 = 0;
UPDATE card_states SET dirty = 1 WHERE rowid % 500 = 0;
COMMIT;
ANALYZE;
```

```sql
PRAGMA foreign_keys = ON;
.eqp on
.timer on
.print '### P1 deck list: app/lib/deck/src/deck_repository.dart:44-46'
SELECT * FROM decks WHERE deleted_at IS NULL ORDER BY name;
.print '### P2 a deck cards, oldest first: deck_repository.dart:166-170 and 178-182'
SELECT * FROM cards WHERE deck_id = 'd0007' AND deleted_at IS NULL ORDER BY created_at;
.print '### P3 card count of one deck: deck_repository.dart:135-139'
SELECT COUNT(id) FROM cards WHERE deck_id = 'd0007' AND deleted_at IS NULL;
.print '### P4 card counts per deck: deck_repository.dart:148-151'
SELECT deck_id, COUNT(id) FROM cards WHERE deleted_at IS NULL GROUP BY deck_id;
.print '### P5 duplicate check: deck_repository.dart:370-380'
SELECT * FROM cards WHERE deck_id = 'd0007' AND card_key = 'word 3001' AND deleted_at IS NULL LIMIT 1;
.print '### P6 pace: app/lib/study/src/study_repository.dart:90-94'
SELECT duration_ms FROM reviews WHERE deleted_at IS NULL ORDER BY reviewed_at DESC LIMIT 200;
.print '### P7 one card reviews for the fold: app/lib/sync/src/sync_store.dart:204-208'
SELECT * FROM reviews WHERE card_id = 'c003001' AND deleted_at IS NULL;
.print '### P8 reviews of one study day (#87, #89, #90)'
SELECT card_id, rating, reviewed_at FROM reviews WHERE deleted_at IS NULL AND reviewed_at >= 1720000000 AND reviewed_at < 1720086400;
.print '### P9 states of a selection: study_repository.dart:25-30'
SELECT * FROM card_states WHERE card_id IN ('c000001', 'c000002', 'c000003') AND deleted_at IS NULL;
.print '### P10 unsynced rows: sync_store.dart:241-252 (drift writes WHERE "dirty")'
SELECT * FROM reviews WHERE "dirty";
.print '### P11 any unsynced row: sync_store.dart:83-86'
SELECT 1 FROM reviews WHERE dirty = 1 LIMIT 1;
.print '### P12 delete 100 cards (the purge, and the cascade to reviews)'
.eqp off
BEGIN; DELETE FROM cards WHERE id IN (SELECT id FROM cards WHERE deleted_at IS NOT NULL LIMIT 100); ROLLBACK;
```

```sql
-- The proposed phone indexes.
DROP INDEX cards_deck_id_card_key;
CREATE INDEX cards_deck_id_card_key ON cards (deck_id, card_key) WHERE deleted_at IS NULL;
CREATE INDEX cards_deck_id_created_at ON cards (deck_id, created_at);
CREATE INDEX reviews_card_id_reviewed_at ON reviews (card_id, reviewed_at);
CREATE INDEX reviews_live_reviewed_at ON reviews (reviewed_at) WHERE deleted_at IS NULL;
CREATE INDEX decks_unsynced ON decks (id) WHERE "dirty";
CREATE INDEX cards_unsynced ON cards (id) WHERE "dirty";
CREATE INDEX reviews_unsynced ON reviews (id) WHERE "dirty";
CREATE INDEX card_states_unsynced ON card_states (card_id) WHERE "dirty";
ANALYZE;
```

Before:

```text
### P1 deck list: app/lib/deck/src/deck_repository.dart:44-46
QUERY PLAN
|--SCAN decks
`--USE TEMP B-TREE FOR ORDER BY
Run Time: real 0.000 user 0.000280 sys 0.000111
### P2 a deck cards, oldest first: deck_repository.dart:166-170 and 178-182
QUERY PLAN
|--SEARCH cards USING INDEX cards_deck_id_card_key (deck_id=?)
`--USE TEMP B-TREE FOR ORDER BY
Run Time: real 0.001 user 0.001007 sys 0.000075
### P3 card count of one deck: deck_repository.dart:135-139
QUERY PLAN
`--SEARCH cards USING INDEX cards_deck_id_card_key (deck_id=?)
Run Time: real 0.000 user 0.000116 sys 0.000019
### P4 card counts per deck: deck_repository.dart:148-151
QUERY PLAN
`--SCAN cards USING INDEX cards_deck_id_card_key
Run Time: real 0.003 user 0.001980 sys 0.000383
### P5 duplicate check: deck_repository.dart:370-380
QUERY PLAN
`--SEARCH cards USING INDEX cards_deck_id_card_key (deck_id=? AND card_key=?)
Run Time: real 0.000 user 0.000096 sys 0.000029
### P6 pace: app/lib/study/src/study_repository.dart:90-94
QUERY PLAN
|--SCAN reviews
`--USE TEMP B-TREE FOR ORDER BY
Run Time: real 0.020 user 0.012514 sys 0.004146
### P7 one card reviews for the fold: app/lib/sync/src/sync_store.dart:204-208
QUERY PLAN
`--SCAN reviews
Run Time: real 0.018 user 0.008019 sys 0.004176
### P8 reviews of one study day (#87, #89, #90)
QUERY PLAN
`--SCAN reviews
Run Time: real 0.015 user 0.010420 sys 0.002668
### P9 states of a selection: study_repository.dart:25-30
QUERY PLAN
`--SEARCH card_states USING INDEX sqlite_autoindex_card_states_1 (card_id=?)
Run Time: real 0.000 user 0.000115 sys 0.000056
### P10 unsynced rows: sync_store.dart:241-252 (drift writes WHERE "dirty")
QUERY PLAN
`--SCAN reviews
Run Time: real 0.008 user 0.007577 sys 0.000167
### P11 any unsynced row: sync_store.dart:83-86
QUERY PLAN
`--SCAN reviews
Run Time: real 0.001 user 0.000502 sys 0.000057
### P12 delete 100 cards (the purge, and the cascade to reviews)
Run Time: real 1.907 user 1.718393 sys 0.041857
```

After:

```text
### P1 deck list: app/lib/deck/src/deck_repository.dart:44-46
QUERY PLAN
|--SCAN decks
`--USE TEMP B-TREE FOR ORDER BY
Run Time: real 0.000 user 0.000280 sys 0.000094
### P2 a deck cards, oldest first: deck_repository.dart:166-170 and 178-182
QUERY PLAN
`--SEARCH cards USING INDEX cards_deck_id_created_at (deck_id=?)
Run Time: real 0.001 user 0.000835 sys 0.000058
### P3 card count of one deck: deck_repository.dart:135-139
QUERY PLAN
`--SEARCH cards USING INDEX cards_deck_id_card_key (deck_id=?)
Run Time: real 0.000 user 0.000099 sys 0.000022
### P4 card counts per deck: deck_repository.dart:148-151
QUERY PLAN
`--SCAN cards USING INDEX cards_deck_id_card_key
Run Time: real 0.002 user 0.001807 sys 0.000320
### P5 duplicate check: deck_repository.dart:370-380
QUERY PLAN
`--SEARCH cards USING INDEX cards_deck_id_card_key (deck_id=? AND card_key=?)
Run Time: real 0.000 user 0.000044 sys 0.000012
### P6 pace: app/lib/study/src/study_repository.dart:90-94
QUERY PLAN
`--SCAN reviews USING INDEX reviews_live_reviewed_at
Run Time: real 0.001 user 0.000413 sys 0.000405
### P7 one card reviews for the fold: app/lib/sync/src/sync_store.dart:204-208
QUERY PLAN
`--SEARCH reviews USING INDEX reviews_card_id_reviewed_at (card_id=?)
Run Time: real 0.000 user 0.000070 sys 0.000035
### P8 reviews of one study day (#87, #89, #90)
QUERY PLAN
`--SEARCH reviews USING INDEX reviews_live_reviewed_at (reviewed_at>? AND reviewed_at<?)
Run Time: real 0.001 user 0.000520 sys 0.000358
### P9 states of a selection: study_repository.dart:25-30
QUERY PLAN
`--SEARCH card_states USING INDEX sqlite_autoindex_card_states_1 (card_id=?)
Run Time: real 0.000 user 0.000068 sys 0.000033
### P10 unsynced rows: sync_store.dart:241-252 (drift writes WHERE "dirty")
QUERY PLAN
`--SCAN reviews USING INDEX reviews_unsynced
Run Time: real 0.001 user 0.000093 sys 0.000040
### P11 any unsynced row: sync_store.dart:83-86
QUERY PLAN
`--SCAN reviews
Run Time: real 0.000 user 0.000408 sys 0.000122
### P12 delete 100 cards (the purge, and the cascade to reviews)
Run Time: real 0.026 user 0.007590 sys 0.015894
```

## Queries #95 added

Read at `cf494ca`. Each server run is a fresh stack seeded by the script above, with the warm second run kept. The first run took the queries before and after the target DDL. The second run took the streak function's `max()` form after it, since a first `exists` form, kept in the first run, read every row once. On the phone, `seed2.sql` adds today's answers to the same file: 20 cards answered for the first time and 200 answers to older cards. The streak probe ran after the proposed indexes.

```sql
-- The queries #95 added (main at cf494ca), run as the heavy user under row-level security.
-- The study day starts at 04:00 in Asia/Seoul, as web/src/features/study/queue.ts computes it.
\pset pager off
select ((date_trunc('day', (now() at time zone 'Asia/Seoul') - interval '4 hours') + interval '4 hours')
  at time zone 'Asia/Seoul') as day_start \gset
select '{' || array_to_string(array(
  select distinct card_id::text from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
    and reviewed_at >= :'day_start' order by 1 limit 100), ',') || '}' as today_cards \gset
select count(*) as reviews_before_today from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
    and reviewed_at < :'day_start';

begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-000000000000","role":"authenticated"}';
set local statement_timeout = '120s';

\echo '### Q14 today''s reviews, first page and count: web/src/features/study/read-today.ts:55-61'
explain (analyze, buffers, costs off, summary on)
select id, card_id, rating, reviewed_at, duration_ms from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  and reviewed_at >= :'day_start' order by id limit 1000 offset 0;
explain (analyze, buffers, costs off, summary on)
select count(*) from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  and reviewed_at >= :'day_start';

\echo '### Q15 earlier reviews of 100 of today''s cards, first page: read-today.ts:80-91'
explain (analyze, buffers, costs off, summary on)
select id, card_id from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  and reviewed_at < :'day_start' and card_id = any (:'today_cards')
  order by id limit 1000 offset 0;

\echo '### Q16 the streak, one page of 1,000 earlier answers newest first: read-today.ts:121-129'
explain (analyze, buffers, costs off, summary on)
select reviewed_at from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  and reviewed_at < :'day_start' order by reviewed_at desc limit 1000 offset 0;
\echo '### Q16 page 50 of the same paging'
explain (analyze, buffers, costs off, summary on)
select reviewed_at from public.reviews
  where user_id = '00000000-0000-4000-8000-000000000000' and deleted_at is null
  and reviewed_at < :'day_start' order by reviewed_at desc limit 1000 offset 49000;

\echo '### Q17 proposed: the streak in one statement, one index probe per study day (Asia/Seoul)'
explain (analyze, buffers, costs off, summary on)
with recursive days(day_start, streak) as (
  select ((:'day_start'::timestamptz at time zone 'Asia/Seoul') - interval '1 day') at time zone 'Asia/Seoul', 0
  union all
  select ((d.day_start at time zone 'Asia/Seoul') - interval '1 day') at time zone 'Asia/Seoul', d.streak + 1
  from days d
  where exists (
    select 1 from public.reviews r
    where r.user_id = (select auth.uid()) and r.deleted_at is null
      and r.reviewed_at >= d.day_start
      and r.reviewed_at < ((d.day_start at time zone 'Asia/Seoul') + interval '1 day') at time zone 'Asia/Seoul')
)
select max(streak) from days;
with recursive days(day_start, streak) as (
  select ((:'day_start'::timestamptz at time zone 'Asia/Seoul') - interval '1 day') at time zone 'Asia/Seoul', 0
  union all
  select ((d.day_start at time zone 'Asia/Seoul') - interval '1 day') at time zone 'Asia/Seoul', d.streak + 1
  from days d
  where exists (
    select 1 from public.reviews r
    where r.user_id = (select auth.uid()) and r.deleted_at is null
      and r.reviewed_at >= d.day_start
      and r.reviewed_at < ((d.day_start at time zone 'Asia/Seoul') + interval '1 day') at time zone 'Asia/Seoul')
)
select max(streak) as streak_before from days;
commit;
```

Before:

```text
 reviews_before_today
----------------------
                99837
(1 row)

BEGIN
SET
SET
SET
### Q14 today's reviews, first page and count: web/src/features/study/read-today.ts:55-61
                                                         QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=75.987..76.066 rows=163 loops=1)
   Buffers: shared hit=2623
   InitPlan 1
     ->  Result (actual time=0.106..0.107 rows=1 loops=1)
   ->  Sort (actual time=75.985..76.037 rows=163 loops=1)
         Sort Key: reviews.id
         Sort Method: quicksort  Memory: 46kB
         Buffers: shared hit=2623
         ->  Result (actual time=12.969..74.930 rows=163 loops=1)
               One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=2623
               ->  Bitmap Heap Scan on reviews (actual time=12.858..74.716 rows=163 loops=1)
                     Recheck Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                     Filter: ((deleted_at IS NULL) AND (reviewed_at >= '2026-10-15 19:00:00+00'::timestamp with time zone))
                     Rows Removed by Filter: 99837
                     Heap Blocks: exact=2128
                     Buffers: shared hit=2623
                     ->  Bitmap Index Scan on reviews_user_id_revision (actual time=12.003..12.008 rows=100000 loops=1)
                           Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                           Buffers: shared hit=495
 Planning:
   Buffers: shared hit=58
 Planning Time: 0.840 ms
 Execution Time: 76.363 ms
(24 rows)

                                                      QUERY PLAN
----------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=88.898..88.901 rows=1 loops=1)
   Buffers: shared hit=2623
   InitPlan 1
     ->  Result (actual time=0.032..0.033 rows=1 loops=1)
   ->  Result (actual time=9.002..88.685 rows=163 loops=1)
         One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
         Buffers: shared hit=2623
         ->  Bitmap Heap Scan on reviews (actual time=8.963..88.543 rows=163 loops=1)
               Recheck Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
               Filter: ((deleted_at IS NULL) AND (reviewed_at >= '2026-10-15 19:00:00+00'::timestamp with time zone))
               Rows Removed by Filter: 99837
               Heap Blocks: exact=2128
               Buffers: shared hit=2623
               ->  Bitmap Index Scan on reviews_user_id_revision (actual time=8.313..8.313 rows=100000 loops=1)
                     Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                     Buffers: shared hit=495
 Planning Time: 0.323 ms
 Execution Time: 89.928 ms
(18 rows)

### Q15 earlier reviews of 100 of today's cards, first page: read-today.ts:80-91
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=5.908..6.126 rows=898 loops=1)
   Buffers: shared hit=323
   InitPlan 1
     ->  Result (actual time=0.025..0.026 rows=1 loops=1)
   ->  Sort (actual time=5.906..5.994 rows=898 loops=1)
         Sort Key: reviews.id
         Sort Method: quicksort  Memory: 144kB
         Buffers: shared hit=323
         ->  Result (actual time=0.140..3.014 rows=898 loops=1)
               One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=323
               ->  Index Scan using reviews_user_id_card_id on reviews (actual time=0.110..2.825 rows=898 loops=1)
                     Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (card_id = ANY ('{00c8e1a9-8bd2-4cd9-bc73-3ec8a11d0a9c,0168485d-23a1-43a3-bb54-5dbef046e13f,0600baf2-0600-40fd-b745-e46a83c04f7f,061276d3-29d8-422a-8010-2d87088ed32a,061298ff-8613-4ef4-a0ad-d32ed8b86561,06ac6f3f-2123-4c91-be40-9ce6b6dc7efa,087001ad-926e-4e19-94d6-94e874744490,0a6e34c8-a1a4-4912-84e2-494f7b4cfbec,0aa42dec-b7e2-4c21-a502-1e1ed624ef67,0cc884d6-ea3c-4979-a0d7-328be4445e9d,0eb31f7e-b27e-4894-b6bc-241a407291e7,0f003a32-78ca-4c94-9f2c-efed764395f3,13c85d8c-bac2-4a88-a4e2-dd3602decb7b,15e82225-883a-4681-8ef3-e318674c05b3,167746fb-a43c-4ba0-b349-a1f3e47012a7,19597622-5603-4132-822e-6a6c9db508d5,1cac77e9-b368-4521-8b66-7819f46d05f4,1e047c5d-5b7d-4054-aebe-c20cc63a7389,1e5cea76-aafd-42d0-92e9-6304fc1624ea,1f119511-ba1f-402d-9150-6a97e3d852d2,203fc780-9459-4bee-bc13-1febb6745dda,2108c132-8438-4672-a577-97a906da44f6,226db278-73f7-472a-843e-665b30cef600,25451406-113a-4a96-adb5-7c156754fdd8,29ca3c7e-fb80-423e-bedb-f45f99165e87,2a039fb1-e49f-4ba9-a395-cba1fa3aeb38,2eda12bd-7ef1-4f9a-b0be-f7d2183b1bb0,2f38cf3e-713d-4a93-afc8-896b8f32bc06,2f6c6e06-a190-4b9b-b3d4-bd5415bbbaf1,2fad9e15-f012-4670-969e-c2d7117cde9a,30ab9014-9cb8-45cc-85cd-1063a3a69ef8,3151ff3e-8d72-44c5-865c-ea1f9347ebae,31b1b3ab-b8e1-43d3-9754-a8868f261435,324d0fda-0737-45c6-839d-d0503b17b66a,33bbec97-e80c-4fe2-a2af-c7efcaee5260,34191183-e997-4b56-9f95-f70fac29ee11,341ebe7e-0737-4f19-a844-999cf093c758,37599863-0442-465b-9166-39ebe2b95caf,38b06130-0733-402f-b695-93e64eeffc46,39657982-0118-440b-82f8-e1ce73c78616,3a9556cb-ca8f-455b-bb4b-0eb36b4cc0c4,3c9080f7-21cb-4f57-8ce7-5b64009b6029,40dc6d32-bde5-4e95-9644-ae2c59328b01,420a21ce-8b55-475b-b721-46b9f558e3d8,42827713-91d2-4f61-849b-7be34e87f1e0,4450b20f-48ec-4021-b985-caf427da52c9,445547f7-95bc-4a66-a5cd-673b25f35986,479cc03b-340b-438f-bb9f-aded788b9035,47c0b52f-9a94-48c3-86a9-7c6a0a2d3372,47ceb136-f16b-45d8-8156-d9bc7b63bf06,499ea3b6-9590-4ea7-a407-cc6c6301b6e8,4af3f810-0f31-4a85-9af1-280097cfe370,4e60b3de-79f6-4134-a64d-239186cd5d71,51285f9b-c471-4059-959e-29590414cb2a,56e8bf31-3171-4689-8d48-167c043746c3,5758a50d-9b5a-4992-8860-24ed757654e4,5c907086-df7d-4e26-89ff-eb5b481ccfb6,6210a3a0-6105-4d72-9550-187d52e64cda,621b7e9d-a3ae-4b6a-a7c4-20f596409a2b,6249365f-7df1-48e0-88c2-a0f5a54b5f0d,6408f563-a09a-4723-a2a5-b4ca711a1179,648c7144-26ad-493e-900c-6ec7844a252e,65a73047-4f10-4ee2-8592-7b52964206cb,6623677a-fe65-431c-b37a-033f2ca25128,665cbcb2-ef60-4635-aecc-414eb563a409,67696c4b-f0b6-4436-8d32-9af6408f33f1,676ceb5d-d524-4cd1-b404-3c0c7cb5c732,6b3792dd-ac2d-4735-8020-0f600ec1f34d,6d833871-065b-4cf4-9e19-44d77fc49b73,6e1b916d-10e3-47c4-b3ea-ae2d63edda1d,6ff8b98f-301d-4aeb-844e-9e9981ae16a9,7044bc60-8165-4346-8156-762ffd780362,72041338-7aeb-49b6-951e-d4e210668e27,73784f9e-b062-4aca-9f1e-8d7fd50d0dbe,7569a345-a5ea-43d7-96b6-dee69be0e197,77b2787f-69a4-4be0-9b72-625aaf5c20bb,79231011-2a7e-4f70-8d25-3b1e1b19c155,7bad87af-dc09-4d98-a9bd-9b81ccd26320,7c5e72d0-9189-47c2-a223-e991ca51a019,7cfdc736-23d6-479e-aa13-3f853bf50a07,7dd00d72-a5b5-4eaa-9f45-fa46aaffaf2b,7fc827a0-6f43-43ef-94eb-2e0f74b95a13,804034cc-34ec-44b5-9b3b-40eaea3990df,8330483b-d20e-4042-81ac-6a5d9bf88fe1,83c37e7f-2929-4574-9994-d0d0e9f49f07,84170cf0-a15e-4ec7-8601-bd052b2458a4,860877fb-9b9b-4054-b7f2-02ad3dafcc51,870d4275-bd84-4b59-ac8d-303901019aa7,87d5a216-ebd8-4dc6-b838-510febcd5db2,880b160b-6603-44d7-8c10-0d8a2fcbdaaf,88d7fa26-dc64-43a2-a076-6421415b4ad1,8c94ece8-71fd-4e5b-bd16-5f53d168d8b6,8d6cbc30-002f-4830-808e-74e2bcdb51d6,8df99953-5302-45f2-b3b9-51cab27f60a1,8eeabe9b-4527-42ac-9bbf-69df836e7cbd,90a5f550-25d3-4381-be7b-88b922f40977,93127924-5108-47f6-b203-e21a016fd0bb,9571da1d-01d7-4f61-82d5-47c3582f8b5a,9655c488-654c-4d79-bc5d-609f8aac2419,9737be38-6c11-49d8-b568-434d3b4a917d}'::text[])))
                     Filter: ((deleted_at IS NULL) AND (reviewed_at < '2026-10-15 19:00:00+00'::timestamp with time zone))
                     Rows Removed by Filter: 102
                     Buffers: shared hit=323
 Planning:
   Buffers: shared hit=3
 Planning Time: 1.602 ms
 Execution Time: 6.332 ms
(20 rows)

### Q16 the streak, one page of 1,000 earlier answers newest first: read-today.ts:121-129
                                                        QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=140.099..140.358 rows=1000 loops=1)
   Buffers: shared hit=2626
   InitPlan 1
     ->  Result (actual time=0.019..0.020 rows=1 loops=1)
   ->  Sort (actual time=140.097..140.199 rows=1000 loops=1)
         Sort Key: reviews.reviewed_at DESC
         Sort Method: top-N heapsort  Memory: 49kB
         Buffers: shared hit=2626
         ->  Result (actual time=10.463..107.824 rows=99837 loops=1)
               One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=2623
               ->  Bitmap Heap Scan on reviews (actual time=10.439..77.899 rows=99837 loops=1)
                     Recheck Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                     Filter: ((deleted_at IS NULL) AND (reviewed_at < '2026-10-15 19:00:00+00'::timestamp with time zone))
                     Rows Removed by Filter: 163
                     Heap Blocks: exact=2128
                     Buffers: shared hit=2623
                     ->  Bitmap Index Scan on reviews_user_id_revision (actual time=10.037..10.037 rows=100000 loops=1)
                           Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                           Buffers: shared hit=495
 Planning:
   Buffers: shared hit=11
 Planning Time: 1.135 ms
 Execution Time: 140.616 ms
(24 rows)

### Q16 page 50 of the same paging
                                                        QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=117.347..117.618 rows=1000 loops=1)
   Buffers: shared hit=2623
   InitPlan 1
     ->  Result (actual time=0.028..0.029 rows=1 loops=1)
   ->  Sort (actual time=107.986..112.942 rows=50000 loops=1)
         Sort Key: reviews.reviewed_at DESC
         Sort Method: quicksort  Memory: 3073kB
         Buffers: shared hit=2623
         ->  Result (actual time=8.174..67.761 rows=99837 loops=1)
               One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=2623
               ->  Bitmap Heap Scan on reviews (actual time=8.142..47.947 rows=99837 loops=1)
                     Recheck Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                     Filter: ((deleted_at IS NULL) AND (reviewed_at < '2026-10-15 19:00:00+00'::timestamp with time zone))
                     Rows Removed by Filter: 163
                     Heap Blocks: exact=2128
                     Buffers: shared hit=2623
                     ->  Bitmap Index Scan on reviews_user_id_revision (actual time=7.704..7.705 rows=100000 loops=1)
                           Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                           Buffers: shared hit=495
 Planning Time: 0.227 ms
 Execution Time: 118.106 ms
(22 rows)

### Q17 proposed: the streak in one statement, one index probe per study day (Asia/Seoul)
                                                                                           QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=369.542..369.551 rows=1 loops=1)
   Buffers: shared hit=2623, temp written=219
   CTE days
     ->  Recursive Union (actual time=0.002..369.238 rows=366 loops=1)
           Buffers: shared hit=2623, temp written=219
           ->  Result (actual time=0.001..0.002 rows=1 loops=1)
           ->  Result (actual time=1.006..1.006 rows=1 loops=366)
                 One-Time Filter: ((InitPlan 2).col1 = (InitPlan 1).col1)
                 Buffers: shared hit=2623, temp written=219
                 InitPlan 1
                   ->  Result (actual time=0.006..0.006 rows=1 loops=1)
                 InitPlan 2
                   ->  Result (actual time=0.022..0.023 rows=1 loops=1)
                 ->  Nested Loop Semi Join (actual time=1.004..1.004 rows=1 loops=366)
                       Join Filter: ((r.reviewed_at >= d.day_start) AND (r.reviewed_at < (((d.day_start AT TIME ZONE 'Asia/Seoul'::text) + '1 day'::interval) AT TIME ZONE 'Asia/Seoul'::text)))
                       Rows Removed by Join Filter: 621
                       Buffers: shared hit=2623, temp written=219
                       ->  WorkTable Scan on days d (actual time=0.000..0.000 rows=1 loops=366)
                       ->  Materialize (actual time=0.000..0.409 rows=622 loops=366)
                             Buffers: shared hit=2623, temp written=219
                             ->  Index Scan using reviews_user_id_revision on reviews r (actual time=0.062..69.518 rows=100000 loops=1)
                                   Index Cond: (user_id = (InitPlan 1).col1)
                                   Filter: (deleted_at IS NULL)
                                   Buffers: shared hit=2623
   ->  CTE Scan on days (actual time=0.004..369.413 rows=366 loops=1)
         Buffers: shared hit=2623, temp written=219
 Planning:
   Buffers: shared hit=9
 Planning Time: 0.765 ms
 Execution Time: 370.450 ms
(30 rows)

 streak_before
---------------
           365
(1 row)

COMMIT
```

After:

```text
 reviews_before_today
----------------------
                99837
(1 row)

BEGIN
SET
SET
SET
### Q14 today's reviews, first page and count: web/src/features/study/read-today.ts:55-61
                                                                             QUERY PLAN
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.351..0.382 rows=163 loops=1)
   Buffers: shared hit=170
   InitPlan 1
     ->  Result (actual time=0.027..0.027 rows=1 loops=1)
   ->  Sort (actual time=0.350..0.362 rows=163 loops=1)
         Sort Key: reviews.id
         Sort Method: quicksort  Memory: 46kB
         Buffers: shared hit=170
         ->  Result (actual time=0.044..0.254 rows=163 loops=1)
               One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=167
               ->  Index Scan using reviews_live_user_id_reviewed_at on reviews (actual time=0.013..0.188 rows=163 loops=1)
                     Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (reviewed_at >= '2026-10-15 19:00:00+00'::timestamp with time zone))
                     Buffers: shared hit=167
 Planning:
   Buffers: shared hit=60
 Planning Time: 0.505 ms
 Execution Time: 0.454 ms
(18 rows)

                                                                          QUERY PLAN
--------------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=0.187..0.188 rows=1 loops=1)
   Buffers: shared hit=167
   InitPlan 1
     ->  Result (actual time=0.008..0.008 rows=1 loops=1)
   ->  Result (actual time=0.041..0.171 rows=163 loops=1)
         One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
         Buffers: shared hit=167
         ->  Index Only Scan using reviews_live_user_id_reviewed_at on reviews (actual time=0.031..0.140 rows=163 loops=1)
               Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (reviewed_at >= '2026-10-15 19:00:00+00'::timestamp with time zone))
               Heap Fetches: 163
               Buffers: shared hit=167
 Planning Time: 0.130 ms
 Execution Time: 0.217 ms
(13 rows)

### Q15 earlier reviews of 100 of today's cards, first page: read-today.ts:80-91
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=1.178..1.353 rows=898 loops=1)
   Buffers: shared hit=291
   InitPlan 1
     ->  Result (actual time=0.009..0.009 rows=1 loops=1)
   ->  Sort (actual time=1.177..1.244 rows=898 loops=1)
         Sort Key: reviews.id
         Sort Method: quicksort  Memory: 88kB
         Buffers: shared hit=291
         ->  Result (actual time=0.043..0.816 rows=898 loops=1)
               One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=291
               ->  Index Scan using reviews_user_id_card_id on reviews (actual time=0.032..0.684 rows=898 loops=1)
                     Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (card_id = ANY ('{00c8e1a9-8bd2-4cd9-bc73-3ec8a11d0a9c,0168485d-23a1-43a3-bb54-5dbef046e13f,0600baf2-0600-40fd-b745-e46a83c04f7f,061276d3-29d8-422a-8010-2d87088ed32a,061298ff-8613-4ef4-a0ad-d32ed8b86561,06ac6f3f-2123-4c91-be40-9ce6b6dc7efa,087001ad-926e-4e19-94d6-94e874744490,0a6e34c8-a1a4-4912-84e2-494f7b4cfbec,0aa42dec-b7e2-4c21-a502-1e1ed624ef67,0cc884d6-ea3c-4979-a0d7-328be4445e9d,0eb31f7e-b27e-4894-b6bc-241a407291e7,0f003a32-78ca-4c94-9f2c-efed764395f3,13c85d8c-bac2-4a88-a4e2-dd3602decb7b,15e82225-883a-4681-8ef3-e318674c05b3,167746fb-a43c-4ba0-b349-a1f3e47012a7,19597622-5603-4132-822e-6a6c9db508d5,1cac77e9-b368-4521-8b66-7819f46d05f4,1e047c5d-5b7d-4054-aebe-c20cc63a7389,1e5cea76-aafd-42d0-92e9-6304fc1624ea,1f119511-ba1f-402d-9150-6a97e3d852d2,203fc780-9459-4bee-bc13-1febb6745dda,2108c132-8438-4672-a577-97a906da44f6,226db278-73f7-472a-843e-665b30cef600,25451406-113a-4a96-adb5-7c156754fdd8,29ca3c7e-fb80-423e-bedb-f45f99165e87,2a039fb1-e49f-4ba9-a395-cba1fa3aeb38,2eda12bd-7ef1-4f9a-b0be-f7d2183b1bb0,2f38cf3e-713d-4a93-afc8-896b8f32bc06,2f6c6e06-a190-4b9b-b3d4-bd5415bbbaf1,2fad9e15-f012-4670-969e-c2d7117cde9a,30ab9014-9cb8-45cc-85cd-1063a3a69ef8,3151ff3e-8d72-44c5-865c-ea1f9347ebae,31b1b3ab-b8e1-43d3-9754-a8868f261435,324d0fda-0737-45c6-839d-d0503b17b66a,33bbec97-e80c-4fe2-a2af-c7efcaee5260,34191183-e997-4b56-9f95-f70fac29ee11,341ebe7e-0737-4f19-a844-999cf093c758,37599863-0442-465b-9166-39ebe2b95caf,38b06130-0733-402f-b695-93e64eeffc46,39657982-0118-440b-82f8-e1ce73c78616,3a9556cb-ca8f-455b-bb4b-0eb36b4cc0c4,3c9080f7-21cb-4f57-8ce7-5b64009b6029,40dc6d32-bde5-4e95-9644-ae2c59328b01,420a21ce-8b55-475b-b721-46b9f558e3d8,42827713-91d2-4f61-849b-7be34e87f1e0,4450b20f-48ec-4021-b985-caf427da52c9,445547f7-95bc-4a66-a5cd-673b25f35986,479cc03b-340b-438f-bb9f-aded788b9035,47c0b52f-9a94-48c3-86a9-7c6a0a2d3372,47ceb136-f16b-45d8-8156-d9bc7b63bf06,499ea3b6-9590-4ea7-a407-cc6c6301b6e8,4af3f810-0f31-4a85-9af1-280097cfe370,4e60b3de-79f6-4134-a64d-239186cd5d71,51285f9b-c471-4059-959e-29590414cb2a,56e8bf31-3171-4689-8d48-167c043746c3,5758a50d-9b5a-4992-8860-24ed757654e4,5c907086-df7d-4e26-89ff-eb5b481ccfb6,6210a3a0-6105-4d72-9550-187d52e64cda,621b7e9d-a3ae-4b6a-a7c4-20f596409a2b,6249365f-7df1-48e0-88c2-a0f5a54b5f0d,6408f563-a09a-4723-a2a5-b4ca711a1179,648c7144-26ad-493e-900c-6ec7844a252e,65a73047-4f10-4ee2-8592-7b52964206cb,6623677a-fe65-431c-b37a-033f2ca25128,665cbcb2-ef60-4635-aecc-414eb563a409,67696c4b-f0b6-4436-8d32-9af6408f33f1,676ceb5d-d524-4cd1-b404-3c0c7cb5c732,6b3792dd-ac2d-4735-8020-0f600ec1f34d,6d833871-065b-4cf4-9e19-44d77fc49b73,6e1b916d-10e3-47c4-b3ea-ae2d63edda1d,6ff8b98f-301d-4aeb-844e-9e9981ae16a9,7044bc60-8165-4346-8156-762ffd780362,72041338-7aeb-49b6-951e-d4e210668e27,73784f9e-b062-4aca-9f1e-8d7fd50d0dbe,7569a345-a5ea-43d7-96b6-dee69be0e197,77b2787f-69a4-4be0-9b72-625aaf5c20bb,79231011-2a7e-4f70-8d25-3b1e1b19c155,7bad87af-dc09-4d98-a9bd-9b81ccd26320,7c5e72d0-9189-47c2-a223-e991ca51a019,7cfdc736-23d6-479e-aa13-3f853bf50a07,7dd00d72-a5b5-4eaa-9f45-fa46aaffaf2b,7fc827a0-6f43-43ef-94eb-2e0f74b95a13,804034cc-34ec-44b5-9b3b-40eaea3990df,8330483b-d20e-4042-81ac-6a5d9bf88fe1,83c37e7f-2929-4574-9994-d0d0e9f49f07,84170cf0-a15e-4ec7-8601-bd052b2458a4,860877fb-9b9b-4054-b7f2-02ad3dafcc51,870d4275-bd84-4b59-ac8d-303901019aa7,87d5a216-ebd8-4dc6-b838-510febcd5db2,880b160b-6603-44d7-8c10-0d8a2fcbdaaf,88d7fa26-dc64-43a2-a076-6421415b4ad1,8c94ece8-71fd-4e5b-bd16-5f53d168d8b6,8d6cbc30-002f-4830-808e-74e2bcdb51d6,8df99953-5302-45f2-b3b9-51cab27f60a1,8eeabe9b-4527-42ac-9bbf-69df836e7cbd,90a5f550-25d3-4381-be7b-88b922f40977,93127924-5108-47f6-b203-e21a016fd0bb,9571da1d-01d7-4f61-82d5-47c3582f8b5a,9655c488-654c-4d79-bc5d-609f8aac2419,9737be38-6c11-49d8-b568-434d3b4a917d}'::uuid[])))
                     Filter: ((deleted_at IS NULL) AND (reviewed_at < '2026-10-15 19:00:00+00'::timestamp with time zone))
                     Rows Removed by Filter: 102
                     Buffers: shared hit=291
 Planning:
   Buffers: shared hit=3
 Planning Time: 0.214 ms
 Execution Time: 1.454 ms
(20 rows)

### Q16 the streak, one page of 1,000 earlier answers newest first: read-today.ts:121-129
                                                                         QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=0.030..1.376 rows=1000 loops=1)
   Buffers: shared hit=1007
   InitPlan 1
     ->  Result (actual time=0.009..0.009 rows=1 loops=1)
   ->  Result (actual time=0.030..1.264 rows=1000 loops=1)
         One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
         Buffers: shared hit=1007
         ->  Index Only Scan Backward using reviews_live_user_id_reviewed_at on reviews (actual time=0.019..1.106 rows=1000 loops=1)
               Index Cond: ((user_id = '00000000-0000-4000-8000-000000000000'::uuid) AND (reviewed_at < '2026-10-15 19:00:00+00'::timestamp with time zone))
               Heap Fetches: 1000
               Buffers: shared hit=1007
 Planning:
   Buffers: shared hit=5
 Planning Time: 0.167 ms
 Execution Time: 1.466 ms
(15 rows)

### Q16 page 50 of the same paging
                                                        QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------
 Limit (actual time=91.531..91.805 rows=1000 loops=1)
   Buffers: shared hit=1793
   InitPlan 1
     ->  Result (actual time=0.012..0.012 rows=1 loops=1)
   ->  Sort (actual time=84.666..88.509 rows=50000 loops=1)
         Sort Key: reviews.reviewed_at DESC
         Sort Method: quicksort  Memory: 3073kB
         Buffers: shared hit=1793
         ->  Result (actual time=5.230..53.444 rows=99837 loops=1)
               One-Time Filter: ((InitPlan 1).col1 = '00000000-0000-4000-8000-000000000000'::uuid)
               Buffers: shared hit=1790
               ->  Bitmap Heap Scan on reviews (actual time=5.215..34.479 rows=99837 loops=1)
                     Recheck Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                     Filter: ((deleted_at IS NULL) AND (reviewed_at < '2026-10-15 19:00:00+00'::timestamp with time zone))
                     Rows Removed by Filter: 163
                     Heap Blocks: exact=1640
                     Buffers: shared hit=1790
                     ->  Bitmap Index Scan on reviews_user_id_card_id (actual time=4.835..4.835 rows=100000 loops=1)
                           Index Cond: (user_id = '00000000-0000-4000-8000-000000000000'::uuid)
                           Buffers: shared hit=150
 Planning Time: 0.209 ms
 Execution Time: 92.480 ms
(22 rows)

### Q17 proposed: the streak in one statement, one index probe per study day (Asia/Seoul)
                                                                                           QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=359.170..359.175 rows=1 loops=1)
   Buffers: shared hit=11622, temp written=219
   CTE days
     ->  Recursive Union (actual time=0.003..358.772 rows=366 loops=1)
           Buffers: shared hit=11622, temp written=219
           ->  Result (actual time=0.001..0.002 rows=1 loops=1)
           ->  Result (actual time=0.978..0.978 rows=1 loops=366)
                 One-Time Filter: ((InitPlan 2).col1 = (InitPlan 1).col1)
                 Buffers: shared hit=11622, temp written=219
                 InitPlan 1
                   ->  Result (actual time=0.004..0.004 rows=1 loops=1)
                 InitPlan 2
                   ->  Result (actual time=0.017..0.017 rows=1 loops=1)
                 ->  Nested Loop Semi Join (actual time=0.975..0.975 rows=1 loops=366)
                       Join Filter: ((r.reviewed_at >= d.day_start) AND (r.reviewed_at < (((d.day_start AT TIME ZONE 'Asia/Seoul'::text) + '1 day'::interval) AT TIME ZONE 'Asia/Seoul'::text)))
                       Rows Removed by Join Filter: 626
                       Buffers: shared hit=11622, temp written=219
                       ->  WorkTable Scan on days d (actual time=0.000..0.000 rows=1 loops=366)
                       ->  Materialize (actual time=0.000..0.356 rows=627 loops=366)
                             Buffers: shared hit=11622, temp written=219
                             ->  Index Scan using reviews_user_id_card_id on reviews r (actual time=0.020..56.933 rows=100000 loops=1)
                                   Index Cond: (user_id = (InitPlan 1).col1)
                                   Filter: (deleted_at IS NULL)
                                   Buffers: shared hit=11622
   ->  CTE Scan on days (actual time=0.005..359.042 rows=366 loops=1)
         Buffers: shared hit=11622, temp written=219
 Planning:
   Buffers: shared hit=13
 Planning Time: 0.630 ms
 Execution Time: 359.784 ms
(30 rows)

 streak_before
---------------
           365
(1 row)

COMMIT
```

The streak function's `max()` form, after:

```sql
-- The streak in one statement: for each study day back from yesterday, the latest answer before
-- the day's end, read by one backward probe of reviews_live_user_id_reviewed_at (Asia/Seoul).
\pset pager off
select ((date_trunc('day', (now() at time zone 'Asia/Seoul') - interval '4 hours') + interval '4 hours')
  at time zone 'Asia/Seoul') as day_start \gset
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-000000000000","role":"authenticated"}';
\echo '### Q17 proposed: the streak, one max() probe per study day'
explain (analyze, buffers, costs off, summary on)
with recursive days(day_start, streak) as (
  select ((:'day_start'::timestamptz at time zone 'Asia/Seoul') - interval '1 day') at time zone 'Asia/Seoul', 0
  union all
  select ((d.day_start at time zone 'Asia/Seoul') - interval '1 day') at time zone 'Asia/Seoul', d.streak + 1
  from days d
  where (
    select max(r.reviewed_at) from public.reviews r
    where r.user_id = (select auth.uid()) and r.deleted_at is null
      and r.reviewed_at < ((d.day_start at time zone 'Asia/Seoul') + interval '1 day') at time zone 'Asia/Seoul'
  ) >= d.day_start
)
select max(streak) from days;
with recursive days(day_start, streak) as (
  select ((:'day_start'::timestamptz at time zone 'Asia/Seoul') - interval '1 day') at time zone 'Asia/Seoul', 0
  union all
  select ((d.day_start at time zone 'Asia/Seoul') - interval '1 day') at time zone 'Asia/Seoul', d.streak + 1
  from days d
  where (
    select max(r.reviewed_at) from public.reviews r
    where r.user_id = (select auth.uid()) and r.deleted_at is null
      and r.reviewed_at < ((d.day_start at time zone 'Asia/Seoul') + interval '1 day') at time zone 'Asia/Seoul'
  ) >= d.day_start
)
select max(streak) as streak_before from days;
commit;
```

```text
BEGIN
SET
SET
### Q17 proposed: the streak, one max() probe per study day
                                                                                                    QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate (actual time=40.401..40.405 rows=1 loops=1)
   Buffers: shared hit=1463
   CTE days
     ->  Recursive Union (actual time=0.004..39.914 rows=366 loops=1)
           Buffers: shared hit=1463
           ->  Result (actual time=0.002..0.003 rows=1 loops=1)
           ->  WorkTable Scan on days d (actual time=0.103..0.104 rows=1 loops=366)
                 Filter: ((SubPlan 4) >= day_start)
                 Rows Removed by Filter: 0
                 Buffers: shared hit=1463
                 SubPlan 4
                   ->  Result (actual time=0.098..0.098 rows=1 loops=366)
                         Buffers: shared hit=1463
                         InitPlan 1
                           ->  Result (actual time=0.005..0.005 rows=1 loops=1)
                         InitPlan 2
                           ->  Result (actual time=0.042..0.042 rows=1 loops=1)
                         InitPlan 3
                           ->  Limit (actual time=0.096..0.096 rows=1 loops=366)
                                 Buffers: shared hit=1463
                                 ->  Result (actual time=0.096..0.096 rows=1 loops=366)
                                       One-Time Filter: ((InitPlan 2).col1 = (InitPlan 1).col1)
                                       Buffers: shared hit=1463
                                       ->  Index Only Scan Backward using reviews_live_user_id_reviewed_at on reviews r (actual time=0.093..0.093 rows=1 loops=366)
                                             Index Cond: ((user_id = (InitPlan 1).col1) AND (reviewed_at < (((d.day_start AT TIME ZONE 'Asia/Seoul'::text) + '1 day'::interval) AT TIME ZONE 'Asia/Seoul'::text)))
                                             Heap Fetches: 365
                                             Buffers: shared hit=1463
   ->  CTE Scan on days (actual time=0.007..40.197 rows=366 loops=1)
         Buffers: shared hit=1463
 Planning:
   Buffers: shared hit=215
 Planning Time: 6.447 ms
 Execution Time: 40.648 ms
(33 rows)

 streak_before
---------------
           365
(1 row)

COMMIT
```

Phone:

```sql
CREATE TEMP TABLE n AS WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1000) SELECT i FROM n;
-- Today (from 1731500000): 20 cards answered for the first time, and 200 answers to older cards.
BEGIN;
INSERT INTO reviews SELECT printf('t%07d', i), printf('c%06d', i), 'good', 1731500000 + i * 60, 5000, 0.5, 1731500000, NULL, 0 FROM n WHERE i <= 200;
INSERT INTO cards SELECT printf('new%03d', i), 'd0001', '[]', '[]', 'new ' || i, 'manual', NULL, 1731400000, 1731400000, NULL, 0 FROM n WHERE i <= 20;
INSERT INTO reviews SELECT printf('f%07d', i), printf('new%03d', i), 'good', 1731500000 + i * 90, 5000, 0.5, 1731500000, NULL, 0 FROM n WHERE i <= 20;
COMMIT;
ANALYZE;
```

```sql
PRAGMA foreign_keys = ON;
.eqp on
.timer on
.print '### P13 firstAnswersSince: app/lib/study/src/study_repository.dart:88-101'
SELECT MIN(reviewed_at) FROM reviews WHERE deleted_at IS NULL GROUP BY card_id HAVING MIN(reviewed_at) >= 1731500000;
.print '### P13r the same, from today''s cards (proposed rewrite)'
SELECT MIN(reviewed_at) FROM reviews WHERE deleted_at IS NULL AND card_id IN (SELECT card_id FROM reviews WHERE deleted_at IS NULL AND reviewed_at >= 1731500000) GROUP BY card_id HAVING MIN(reviewed_at) >= 1731500000;
.print '### P14 answersSince: study_repository.dart:104-125'
SELECT * FROM reviews WHERE deleted_at IS NULL AND reviewed_at >= 1731500000 ORDER BY reviewed_at;
.print '### P15 answerTimes: study_repository.dart:128-140'
SELECT reviewed_at FROM reviews WHERE deleted_at IS NULL ORDER BY reviewed_at DESC;
```

```sql
.eqp on
.timer on
.print '### P15p the streak by one probe per study day (proposed; days of 86,400 s here, local boundaries in the app)'
WITH RECURSIVE days(day_start, streak) AS (
  SELECT 1731500000 - 86400, 0
  UNION ALL
  SELECT day_start - 86400, streak + 1 FROM days
  WHERE EXISTS (SELECT 1 FROM reviews WHERE deleted_at IS NULL AND reviewed_at >= day_start AND reviewed_at < day_start + 86400)
)
SELECT MAX(streak) FROM days;
```

Before:

```text
### P13 firstAnswersSince: app/lib/study/src/study_repository.dart:88-101
QUERY PLAN
|--SCAN reviews
`--USE TEMP B-TREE FOR GROUP BY
Run Time: real 0.064 user 0.058188 sys 0.004282
### P13r the same, from today s cards (proposed rewrite)
QUERY PLAN
|--SCAN reviews
|--LIST SUBQUERY 1
|  |--SCAN reviews
|  `--CREATE BLOOM FILTER
`--USE TEMP B-TREE FOR GROUP BY
Run Time: real 0.057 user 0.053645 sys 0.002796
### P14 answersSince: study_repository.dart:104-125
QUERY PLAN
|--SCAN reviews
`--USE TEMP B-TREE FOR ORDER BY
Run Time: real 0.014 user 0.011750 sys 0.001396
### P15 answerTimes: study_repository.dart:128-140
QUERY PLAN
|--SCAN reviews
`--USE TEMP B-TREE FOR ORDER BY
Run Time: real 0.126 user 0.086198 sys 0.003040
```

After:

```text
### P13 firstAnswersSince: app/lib/study/src/study_repository.dart:88-101
QUERY PLAN
`--SCAN reviews USING INDEX reviews_card_id_reviewed_at
Run Time: real 0.092 user 0.085791 sys 0.004660
### P13r the same, from today s cards (proposed rewrite)
QUERY PLAN
|--SEARCH reviews USING INDEX reviews_card_id_reviewed_at (card_id=?)
`--LIST SUBQUERY 1
   |--SEARCH reviews USING INDEX reviews_live_reviewed_at (reviewed_at>?)
   `--CREATE BLOOM FILTER
Run Time: real 0.004 user 0.004181 sys 0.000401
### P14 answersSince: study_repository.dart:104-125
QUERY PLAN
`--SEARCH reviews USING INDEX reviews_live_reviewed_at (reviewed_at>?)
Run Time: real 0.002 user 0.001264 sys 0.000130
### P15 answerTimes: study_repository.dart:128-140
QUERY PLAN
`--SCAN reviews USING INDEX reviews_live_reviewed_at
Run Time: real 0.050 user 0.036131 sys 0.001734
### P15p the streak by one probe per study day (proposed; days of 86,400 s here, local boundaries in the app)
QUERY PLAN
|--CO-ROUTINE days
|  |--SETUP
|  |  `--SCAN CONSTANT ROW
|  `--RECURSIVE STEP
|     |--SCAN days
|     `--CORRELATED SCALAR SUBQUERY 2
|        `--SEARCH reviews USING INDEX reviews_live_reviewed_at (reviewed_at>? AND reviewed_at<?)
`--SEARCH days
Run Time: real 0.021 user 0.001949 sys 0.008287
```
