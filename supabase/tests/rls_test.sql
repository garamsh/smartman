-- Row-level security: user A reaches its own rows in every table and none of user B's.
begin;
select plan(20);

-- Two users, A and B, each owning one row in every table.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'A', now(), now()),
  ('d0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'B', now(), now());
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at) values
  ('c0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000a',
   '[{"type":"text","payload":"a"}]', '[]', 'a', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-00000000000b',
   '[{"type":"text","payload":"b"}]', '[]', 'b', 'manual', now(), now());
insert into public.reviews
  (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at) values
  ('e0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000a', 'good', now(), 1000, now()),
  ('e0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-00000000000b', 'good', now(), 1000, now());
insert into public.card_states
  (user_id, card_id, stability, difficulty, last_review, due, updated_at) values
  ('00000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000a', 1, 5, now(), now(), now()),
  ('00000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-00000000000b', 1, 5, now(), now(), now());

select results_eq(
  $$select count(*) from public.decks union all select count(*) from public.cards
    union all select count(*) from public.reviews union all select count(*) from public.card_states$$,
  array[2::bigint, 2, 2, 2],
  'the fixture holds two rows in each of the four tables'
);

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

-- select
select results_eq('select id from public.decks', array['d0000000-0000-4000-8000-00000000000a']::uuid[], 'A selects its own deck and not B''s');
select results_eq('select id from public.cards', array['c0000000-0000-4000-8000-00000000000a']::uuid[], 'A selects its own card and not B''s');
select results_eq('select id from public.reviews', array['e0000000-0000-4000-8000-00000000000a']::uuid[], 'A selects its own review and not B''s');
select results_eq('select card_id from public.card_states', array['c0000000-0000-4000-8000-00000000000a']::uuid[],
  'A selects its own card state and not B''s');

-- insert
select throws_ok(
  $$insert into public.decks (id, user_id, name, created_at, updated_at)
    values ('d0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000b', 'X', now(), now())$$,
  '42501', null, 'A cannot insert a deck owned by B');
select lives_ok(
  $$insert into public.decks (id, user_id, name, created_at, updated_at)
    values ('d0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'Y', now(), now())$$,
  'A inserts a deck it owns');
select throws_ok(
  $$insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at)
    values ('c0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-00000000000b', '[]', '[]', 'x', 'manual', now(), now())$$,
  '42501', null, 'A cannot insert a card owned by B');
select lives_ok(
  $$insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at)
    values ('c0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000a', '[]', '[]', 'y', 'manual', now(), now())$$,
  'A inserts a card it owns');
select throws_ok(
  $$insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at)
    values ('e0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-00000000000b', 'again', now(), 0, now())$$,
  '42501', null, 'A cannot insert a review owned by B');
select lives_ok(
  $$insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at)
    values ('e0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000002', 'again', now(), 0, now())$$,
  'A inserts a review it owns');
select throws_ok(
  $$insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due, updated_at)
    values ('00000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-00000000000b', 2, 5, now(), now(), now())$$,
  '42501', null, 'A cannot insert a card state owned by B');
select lives_ok(
  $$insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due, updated_at)
    values ('00000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000002', 2, 5, now(), now(), now())$$,
  'A inserts a card state it owns');

-- update: A's statements name both users' rows; only A's change.
update public.decks set name = 'changed' where id in ('d0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000b');
update public.cards set card_key = 'changed' where id in ('c0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000b');
update public.reviews set rating = 'again' where id in ('e0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-00000000000b');
update public.card_states set stability = 9 where card_id in ('c0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000b');

reset role;
select results_eq(
  $$select id, name from public.decks where id in ('d0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000b') order by id$$,
  $$values ('d0000000-0000-4000-8000-00000000000a'::uuid, 'changed'), ('d0000000-0000-4000-8000-00000000000b'::uuid, 'B')$$,
  'A updates its own deck and not B''s');
select results_eq(
  $$select id, card_key from public.cards where id in ('c0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000b') order by id$$,
  $$values ('c0000000-0000-4000-8000-00000000000a'::uuid, 'changed'), ('c0000000-0000-4000-8000-00000000000b'::uuid, 'b')$$,
  'A updates its own card and not B''s');
select results_eq(
  $$select id, rating from public.reviews where id in ('e0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-00000000000b') order by id$$,
  $$values ('e0000000-0000-4000-8000-00000000000a'::uuid, 'again'), ('e0000000-0000-4000-8000-00000000000b'::uuid, 'good')$$,
  'A updates its own review''s rating and not B''s');
select results_eq(
  $$select card_id, stability from public.card_states where card_id in ('c0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000b') order by card_id$$,
  $$values ('c0000000-0000-4000-8000-00000000000a'::uuid, 9::double precision), ('c0000000-0000-4000-8000-00000000000b'::uuid, 1::double precision)$$,
  'A updates its own card state and not B''s');

-- delete: each statement names both users' rows; only A's go. Reviews are covered in reviews_test.sql.
set local role authenticated;
delete from public.card_states where card_id in ('c0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000b');
reset role;
select results_eq(
  $$select user_id::text || ':' || card_id from public.card_states order by 1$$,
  $$values ('00000000-0000-4000-8000-00000000000a:c0000000-0000-4000-8000-000000000002'), ('00000000-0000-4000-8000-00000000000b:c0000000-0000-4000-8000-00000000000b')$$,
  'A deletes its own card state and not B''s');

set local role authenticated;
delete from public.cards where id in ('c0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-00000000000b');
reset role;
select results_eq(
  $$select id from public.cards order by id$$,
  $$values ('c0000000-0000-4000-8000-00000000000a'::uuid), ('c0000000-0000-4000-8000-00000000000b'::uuid)$$,
  'A deletes its own card and not B''s');

set local role authenticated;
delete from public.decks where id in ('d0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-00000000000b');
reset role;
select results_eq(
  $$select id from public.decks order by id$$,
  $$values ('d0000000-0000-4000-8000-00000000000a'::uuid), ('d0000000-0000-4000-8000-00000000000b'::uuid)$$,
  'A deletes its own deck and not B''s');

select * from finish();
rollback;
