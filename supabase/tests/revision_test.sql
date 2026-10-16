-- revision: the server sets it from one sequence on every insert and update, whatever the client sends.
begin;
select plan(10);

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

-- Revisions before A's writes, read as the table owner.
create temporary table before_revision on commit drop as
  select 'deck' as kind, revision from public.decks where id = 'd0000000-0000-4000-8000-00000000000a'
  union all select 'card', revision from public.cards where id = 'c0000000-0000-4000-8000-00000000000a'
  union all select 'review', revision from public.reviews where id = 'e0000000-0000-4000-8000-00000000000a'
  union all select 'card_state', revision from public.card_states where card_id = 'c0000000-0000-4000-8000-00000000000a';
grant select on before_revision to authenticated;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$insert into public.decks (id, user_id, name, created_at, updated_at, revision)
    values ('d0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'Y', now(), now(), 1)$$,
  'A inserts a deck sending its own revision');

reset role;
select results_eq(
  $$select revision from public.decks where id = 'd0000000-0000-4000-8000-000000000002'$$,
  $$select last_value from private.revision$$,
  'an inserted row takes the sequence''s next value, not the one the client sent');

set local role authenticated;
update public.decks set name = 'changed' where id = 'd0000000-0000-4000-8000-00000000000a';
update public.cards set card_key = 'changed' where id = 'c0000000-0000-4000-8000-00000000000a';
update public.reviews set rating = 'again' where id = 'e0000000-0000-4000-8000-00000000000a';
update public.card_states set stability = 9 where card_id = 'c0000000-0000-4000-8000-00000000000a';

reset role;
select cmp_ok(
  (select revision from public.decks where id = 'd0000000-0000-4000-8000-00000000000a'), '>',
  (select revision from before_revision where kind = 'deck'),
  'updating a deck raises its revision');
select cmp_ok(
  (select revision from public.cards where id = 'c0000000-0000-4000-8000-00000000000a'), '>',
  (select revision from before_revision where kind = 'card'),
  'updating a card raises its revision');
select cmp_ok(
  (select revision from public.reviews where id = 'e0000000-0000-4000-8000-00000000000a'), '>',
  (select revision from before_revision where kind = 'review'),
  'updating a review raises its revision');
select cmp_ok(
  (select revision from public.card_states where card_id = 'c0000000-0000-4000-8000-00000000000a'), '>',
  (select revision from before_revision where kind = 'card_state'),
  'updating a card state raises its revision');

set local role authenticated;
update public.decks set revision = 1 where id = 'd0000000-0000-4000-8000-00000000000a';

reset role;
select results_eq(
  $$select revision from public.decks where id = 'd0000000-0000-4000-8000-00000000000a'$$,
  $$select last_value from private.revision$$,
  'an update that sets revision gets the sequence''s next value instead');

set local role authenticated;
select throws_ok(
  $$update public.reviews set revision = 1 where id = 'e0000000-0000-4000-8000-00000000000a'$$,
  '42501', null, 'A cannot name revision in a review update');
select throws_ok(
  $$select nextval('private.revision')$$,
  '42501', null, 'A cannot draw from the revision sequence');

select * from finish();
rollback;
