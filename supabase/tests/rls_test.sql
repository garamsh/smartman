-- Row-level security: user A reaches its own rows in every table and none of user B's.
begin;
select plan(20);

-- Two users, A and B, each owning one row in every table.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at) values
  ('deck-a', '00000000-0000-4000-8000-00000000000a', 'A', now(), now()),
  ('deck-b', '00000000-0000-4000-8000-00000000000b', 'B', now(), now());
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at) values
  ('card-a', '00000000-0000-4000-8000-00000000000a', 'deck-a',
   '[{"type":"text","payload":"a"}]', '[]', 'a', 'manual', now(), now()),
  ('card-b', '00000000-0000-4000-8000-00000000000b', 'deck-b',
   '[{"type":"text","payload":"b"}]', '[]', 'b', 'manual', now(), now());
insert into public.reviews
  (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at) values
  ('review-a', '00000000-0000-4000-8000-00000000000a', 'card-a', 'good', now(), 1000, now()),
  ('review-b', '00000000-0000-4000-8000-00000000000b', 'card-b', 'good', now(), 1000, now());
insert into public.card_states
  (user_id, card_id, stability, difficulty, last_review, due, updated_at) values
  ('00000000-0000-4000-8000-00000000000a', 'card-a', 1, 5, now(), now(), now()),
  ('00000000-0000-4000-8000-00000000000b', 'card-b', 1, 5, now(), now(), now());

select results_eq(
  $$select count(*) from public.decks union all select count(*) from public.cards
    union all select count(*) from public.reviews union all select count(*) from public.card_states$$,
  array[2::bigint, 2, 2, 2],
  'the fixture holds two rows in each of the four tables'
);

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

-- select
select results_eq('select id from public.decks', array['deck-a'], 'A selects its own deck and not B''s');
select results_eq('select id from public.cards', array['card-a'], 'A selects its own card and not B''s');
select results_eq('select id from public.reviews', array['review-a'], 'A selects its own review and not B''s');
select results_eq('select card_id from public.card_states', array['card-a'],
  'A selects its own card state and not B''s');

-- insert
select throws_ok(
  $$insert into public.decks (id, user_id, name, created_at, updated_at)
    values ('deck-x', '00000000-0000-4000-8000-00000000000b', 'X', now(), now())$$,
  '42501', null, 'A cannot insert a deck owned by B');
select lives_ok(
  $$insert into public.decks (id, user_id, name, created_at, updated_at)
    values ('deck-y', '00000000-0000-4000-8000-00000000000a', 'Y', now(), now())$$,
  'A inserts a deck it owns');
select throws_ok(
  $$insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at)
    values ('card-x', '00000000-0000-4000-8000-00000000000b', 'deck-b', '[]', '[]', 'x', 'manual', now(), now())$$,
  '42501', null, 'A cannot insert a card owned by B');
select lives_ok(
  $$insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at)
    values ('card-y', '00000000-0000-4000-8000-00000000000a', 'deck-a', '[]', '[]', 'y', 'manual', now(), now())$$,
  'A inserts a card it owns');
select throws_ok(
  $$insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at)
    values ('review-x', '00000000-0000-4000-8000-00000000000b', 'card-b', 'again', now(), 0, now())$$,
  '42501', null, 'A cannot insert a review owned by B');
select lives_ok(
  $$insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at)
    values ('review-y', '00000000-0000-4000-8000-00000000000a', 'card-y', 'again', now(), 0, now())$$,
  'A inserts a review it owns');
select throws_ok(
  $$insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due, updated_at)
    values ('00000000-0000-4000-8000-00000000000b', 'card-b', 2, 5, now(), now(), now())$$,
  '42501', null, 'A cannot insert a card state owned by B');
select lives_ok(
  $$insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due, updated_at)
    values ('00000000-0000-4000-8000-00000000000a', 'card-y', 2, 5, now(), now(), now())$$,
  'A inserts a card state it owns');

-- update: A's statements name both users' rows; only A's change.
update public.decks set name = 'changed' where id in ('deck-a', 'deck-b');
update public.cards set card_key = 'changed' where id in ('card-a', 'card-b');
update public.reviews set rating = 'again' where id in ('review-a', 'review-b');
update public.card_states set stability = 9 where card_id in ('card-a', 'card-b');

reset role;
select results_eq(
  $$select id, name from public.decks where id in ('deck-a', 'deck-b') order by id$$,
  $$values ('deck-a', 'changed'), ('deck-b', 'B')$$,
  'A updates its own deck and not B''s');
select results_eq(
  $$select id, card_key from public.cards where id in ('card-a', 'card-b') order by id$$,
  $$values ('card-a', 'changed'), ('card-b', 'b')$$,
  'A updates its own card and not B''s');
select results_eq(
  $$select id, rating from public.reviews where id in ('review-a', 'review-b') order by id$$,
  $$values ('review-a', 'again'), ('review-b', 'good')$$,
  'A updates its own review''s rating and not B''s');
select results_eq(
  $$select card_id, stability from public.card_states where card_id in ('card-a', 'card-b') order by card_id$$,
  $$values ('card-a', 9::double precision), ('card-b', 1::double precision)$$,
  'A updates its own card state and not B''s');

-- delete: each statement names both users' rows; only A's go. Reviews are covered in reviews_test.sql.
set local role authenticated;
delete from public.card_states where card_id in ('card-a', 'card-b');
reset role;
select results_eq(
  $$select user_id::text || ':' || card_id from public.card_states order by 1$$,
  $$values ('00000000-0000-4000-8000-00000000000a:card-y'), ('00000000-0000-4000-8000-00000000000b:card-b')$$,
  'A deletes its own card state and not B''s');

set local role authenticated;
delete from public.cards where id in ('card-y', 'card-b');
reset role;
select results_eq(
  $$select id from public.cards order by id$$,
  $$values ('card-a'), ('card-b')$$,
  'A deletes its own card and not B''s');

set local role authenticated;
delete from public.decks where id in ('deck-y', 'deck-b');
reset role;
select results_eq(
  $$select id from public.decks order by id$$,
  $$values ('deck-a'), ('deck-b')$$,
  'A deletes its own deck and not B''s');

select * from finish();
rollback;
