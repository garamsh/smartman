-- Indexes: each index ADR 0034 names for a server query exists with its columns and predicate,
-- and cards_user_id_deck_id, which cards_deck_id_created_at_id replaces, is gone.
begin;
select plan(10);

-- The definition Postgres reconstructs for a public index, or null where none has that name.
create function pg_temp.definition(index_name name) returns text
language sql stable as $$
  select indexdef from pg_indexes where schemaname = 'public' and indexname = index_name
$$;

select is(pg_temp.definition('reviews_live_user_id_reviewed_at'),
  'CREATE INDEX reviews_live_user_id_reviewed_at ON public.reviews USING btree (user_id, reviewed_at) WHERE (deleted_at IS NULL)',
  'reviews_live_user_id_reviewed_at indexes a user''s live reviews by time');
select is(pg_temp.definition('cards_deck_id_created_at_id'),
  'CREATE INDEX cards_deck_id_created_at_id ON public.cards USING btree (deck_id, created_at, id)',
  'cards_deck_id_created_at_id indexes every card of a deck, tombstones included, oldest first');
select is(pg_temp.definition('deck_reports_reporter_id'),
  'CREATE INDEX deck_reports_reporter_id ON public.deck_reports USING btree (reporter_id)',
  'deck_reports_reporter_id indexes reports by reporter');
select is(pg_temp.definition('user_blocks_blocked_id'),
  'CREATE INDEX user_blocks_blocked_id ON public.user_blocks USING btree (blocked_id)',
  'user_blocks_blocked_id indexes blocks by the blocked user');
select is(pg_temp.definition('deck_imports_user_id'),
  'CREATE INDEX deck_imports_user_id ON public.deck_imports USING btree (user_id)',
  'deck_imports_user_id indexes imports by the copying user');
select is(pg_temp.definition('decks_tombstone_revision'),
  'CREATE INDEX decks_tombstone_revision ON public.decks USING btree (revision) WHERE (deleted_at IS NOT NULL)',
  'decks_tombstone_revision indexes deck tombstones by revision');
select is(pg_temp.definition('cards_tombstone_revision'),
  'CREATE INDEX cards_tombstone_revision ON public.cards USING btree (revision) WHERE (deleted_at IS NOT NULL)',
  'cards_tombstone_revision indexes card tombstones by revision');
select is(pg_temp.definition('card_states_tombstone_revision'),
  'CREATE INDEX card_states_tombstone_revision ON public.card_states USING btree (revision) WHERE (deleted_at IS NOT NULL)',
  'card_states_tombstone_revision indexes card state tombstones by revision');

-- The control: the same lookup finds an index the cards table still has.
select isnt(pg_temp.definition('cards_user_id_revision'), null,
  'the lookup finds cards_user_id_revision, which cards keeps');
select is(pg_temp.definition('cards_user_id_deck_id'), null,
  'cards_user_id_deck_id is dropped');

select * from finish();
rollback;
