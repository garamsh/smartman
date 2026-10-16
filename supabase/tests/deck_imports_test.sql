-- Deck imports: a public deck's import_count counts each user who copied it once, never its
-- owner, adds to a count recorded before copies were kept per user, and clients reach no row of
-- deck_imports.
begin;
select plan(7);

-- A owns a public deck and an older one copied five times before copies were kept per user;
-- B and C copy them.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com'),
  ('00000000-0000-4000-8000-00000000000c', 'c@example.com');
insert into public.decks
  (id, user_id, name, visibility, published_at, import_count, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'French', 'public', now(), 0, now(), now()),
  ('d0000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-00000000000a', 'German', 'public', now(), 5, now(), now());

select results_eq(
  $$select id, import_count from public.decks order by id$$,
  $$values ('d0000000-0000-4000-8000-000000000006'::uuid, 5), ('d0000000-0000-4000-8000-00000000000a'::uuid, 0)$$,
  'the fixture holds a deck copied by no one and one with five earlier copies');

-- Two copies of one deck by the same user meet on this key, so concurrent copies by that user
-- insert one row between them.
select col_is_pk('public', 'deck_imports', array['deck_id', 'user_id'],
  'a deck_imports row is unique per deck and user');

-- Copies a deck as a user, then records the answer and the deck's count as the table owner.
create temporary table counts (step integer, copier text, accepted boolean, import_count integer);
create function pg_temp.copy(step integer, copier text, copier_id uuid, deck uuid) returns void
language plpgsql as $$
declare
  accepted boolean;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', copier_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  accepted := public.record_deck_import(deck);
  reset role;
  insert into counts
    select step, copier, accepted, d.import_count from public.decks as d where d.id = deck;
end;
$$;

select pg_temp.copy(1, 'B', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-00000000000a');
select pg_temp.copy(2, 'B again', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-00000000000a');
select pg_temp.copy(3, 'A, the owner', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000a');
select pg_temp.copy(4, 'C', '00000000-0000-4000-8000-00000000000c', 'd0000000-0000-4000-8000-00000000000a');

select results_eq(
  $$select copier, accepted, import_count from counts order by step$$,
  $$values ('B', true, 1), ('B again', true, 1), ('A, the owner', true, 1), ('C', true, 2)$$,
  'every copy is accepted; B''s second copy and the owner''s copy add nothing, C''s adds one');

select results_eq(
  $$select deck_id, user_id::text from public.deck_imports order by user_id$$,
  $$values ('d0000000-0000-4000-8000-00000000000a'::uuid, '00000000-0000-4000-8000-00000000000b'),
    ('d0000000-0000-4000-8000-00000000000a'::uuid, '00000000-0000-4000-8000-00000000000c')$$,
  'deck_imports holds one row for each user who copied the deck, and none for its owner');

-- A count kept before copies were recorded per user is added to, not recounted from the rows.
select pg_temp.copy(5, 'B', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-000000000006');
select pg_temp.copy(6, 'B again', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-000000000006');
select results_eq(
  $$select copier, import_count from counts where step > 4 order by step$$,
  $$values ('B', 6), ('B again', 6)$$,
  'B''s copies of a deck with five earlier copies make it six, once');

-- Clients reach deck_imports only through record_deck_import, which wrote the rows above.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select throws_ok(
  $$select * from public.deck_imports$$,
  '42501', null, 'B cannot read deck_imports');
select throws_ok(
  $$insert into public.deck_imports (deck_id, user_id)
    values ('d0000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-00000000000c')$$,
  '42501', null, 'B cannot write deck_imports');

select * from finish();
rollback;
