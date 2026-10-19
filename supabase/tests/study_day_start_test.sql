-- The study day's start hour: study_streak_before, study_days_before and study_record_days each
-- start a study day at study_day_start_hour(), so moving that one hour moves all three, and the
-- hour is 04:00, the one web/src/features/study/__tests__/rules.test.ts compares with queue.ts.
begin;
select plan(10);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-000000000001', 'hour@example.com');

-- One answer at 04:30 UTC on 13 October 2026: in the day from 04:00 on the 13th, or, with days
-- from 05:00, in the day from 05:00 on the 12th. Written in replica mode, which skips the foreign
-- keys and the revision trigger, since the functions read only the answer's time and card.
set local session_replication_role = replica;
insert into public.reviews
  (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at, revision)
values (gen_random_uuid(), '00000000-0000-4000-8000-000000000001', gen_random_uuid(), 'good',
  '2026-10-13 04:30Z', 1000, '2026-10-13 04:30Z', 0);
set local session_replication_role = origin;

-- Signs the test in as that user.
create function pg_temp.sign_in() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-4000-8000-000000000001', 'role', 'authenticated')::text,
    true);
  set local role authenticated;
end;
$$;

-- The streak before noon UTC on the 14th: 1 when the answer is in the day before the 14th's.
create function pg_temp.streak() returns integer
language plpgsql as $$
declare
  streak integer;
begin
  perform pg_temp.sign_in();
  -- Read through FROM, as the others are: an assignment would keep the function's plan from the
  -- first call for the transaction, and so the hour it was planned with.
  select s into streak from public.study_streak_before('UTC', '2026-10-14 12:00Z') as s;
  reset role;
  return streak;
end;
$$;

-- The start of the one study day study_days_before returns before the 14th's noon.
create function pg_temp.days_start() returns timestamptz
language plpgsql as $$
declare
  start timestamptz;
begin
  perform pg_temp.sign_in();
  select d.day_start into start
  from public.study_days_before('UTC', '2026-10-14 12:00Z', 30, 30000) as d;
  reset role;
  return start;
end;
$$;

-- The start of the one study day study_record_days returns before the 14th's noon.
create function pg_temp.record_start() returns timestamptz
language plpgsql as $$
declare
  start timestamptz;
begin
  perform pg_temp.sign_in();
  select d.day_start into start from public.study_record_days('UTC', '2026-10-14 12:00Z') as d;
  reset role;
  return start;
end;
$$;

select is(public.study_day_start_hour(), 4, 'a study day starts at 04:00');
select is(pg_temp.streak(), 1, 'from 04:00, the answer at 04:30 is in the day before the 14th''s');
select is(pg_temp.days_start(), '2026-10-13 04:00Z'::timestamptz,
  'from 04:00, study_days_before puts the answer in the day from 04:00 on the 13th');
select is(pg_temp.record_start(), '2026-10-13 04:00Z'::timestamptz,
  'from 04:00, study_record_days puts the answer in the day from 04:00 on the 13th');

-- The hour moved to 05:00, inside this transaction alone: each function follows it.
create or replace function public.study_day_start_hour() returns integer
language sql
immutable
security invoker
set search_path = ''
as $$
  select 5
$$;

select is(public.study_day_start_hour(), 5, 'the hour is moved to 05:00 for the rest of the test');
select is(pg_temp.streak(), 0,
  'from 05:00, the answer at 04:30 on the 13th is two days before the 14th''s, so no run');
select is(pg_temp.days_start(), '2026-10-12 05:00Z'::timestamptz,
  'from 05:00, study_days_before puts the answer in the day from 05:00 on the 12th');
select is(pg_temp.record_start(), '2026-10-12 05:00Z'::timestamptz,
  'from 05:00, study_record_days puts the answer in the day from 05:00 on the 12th');

select function_privs_are('public', 'study_day_start_hour', '{}', 'authenticated', '{EXECUTE}',
  'authenticated can read the hour, as it calls the three functions');
select function_privs_are('public', 'study_day_start_hour', '{}', 'anon', '{}',
  'anon cannot read the hour');

select * from finish();
rollback;
