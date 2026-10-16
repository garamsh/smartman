-- Server indexes (ADR 0034 §4, step 1 of §9): one index per real query. Additive: it creates
-- eight indexes, then drops cards_user_id_deck_id, which cards_deck_id_created_at_id replaces,
-- and changes no row.

-- The deck's cards, oldest first: the composite foreign key's cascade, a study selection's cards,
-- the public preview and the public listing's count. Not partial, so the cascade finds tombstones.
create index cards_deck_id_created_at_id on public.cards (deck_id, created_at, id);
drop index public.cards_user_id_deck_id;

-- A user's live reviews by time: the pace, a study day's reviews and the streak.
create index reviews_live_user_id_reviewed_at on public.reviews (user_id, reviewed_at)
  where deleted_at is null;

-- The account-deletion cascade from auth.users through the columns no other index leads with.
create index deck_reports_reporter_id on public.deck_reports (reporter_id);
create index user_blocks_blocked_id on public.user_blocks (blocked_id);
create index deck_imports_user_id on public.deck_imports (user_id);

-- The tombstone purge, by revision below the horizon.
create index decks_tombstone_revision on public.decks (revision) where deleted_at is not null;
create index cards_tombstone_revision on public.cards (revision) where deleted_at is not null;
create index card_states_tombstone_revision on public.card_states (revision)
  where deleted_at is not null;
