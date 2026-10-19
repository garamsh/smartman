-- The streak: study_streak_before counts the caller's study days in a row before the day holding
-- before, from 04:00 to 04:00 in the zone named, on the instants web/src/features/study's
-- queue.test.ts counts; it reads only the caller's live answers and runs as the caller.
begin;
select plan(17);

-- One user per case, so each case reads only its own answers.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-000000000001', 'utc@example.com'),
  ('00000000-0000-4000-8000-000000000002', 'late-utc@example.com'),
  ('00000000-0000-4000-8000-000000000003', 'seoul-before@example.com'),
  ('00000000-0000-4000-8000-000000000004', 'seoul-at@example.com'),
  ('00000000-0000-4000-8000-000000000005', 'los-angeles@example.com'),
  ('00000000-0000-4000-8000-000000000006', 'los-angeles-after@example.com'),
  ('00000000-0000-4000-8000-000000000007', 'los-angeles-start@example.com'),
  ('00000000-0000-4000-8000-000000000008', 'los-angeles-before-start@example.com'),
  ('00000000-0000-4000-8000-000000000009', 'other@example.com');

-- Stores an answer of [who] at [at]. Written in replica mode, which
-- skips the foreign keys and the revision trigger, since the streak reads only the answer's time.
create function pg_temp.answer(who uuid, at timestamptz) returns void
language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.reviews
    (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at, revision)
  values (gen_random_uuid(), who, gen_random_uuid(), 'good', at, 1000, at, 0);
  set local session_replication_role = origin;
end;
$$;

-- The streak study_streak_before returns to [who], signed in, for [time_zone] and [before].
create function pg_temp.streak_of(who uuid, time_zone text, before timestamptz) returns integer
language plpgsql as $$
declare
  streak integer;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', who, 'role', 'authenticated')::text, true);
  set local role authenticated;
  streak := public.study_streak_before(time_zone, before);
  reset role;
  return streak;
end;
$$;

-- queue.test.ts "counts study days in a row back from today": answers at noon UTC on 14, 13 and
-- 10 October 2026 and at 05:00 on the 12th; there the streak is 3 with today, the 14th.
select pg_temp.answer('00000000-0000-4000-8000-000000000001', '2026-10-14 12:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000001', '2026-10-13 12:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000001', '2026-10-12 05:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000001', '2026-10-10 12:00Z');
select is(pg_temp.streak_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-14 20:00Z'), 2,
  'the two days before today, the 13th and the 12th, are in a row; the 11th has no answer');
select is(pg_temp.streak_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-16 12:00Z'), 0,
  'a gap: the day before the 16th has no answer, so no run reaches it');
select is(pg_temp.streak_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-15 12:00Z'), 3,
  'control: from the 15th, the 14th, 13th and 12th are in a row');

-- queue.test.ts "An answer at 03:00 belongs to the day before".
select pg_temp.answer('00000000-0000-4000-8000-000000000002', '2026-10-14 12:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000002', '2026-10-14 03:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000002', '2026-10-12 12:00Z');
select is(pg_temp.streak_of('00000000-0000-4000-8000-000000000002', 'UTC', '2026-10-14 20:00Z'), 2,
  'an answer at 03:00 on the 14th counts for the 13th, so the 13th and the 12th are in a row');

-- queue.test.ts "starts at 04:00 local time": 03:59 and 04:00 on 15 October in Seoul are 18:59 and
-- 19:00 UTC on the 14th. At 11:00 in Seoul on the 15th, today began at 04:00.
select pg_temp.answer('00000000-0000-4000-8000-000000000003', '2026-10-14 18:59Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000004', '2026-10-14 19:00Z');
select is(
  pg_temp.streak_of('00000000-0000-4000-8000-000000000003', 'Asia/Seoul', '2026-10-15 02:00Z'), 1,
  'an answer at 03:59 in Seoul counts for the day before');
select is(
  pg_temp.streak_of('00000000-0000-4000-8000-000000000004', 'Asia/Seoul', '2026-10-15 02:00Z'), 0,
  'an answer at 04:00 in Seoul counts for today, not before it');
select is(pg_temp.streak_of('00000000-0000-4000-8000-000000000004', 'Asia/Seoul', '2026-10-15 20:00Z'), 1,
  'control: the same answer counts for the day before 05:00 in Seoul on the 16th');

-- queue.test.ts "runs from 04:00 to 04:00 local time across a change of offset": in Los Angeles
-- the day of 31 October 2026 runs from 11:00 UTC that day (04:00 PDT) to 12:00 UTC on 1 November
-- (04:00 PST), 25 hours. Each case asks at 12:00 PST on 1 November, 20:00 UTC.
select pg_temp.answer('00000000-0000-4000-8000-000000000005', '2026-11-01 11:30Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000006', '2026-11-01 12:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000007', '2026-10-31 11:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000008', '2026-10-31 10:59Z');
select is(
  pg_temp.streak_of('00000000-0000-4000-8000-000000000005', 'America/Los_Angeles', '2026-11-01 20:00Z'),
  1, '03:30 PST on 1 November, past a fixed 24 hours, counts for 31 October');
select is(
  pg_temp.streak_of('00000000-0000-4000-8000-000000000006', 'America/Los_Angeles', '2026-11-01 20:00Z'),
  0, '04:00 PST on 1 November counts for that day, today');
select is(
  pg_temp.streak_of('00000000-0000-4000-8000-000000000007', 'America/Los_Angeles', '2026-11-01 20:00Z'),
  1, '04:00 PDT on 31 October counts for 31 October');
select is(
  pg_temp.streak_of('00000000-0000-4000-8000-000000000008', 'America/Los_Angeles', '2026-11-01 20:00Z'),
  0, '03:59 PDT on 31 October counts for 30 October, so 31 October has no answer');

-- Only the caller's answers count.
select pg_temp.answer('00000000-0000-4000-8000-000000000009', '2026-10-15 13:00Z');
select is(pg_temp.streak_of('00000000-0000-4000-8000-000000000009', 'UTC', '2026-10-16 12:00Z'), 1,
  'an answer on the day before counts');
select is(pg_temp.streak_of('00000000-0000-4000-8000-000000000009', 'UTC', '2026-10-15 20:00Z'), 0,
  'another user''s answers do not count: user 1''s 14th, 13th and 12th are not this user''s');

select throws_ok(
  $$select pg_temp.streak_of('00000000-0000-4000-8000-000000000001', 'Mars/Olympus', '2026-10-16 12:00Z')$$,
  '22023', null, 'a zone Postgres does not know raises');

select function_privs_are('public', 'study_streak_before', array['text', 'timestamp with time zone'],
  'authenticated', array['EXECUTE'], 'authenticated may read its streak');
select function_privs_are('public', 'study_streak_before', array['text', 'timestamp with time zone'],
  'anon', array[]::text[], 'anon may not');
select results_eq(
  $$select prosecdef, provolatile = 's', proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.study_streak_before(text, timestamptz)'::regprocedure$$,
  $$values (false, true, true)$$,
  'it runs as the caller, is stable, and sets an empty search_path');

select * from finish();
rollback;
