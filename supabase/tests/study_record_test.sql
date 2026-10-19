-- The 기록 reads: study_record_days returns each study day's distinct cards, scheduled reviews and
-- those known, on the histories app/test/study/stats_test.dart counts; study_record_cards returns
-- each live card of a live deck with its state and its live answers in order; both read only the
-- caller's rows and run as the caller.
begin;
select plan(16);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-000000000001', 'retention@example.com'),
  ('00000000-0000-4000-8000-000000000002', 'seoul@example.com'),
  ('00000000-0000-4000-8000-000000000003', 'cards@example.com');

-- The id of the card named by the letter [name].
create function pg_temp.card(name char) returns uuid
language sql as $$
  select (repeat(name, 8) || '-0000-4000-8000-000000000000')::uuid
$$;

-- Stores an answer of [who] to the card named [card] at [at], "good" when [know], with [fuzz]. Written in replica mode, which skips the foreign keys and the revision
-- trigger, since study_record_days reads only the answer's card, rating and time.
create function pg_temp.answer(
  who uuid, card char, at timestamptz, know boolean default true, fuzz double precision default null
) returns void
language plpgsql as $$
begin
  set local session_replication_role = replica;
  insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, fuzz_factor,
    updated_at, revision)
  values (gen_random_uuid(), who, pg_temp.card(card), case when know then 'good' else 'again' end,
    at, 6000, fuzz, at, 0);
  set local session_replication_role = origin;
end;
$$;

-- What study_record_days returns to [who], signed in, as one text per day, oldest first:
-- "start cards/reviews/known".
create function pg_temp.days_of(who uuid, time_zone text, before timestamptz) returns text[]
language plpgsql as $$
declare
  result text[];
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', who, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select array_agg(format('%s %s/%s/%s', d.day_start, d.cards, d.reviews, d.known)
      order by d.day_start)
    into result
    from public.study_record_days(time_zone, before) as d;
  reset role;
  return result;
end;
$$;

-- What study_record_cards returns to [who], signed in, as one text per card.
create function pg_temp.cards_of(who uuid) returns text[]
language plpgsql as $$
declare
  result text[];
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', who, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select array_agg(format('%s %s %s %s %s', left(c.card_id::text, 1), c.stability, c.ratings,
      c.reviewed_at, c.fuzz_factors) order by c.card_id)
    into result
    from public.study_record_cards() as c;
  reset role;
  return result;
end;
$$;

set local timezone = 'UTC';

-- The retention test's history: card a's and b's first answers on 10 October, a re-show of b the
-- same day as its scheduled review, c first answered at 03:59 on the 12th, which ends the 11th's
-- study day, and d answered twice from 04:00 on the 12th, one study day.
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'a', '2026-10-10 09:00Z', false);
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'a', '2026-10-12 09:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'b', '2026-10-10 09:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'b', '2026-10-12 10:00Z', false);
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'b', '2026-10-12 10:05Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'c', '2026-10-12 03:59Z', false);
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'c', '2026-10-12 04:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'd', '2026-10-12 04:00Z', false);
select pg_temp.answer('00000000-0000-4000-8000-000000000001', 'd', '2026-10-12 05:00Z');
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-14 09:00Z'),
  array['2026-10-10 04:00:00+00 2/0/0', '2026-10-11 04:00:00+00 1/0/0',
    '2026-10-12 04:00:00+00 4/3/2'],
  'a card''s first answer of a later study day is scheduled, from 04:00; its first answer ever, a re-show and a second answer the same day are not');

select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'UTC', '2026-10-12 04:00Z'),
  array['2026-10-10 04:00:00+00 2/0/0', '2026-10-11 04:00:00+00 1/0/0'],
  'answers at or after the time given are left out');

-- The study days test's history in Seoul: 03:59 on 14 October there is 18:59 UTC on the 13th.
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'a', '2026-10-13 18:59Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'a', '2026-10-13 19:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'a', '2026-10-13 20:00Z', false);
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'b', '2026-10-13 21:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'c', '2026-07-22 18:59Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000002', 'd', '2026-07-22 19:00Z');
select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000002', 'Asia/Seoul', '2026-10-14 09:00Z'),
  array['2026-07-21 19:00:00+00 1/0/0', '2026-07-22 19:00:00+00 1/0/0',
    '2026-10-12 19:00:00+00 1/0/0', '2026-10-13 19:00:00+00 2/1/1'],
  'in Seoul an answer at 03:59 belongs to the day before and one at 04:00 to its own, each card counted once a day');
