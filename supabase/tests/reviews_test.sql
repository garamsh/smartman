-- Reviews are insert-only for clients, except their rating and edit time, which a toggle changes.
begin;
select plan(7);

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

select lives_ok(
  $$update public.reviews set rating = 'again', updated_at = now() where id = 'e0000000-0000-4000-8000-00000000000a'$$,
  'A changes its own review''s rating and edit time');
select throws_ok(
  $$update public.reviews set reviewed_at = now() where id = 'e0000000-0000-4000-8000-00000000000a'$$,
  '42501', null, 'A cannot change its own review''s time');
select throws_ok(
  $$update public.reviews set duration_ms = 0 where id = 'e0000000-0000-4000-8000-00000000000a'$$,
  '42501', null, 'A cannot change its own review''s duration');
select throws_ok(
  $$delete from public.reviews where id = 'e0000000-0000-4000-8000-00000000000a'$$,
  '42501', null, 'A cannot delete its own review');
select throws_ok(
  $$delete from public.reviews where id = 'e0000000-0000-4000-8000-00000000000b'$$,
  '42501', null, 'A cannot delete B''s review');

reset role;
select results_eq(
  $$select id, rating from public.reviews order by id$$,
  $$values ('e0000000-0000-4000-8000-00000000000a'::uuid, 'again'), ('e0000000-0000-4000-8000-00000000000b'::uuid, 'good')$$,
  'both reviews remain, with only A''s rating changed');

select * from finish();
rollback;
