-- A deck's appearance (#382, ADR 0103): the keys of the icon and the colour its owner chose for
-- its tile. Additive: two nullable columns and their grants, and no row is rewritten; a deck
-- with neither key, as every existing deck, draws the default tile.

-- Each key is bounded in length alone, never checked against a list: a newer app may add icons
-- or colours, and a client draws the default for a key it does not know.
alter table public.decks
  add column icon text check (char_length(icon) <= 40),
  add column color text check (char_length(color) <= 40);

-- Clients write both, as they write the deck's other columns (20261015180000_public_decks.sql).
grant insert (icon, color) on public.decks to authenticated;
grant update (icon, color) on public.decks to authenticated;