select isnt(
  pg_temp.days_of('00000000-0000-4000-8000-000000000002', 'UTC', '2026-10-14 09:00Z'),
  pg_temp.days_of('00000000-0000-4000-8000-000000000002', 'Asia/Seoul', '2026-10-14 09:00Z'),
  'control: in UTC the same answers fall on other days');

select is(
  pg_temp.days_of('00000000-0000-4000-8000-000000000003', 'UTC', '2026-10-14 09:00Z'),
  null,
  'another user''s answers are not read');
select throws_ok(
  $$select pg_temp.days_of('00000000-0000-4000-8000-000000000001', 'Mars/Olympus', '2026-10-14 09:00Z')$$,
  '22023', null, 'a zone Postgres does not know raises');

-- User 3's library: a live deck with cards a (state, two answers, one fuzzed), b (no state), c
-- (deleted), d (no answer) and e (one answer); and a deleted deck with card f.
insert into public.decks (id, user_id, name, created_at, updated_at, deleted_at) values
  ('d0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 'Live',
    now(), now(), null),
  ('d0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000003', '',
    now(), now(), now());
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at, deleted_at)
select pg_temp.card(name), '00000000-0000-4000-8000-000000000003', deck::uuid, '[]', '[]',
  case when deleted then '' else name end, 'manual', now(), now(), case when deleted then now() end
from (values
  ('a', 'd0000000-0000-4000-8000-000000000001', false),
  ('b', 'd0000000-0000-4000-8000-000000000001', false),
  ('c', 'd0000000-0000-4000-8000-000000000001', true),
  ('d', 'd0000000-0000-4000-8000-000000000001', false),
  ('e', 'd0000000-0000-4000-8000-000000000001', false),
  ('f', 'd0000000-0000-4000-8000-000000000002', false)) as v (name, deck, deleted);
insert into public.card_states
  (user_id, card_id, stability, difficulty, last_review, due, updated_at)
select '00000000-0000-4000-8000-000000000003', pg_temp.card(name), 3, 5, now(), now(), now()
from (values ('a'), ('c'), ('f')) as v (name);
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'a', '2026-10-12 09:00Z', true, 0.25);
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'a', '2026-10-10 09:00Z', false);
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'b', '2026-10-11 09:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'c', '2026-10-11 09:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'e', '2026-10-12 09:00Z');
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'f', '2026-10-11 09:00Z');
select is(
  pg_temp.cards_of('00000000-0000-4000-8000-000000000003'),
  array[
    'a 3 {again,good} {"2026-10-10 09:00:00+00","2026-10-12 09:00:00+00"} {NULL,0.25}',
    'b  {good} {"2026-10-11 09:00:00+00"} {NULL}',
    'e  {good} {"2026-10-12 09:00:00+00"} {NULL}'],
  'each live card of a live deck with an answer: its state or none, and its answers oldest first with their fuzz factors');

-- Controls: the cards left out are left out for the reason named.
update public.cards set deleted_at = null, card_key = 'c' where id = pg_temp.card('c');
select is(
  array_length(pg_temp.cards_of('00000000-0000-4000-8000-000000000003'), 1), 4,
  'control: card c restored is read');
update public.decks set deleted_at = null, name = 'Back'
  where id = 'd0000000-0000-4000-8000-000000000002';
select is(
  array_length(pg_temp.cards_of('00000000-0000-4000-8000-000000000003'), 1), 5,
  'control: card f''s deck restored, f is read');
select pg_temp.answer('00000000-0000-4000-8000-000000000003', 'd', '2026-10-12 09:00Z');
select is(
  array_length(pg_temp.cards_of('00000000-0000-4000-8000-000000000003'), 1), 6,
  'control: card d answered once is read');

select is(pg_temp.cards_of('00000000-0000-4000-8000-000000000001'), null,
  'another user''s cards are not read');

select function_privs_are('public', 'study_record_days',
  array['text', 'timestamp with time zone'], 'authenticated', array['EXECUTE'],
  'authenticated may read its study days');
select function_privs_are('public', 'study_record_days',
  array['text', 'timestamp with time zone'], 'anon', array[]::text[], 'anon may not');
select function_privs_are('public', 'study_record_cards', array[]::text[],
  'authenticated', array['EXECUTE'], 'authenticated may read its cards');
select function_privs_are('public', 'study_record_cards', array[]::text[],
  'anon', array[]::text[], 'anon may not read cards');
select results_eq(
  $$select prosecdef, provolatile = 's', proconfig = array['search_path=""'] from pg_proc
    where oid in ('public.study_record_days(text, timestamptz)'::regprocedure,
      'public.study_record_cards()'::regprocedure)$$,
  $$values (false, true, true), (false, true, true)$$,
  'both run as the caller, are stable, and set an empty search_path');

select * from finish();
rollback;
