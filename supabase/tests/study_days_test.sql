-- The study days: study_days_before returns the caller's latest study days before a time, from
-- 04:00 to 04:00 in the zone named, each with its reviews' and first answers' time and number,
-- every answer counted up to the cap; it reads only the caller's live answers and runs as the
-- caller.
begin;
select plan(14);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-000000000001', 'window@example.com'),
  ('00000000-0000-4000-8000-000000000002', 'longer@example.com'),
  ('00000000-0000-4000-8000-000000000003', 'seoul@example.com'),
  ('00000000-0000-4000-8000-000000000004', 'first@example.com');

-- The id of the card named by the letter [name].
create function pg_temp.card(name char) returns uuid
language sql as $$
  select (repeat(name, 8) || '-0000-4000-8000-000000000000')::uuid
$$;

-- Stores an answer of [who] to the card named [card] at [at], taking [ms], tombstoned when [deleted]. Written in
-- replica mode, which skips the foreign keys and the revision trigger, since the function reads
-- only the answer's card, time and duration.
create function pg_temp.answer(
  who uuid, card char, at timestamptz, ms integer default 6000, deleted boolean default false
) returns void
language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.reviews
    (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at, deleted_at, revision)
  values (gen_random_uuid(), who, pg_temp.card(card), 'good', at, ms, at,
    case when deleted then at end, 0);
  set local session_replication_role = origin;
end;
$$;

-- What study_days_before returns to [who], signed in, as one text per day, oldest first.
create function pg_temp.days_of(
  who uuid, time_zone text, before timestamptz, days integer, cap_ms integer default 30000
) returns text[]
language plpgsql as $$
declare
  result text[];
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', who, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select array_agg(format('%s %s/%s %s/%s', d.day_start, d.review_ms, d.reviews, d.first_ms,
      d.first_answers) order by d.day_start)
    into result
    from public.study_days_before(time_zone, before, days, cap_ms) as d;
  reset role;
  return result;
end;
$$;

set local timezone = 'UTC';

-- Three study days with rests between, UTC: card a first answered on the 8th and reviewed on the
-- 10th, card b first answered on the 12th; and one answer on the 14th, today.
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'a', '2026-10-08 12:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'a', '2026-10-10 12:00Z', 4000);
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'b', '2026-10-12 12:00Z', 600000);
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'b', '2026-10-14 05:00Z');
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-14 04:00Z', 30),
  array['2026-10-08 04:00:00+00 0/0 6000/1', '2026-10-10 04:00:00+00 4000/1 0/0',
    '2026-10-12 04:00:00+00 0/0 30000/1'],
  'each study day before today, oldest first, rests left out, a review and a first answer apart, the 10-minute answer counted as 30 s');
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-14 04:00Z', 2),
  array['2026-10-10 04:00:00+00 4000/1 0/0', '2026-10-12 04:00:00+00 0/0 30000/1'],
  'only the latest so many study days, however many days of rest lie between them');
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-14 04:00Z', 30, 1000000),
  array['2026-10-08 04:00:00+00 0/0 6000/1', '2026-10-10 04:00:00+00 4000/1 0/0',
    '2026-10-12 04:00:00+00 0/0 600000/1'],
  'control: under a higher cap the stored 10 minutes count whole');

-- The same two latest study days, and longer history before them on another card: the window
-- reads the same.
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'a', '2026-10-08 12:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'a', '2026-10-10 12:00Z', 4000);
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'b', '2026-10-12 12:00Z', 600000);
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'c', '2026-09-01 12:00Z', 25000);
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'c', '2026-09-02 12:00Z', 25000);
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000002', 'UTC', '2026-10-14 04:00Z', 2),
  pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-14 04:00Z', 2),
  'history before the window changes nothing in it');
select isnt(
  pg_temp.days_of('00000000-0000-4000-8000-000000000002', 'UTC', '2026-10-14 04:00Z', 30),
  pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-14 04:00Z', 30),
  'control: a window long enough to reach it reads it');

-- 03:59 and 04:00 on 15 October in Seoul are 18:59 and 19:00 UTC on the 14th.
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'a', '2026-10-14 18:59Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'b', '2026-10-14 19:00Z');
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000003', 'Asia/Seoul', '2026-10-15 19:00Z', 30),
  array['2026-10-13 19:00:00+00 0/0 6000/1', '2026-10-14 19:00:00+00 0/0 6000/1'],
  'an answer at 03:59 in Seoul belongs to the day before, one at 04:00 to its own');

-- A first answer later deleted: the next live answer is the card's first.
select pg_temp.answer('00000000-0000-4000-8000-000000000004', 'a', '2026-10-10 12:00Z', 6000, true);
select pg_temp.answer('00000000-0000-4000-8000-000000000004', 'a', '2026-10-11 12:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000004', 'a', '2026-10-11 12:01Z', 4000);
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000004', 'UTC', '2026-10-14 04:00Z', 30),
  array['2026-10-11 04:00:00+00 4000/1 6000/1'],
  'a deleted answer is read for nothing, so the next live answer is the card''s first');
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000004', 'UTC', '2026-10-11 12:01Z', 30),
  array['2026-10-11 04:00:00+00 0/0 6000/1'],
  'answers at or after the time given are left out');
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000004', 'UTC', '2026-10-10 04:00Z', 30),
  null,
  'no answer before the time given: no study day');

-- Only the caller's answers: user 4 reads none of user 1's.
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000004', 'UTC', '2026-10-11 04:00Z', 30),
  null,
  'another user''s answers are not read: user 1''s 8th and 10th are not this user''s');

select throws_ok(
  $$select pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'Mars/Olympus', '2026-10-14 04:00Z', 30)$$,
  '22023', null, 'a zone Postgres does not know raises');

select function_privs_are('public', 'study_days_before',
  array['text', 'timestamp with time zone', 'integer', 'integer'],
  'authenticated', array['EXECUTE'], 'authenticated may read its study days');
select function_privs_are('public', 'study_days_before',
  array['text', 'timestamp with time zone', 'integer', 'integer'],
  'anon', array[]::text[], 'anon may not');
select results_eq(
  $$select prosecdef, provolatile = 's', proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.study_days_before(text, timestamptz, integer, integer)'::regprocedure$$,
  $$values (false, true, true)$$,
  'it runs as the caller, is stable, and sets an empty search_path');

select * from finish();
rollback;
