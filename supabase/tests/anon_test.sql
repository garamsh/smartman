-- The anon role reaches no table: every statement it sends is refused.
begin;
select plan(10);

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

select results_eq(
  $$select (select count(*) from public.decks) + (select count(*) from public.cards)
    + (select count(*) from public.reviews) + (select count(*) from public.card_states)$$,
  array[4::bigint],
  'an authenticated user reads its own row in each table');

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok('select * from public.decks', '42501', null, 'anon cannot select decks');
select throws_ok('select * from public.cards', '42501', null, 'anon cannot select cards');
select throws_ok('select * from public.reviews', '42501', null, 'anon cannot select reviews');
select throws_ok('select * from public.card_states', '42501', null, 'anon cannot select card states');
select throws_ok(
  $$insert into public.decks (id, user_id, name, created_at, updated_at)
    values ('deck-x', '00000000-0000-4000-8000-00000000000a', 'X', now(), now())$$,
  '42501', null, 'anon cannot insert a deck');
select throws_ok($$update public.cards set card_key = 'x'$$, '42501', null, 'anon cannot update cards');
select throws_ok('delete from public.card_states', '42501', null, 'anon cannot delete card states');

reset role;
select results_eq(
  $$select count(*) from public.decks union all select count(*) from public.cards
    union all select count(*) from public.reviews union all select count(*) from public.card_states$$,
  array[2::bigint, 2, 2, 2],
  'every row remains after anon''s statements');

select * from finish();
rollback;
