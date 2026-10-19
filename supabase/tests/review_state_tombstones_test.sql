-- Reviews and card states have no tombstone (ADR 0077): their deleted_at, the reviews delete policy
-- and the card state purge index are gone, while decks and cards keep theirs; and the guard the
-- migration ran before dropping the columns refuses a table holding a tombstone.
begin;
select plan(9);

select hasnt_column('public', 'reviews', 'deleted_at', 'reviews has no deleted_at');
select hasnt_column('public', 'card_states', 'deleted_at', 'card_states has no deleted_at');
select has_column('public', 'decks', 'deleted_at', 'control: decks keeps its tombstone');
select has_column('public', 'cards', 'deleted_at', 'control: cards keeps its tombstone');

select policies_are('public', 'reviews',
  array['reviews_select', 'reviews_insert', 'reviews_update', 'reviews_not_suspended_insert',
    'reviews_not_suspended_update'],
  'reviews has no delete policy, since no client may delete a review');

-- The guard: a table with no tombstone passes, one holding a tombstone raises.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'guard@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at) values
  ('d0000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1', 'Live', now(),
    now());
select is(
  (select count(*) from public.decks where deleted_at is not null), 0::bigint,
  'the setup holds no deck tombstone');
select lives_ok(
  $$select private.require_no_tombstone('public.decks')$$,
  'control: the guard passes a table whose every deleted_at is null');
update public.decks set deleted_at = now() where id = 'd0000000-0000-4000-8000-0000000000a1';
select throws_ok(
  $$select private.require_no_tombstone('public.decks')$$,
  'P0001', 'public.decks holds a tombstone, which dropping deleted_at would lose',
  'the guard refuses a table holding a tombstone');

select function_privs_are('private', 'require_no_tombstone', array['regclass'], 'authenticated',
  '{}', 'no client may call the guard');

select * from finish();
rollback;
