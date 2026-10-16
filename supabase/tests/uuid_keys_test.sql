-- Keys: every synced id and every reference to one is uuid, the keys and functions that name them
-- take uuid, and a report still takes the lock key its deck's id took as text.
begin;
select plan(26);

select col_type_is('public', 'decks', 'id', 'uuid', 'decks.id is uuid');
select col_type_is('public', 'cards', 'id', 'uuid', 'cards.id is uuid');
select col_type_is('public', 'cards', 'deck_id', 'uuid', 'cards.deck_id is uuid');
select col_type_is('public', 'cards', 'origin_deck_id', 'uuid', 'cards.origin_deck_id is uuid');
select col_type_is('public', 'reviews', 'id', 'uuid', 'reviews.id is uuid');
select col_type_is('public', 'reviews', 'card_id', 'uuid', 'reviews.card_id is uuid');
select col_type_is('public', 'card_states', 'card_id', 'uuid', 'card_states.card_id is uuid');
select col_type_is('public', 'deck_reports', 'deck_id', 'uuid', 'deck_reports.deck_id is uuid');
select col_type_is('public', 'deck_imports', 'deck_id', 'uuid', 'deck_imports.deck_id is uuid');
-- Control: the one id that is not synced keeps its type, so the checks above read each column's own.
select col_type_is('public', 'extraction_usage', 'id', 'bigint', 'extraction_usage.id stays an identity');

-- No id takes a default: a client that sends none is refused rather than given one.
select col_hasnt_default('public', 'decks', 'id', 'decks.id has no default');
select col_hasnt_default('public', 'cards', 'id', 'cards.id has no default');
select col_hasnt_default('public', 'reviews', 'id', 'reviews.id has no default');

select fk_ok('public', 'cards', array['user_id', 'deck_id'], 'public', 'decks', array['user_id', 'id'],
  'a card''s deck is its own user''s');
select fk_ok('public', 'reviews', array['user_id', 'card_id'], 'public', 'cards', array['user_id', 'id'],
  'a review''s card is its own user''s');
select fk_ok('public', 'card_states', array['user_id', 'card_id'], 'public', 'cards', array['user_id', 'id'],
  'a card state''s card is its own user''s');
select fk_ok('public', 'deck_reports', 'deck_id', 'public', 'decks', 'id', 'a report names its deck');
select fk_ok('public', 'deck_imports', 'deck_id', 'public', 'decks', 'id', 'an import names its deck');

select is(
  pg_get_function_result('public.list_public_decks(text, text, integer, integer)'::regprocedure),
  'TABLE(id uuid, user_id uuid, name text, description text, display_name text, card_count bigint, '
    || 'import_count integer, published_at timestamp with time zone)',
  'list_public_decks returns uuid ids');
select has_function('public', 'record_deck_import', array['uuid'], 'record_deck_import takes a uuid');
select hasnt_function('public', 'record_deck_import', array['text'], 'record_deck_import takes no text');
select function_privs_are('public', 'record_deck_import', array['uuid'], 'authenticated', array['EXECUTE'],
  'authenticated may record an import');
select function_privs_are('public', 'record_deck_import', array['uuid'], 'anon', array[]::text[],
  'anon may not record an import');

-- Whether this transaction holds the advisory lock that hide_reported_deck keys by the deck's id
-- as text, seeded with 2: the key it took before the ids were uuid.
create function pg_temp.holds_report_lock(deck_id text) returns boolean language sql as $$
  select exists (
    select from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and granted
      and classid::bigint = (hashtextextended(deck_id, 2) >> 32) & 4294967295
      and objid::bigint = hashtextextended(deck_id, 2) & 4294967295
      and objsubid = 1
  )
$$;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com'),
  ('00000000-0000-4000-8000-00000000000c', 'c@example.com'),
  ('00000000-0000-4000-8000-00000000000d', 'd@example.com');
insert into public.decks
  (id, user_id, name, visibility, published_at, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000007a', '00000000-0000-4000-8000-00000000000a', 'French', 'public', now(),
   now(), now());
select ok(not pg_temp.holds_report_lock('d0000000-0000-4000-8000-00000000007a'),
  'before any report, the transaction holds no report lock on the deck');
insert into public.deck_reports (deck_id, reporter_id, reason) values
  ('d0000000-0000-4000-8000-00000000007a', '00000000-0000-4000-8000-00000000000b', 'spam');
select ok(pg_temp.holds_report_lock('d0000000-0000-4000-8000-00000000007a'),
  'a report takes the lock keyed by its deck''s id as text');

-- Control: the trigger that took the lock runs to its end, so the third distinct report hides.
insert into public.deck_reports (deck_id, reporter_id, reason) values
  ('d0000000-0000-4000-8000-00000000007a', '00000000-0000-4000-8000-00000000000c', 'spam'),
  ('d0000000-0000-4000-8000-00000000007a', '00000000-0000-4000-8000-00000000000d', 'other');
select results_eq(
  $$select hidden from public.decks where id = 'd0000000-0000-4000-8000-00000000007a'$$,
  $$values (true)$$,
  'the third distinct report hides the deck');

select * from finish();
rollback;
