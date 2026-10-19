-- Account deletion: deleting a user from auth.users, as the delete-account function does, leaves
-- no row holding that user's id in any table, and leaves every other user's rows.
begin;
select plan(7);

-- A and B each own a row in every table, report, block and copy each other, and B holds a card
-- copied from A's deck.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
insert into public.profiles (user_id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Alice'),
  ('00000000-0000-4000-8000-00000000000b', 'Bob');
insert into public.decks
  (id, user_id, name, visibility, published_at, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'A', 'public', now(), now(), now()),
  ('d0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'B', 'public', now(), now(), now());
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, origin_deck_id, created_at, updated_at)
  values
  ('c0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000a', '[]', '[]', 'a', 'manual', null,
   now(), now()),
  ('c0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-00000000000b', '[]', '[]', 'b', 'manual', null,
   now(), now()),
  ('c0000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-00000000000b', '[]', '[]', 'c', 'copy',
   'd0000000-0000-4000-8000-00000000000a', now(), now());
insert into public.reviews
  (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at) values
  ('e0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000a', 'good', now(), 1000, now()),
  ('e0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-00000000000b', 'good', now(), 1000, now());
insert into public.card_states
  (user_id, card_id, stability, difficulty, last_review, due, updated_at) values
  ('00000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000a', 1, 5, now(), now(), now()),
  ('00000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-00000000000b', 1, 5, now(), now(), now());
insert into public.extraction_usage (user_id) values
  ('00000000-0000-4000-8000-00000000000a'),
  ('00000000-0000-4000-8000-00000000000b');
insert into public.deck_reports (deck_id, reporter_id, reason) values
  ('d0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000a', 'spam'),
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000b', 'spam');
insert into public.user_blocks (blocker_id, blocked_id) values
  ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000b'),
  ('00000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000a');
insert into public.deck_copies (deck_id, user_id) values
  ('d0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000a'),
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000b');

-- Every uuid column of every table in public, as "table.column", that holds [who] in some row.
create function pg_temp.columns_holding(who uuid) returns setof text language plpgsql as $$
declare
  col record;
  found boolean;
begin
  for col in
    select c.table_name, c.column_name
    from information_schema.columns as c
    join information_schema.tables as t using (table_schema, table_name)
    where c.table_schema = 'public' and t.table_type = 'BASE TABLE' and c.data_type = 'uuid'
    order by 1, 2
  loop
    execute format('select exists (select 1 from public.%I where %I = $1)',
      col.table_name, col.column_name) into found using who;
    if found then
      return next col.table_name || '.' || col.column_name;
    end if;
  end loop;
end;
$$;

select results_eq(
  $$select tablename::text collate "default" from pg_tables where schemaname = 'public' order by 1$$,
  array['card_states', 'cards', 'deck_copies', 'deck_reports', 'decks', 'extraction_usage',
    'profiles', 'reviews', 'user_blocks'],
  'these are every table in public, so a new table fails here until this test covers it');

select is_empty(
  $$select conrelid::regclass::text from pg_constraint
    where contype = 'f' and connamespace = 'public'::regnamespace
      and confrelid = 'auth.users'::regclass and confdeltype <> 'c'$$,
  'every reference from public to auth.users deletes with the user');

select results_eq(
  $$select pg_temp.columns_holding('00000000-0000-4000-8000-00000000000a')$$,
  array['card_states.user_id', 'cards.user_id', 'deck_copies.user_id', 'deck_reports.reporter_id',
    'decks.user_id', 'extraction_usage.user_id', 'profiles.user_id', 'reviews.user_id', 'user_blocks.blocked_id',
    'user_blocks.blocker_id'],
  'before deletion, A''s id is in every table, in each column that can hold it');

delete from auth.users where id = '00000000-0000-4000-8000-00000000000a';

select is_empty(
  $$select pg_temp.columns_holding('00000000-0000-4000-8000-00000000000a')$$,
  'after deletion, no row in any table holds A''s id');

select is_empty(
  $$select deck_id from public.deck_reports where deck_id = 'd0000000-0000-4000-8000-00000000000a'$$,
  'B''s report on A''s deck went with the deck');

select results_eq(
  $$select pg_temp.columns_holding('00000000-0000-4000-8000-00000000000b')$$,
  array['card_states.user_id', 'cards.user_id', 'decks.user_id', 'extraction_usage.user_id',
    'profiles.user_id', 'reviews.user_id'],
  'B keeps its own rows; its report on and copy of A''s deck and its block of A go, and nothing else');

select results_eq(
  $$select id, origin_deck_id from public.cards order by id$$,
  $$values ('c0000000-0000-4000-8000-00000000000b'::uuid, null::uuid), ('c0000000-0000-4000-8000-000000000011'::uuid, 'd0000000-0000-4000-8000-00000000000a'::uuid)$$,
  'the card B copied from A''s deck stays B''s');

select * from finish();
rollback;
