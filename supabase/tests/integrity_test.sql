-- Integrity: a card's deck, and a review's or card state's card, belong to the row's own user.
begin;
select plan(9);

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

-- Each row is A's own, so row-level security accepts it; only the reference differs.
select throws_ok(
  $$insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at)
    values ('card-x', '00000000-0000-4000-8000-00000000000a', 'deck-b', '[]', '[]', 'x', 'manual', now(), now())$$,
  '23503', null, 'A cannot put a card in B''s deck');
select lives_ok(
  $$insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at)
    values ('card-y', '00000000-0000-4000-8000-00000000000a', 'deck-a', '[]', '[]', 'y', 'manual', now(), now())$$,
  'A puts a card in its own deck');
select throws_ok(
  $$update public.cards set deck_id = 'deck-b' where id = 'card-a'$$,
  '23503', null, 'A cannot move its card into B''s deck');
select throws_ok(
  $$insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at)
    values ('review-x', '00000000-0000-4000-8000-00000000000a', 'card-b', 'good', now(), 0, now())$$,
  '23503', null, 'A cannot review B''s card');
select lives_ok(
  $$insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at)
    values ('review-y', '00000000-0000-4000-8000-00000000000a', 'card-y', 'good', now(), 0, now())$$,
  'A reviews its own card');
select throws_ok(
  $$insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due, updated_at)
    values ('00000000-0000-4000-8000-00000000000a', 'card-b', 1, 5, now(), now(), now())$$,
  '23503', null, 'A cannot store a state for B''s card');
select lives_ok(
  $$insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due, updated_at)
    values ('00000000-0000-4000-8000-00000000000a', 'card-y', 1, 5, now(), now(), now())$$,
  'A stores a state for its own card');
select throws_ok(
  $$insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at)
    values ('card-z', '00000000-0000-4000-8000-00000000000a', 'deck-a', '{"type":"text"}', '[]', 'z', 'manual', now(), now())$$,
  '23514', null, 'a card side that is not a list of blocks is refused');

select * from finish();
rollback;
