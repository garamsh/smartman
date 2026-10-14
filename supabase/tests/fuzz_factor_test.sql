-- A review's fuzz factor is checked to [0, 1), inserted by its client, and never updated by one.
begin;
select plan(7);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at) values
  ('deck-a', '00000000-0000-4000-8000-00000000000a', 'A', now(), now());
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at) values
  ('card-a', '00000000-0000-4000-8000-00000000000a', 'deck-a',
   '[{"type":"text","payload":"a"}]', '[]', 'a', 'manual', now(), now());

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

select throws_ok(
  $$insert into public.reviews (id, card_id, rating, reviewed_at, duration_ms, updated_at, fuzz_factor)
    values ('below', 'card-a', 'good', now(), 1000, now(), -0.1)$$,
  '23514', null, 'a fuzz factor below 0 is refused');
select throws_ok(
  $$insert into public.reviews (id, card_id, rating, reviewed_at, duration_ms, updated_at, fuzz_factor)
    values ('one', 'card-a', 'good', now(), 1000, now(), 1)$$,
  '23514', null, 'a fuzz factor of 1 is refused');
select lives_ok(
  $$insert into public.reviews (id, card_id, rating, reviewed_at, duration_ms, updated_at, fuzz_factor)
    values ('least', 'card-a', 'good', now(), 1000, now(), 0),
           ('greatest', 'card-a', 'good', now(), 1000, now(), 0.9999),
           ('unfuzzed', 'card-a', 'good', now(), 1000, now(), null)$$,
  'the client inserts the ends of the range, and no factor');
select throws_ok(
  $$update public.reviews set fuzz_factor = 0.5 where id = 'least'$$,
  '42501', null, 'the client cannot change a review''s fuzz factor');
-- Control: the same client may change the review's rating, so the refusal above is the column's.
select lives_ok(
  $$update public.reviews set rating = 'again', updated_at = now() where id = 'least'$$,
  'the client changes the same review''s rating');

reset role;
select results_eq(
  $$select id, fuzz_factor from public.reviews order by id$$,
  $$values ('greatest', 0.9999::double precision), ('least', 0::double precision),
           ('unfuzzed', null::double precision)$$,
  'the three reviews hold the factors they were inserted with');
select results_eq(
  $$select rating from public.reviews where id = 'least'$$,
  $$values ('again')$$,
  'the rating change took effect');

select * from finish();
rollback;
