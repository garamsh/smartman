-- A card's template and its version (#388, ADR 0106): the template a card was made from, which
-- only decides how the editor opens it, and the version it was written in. Additive: two
-- nullable columns, and no row is rewritten; a card gains them on its next write from an app
-- that records them.

-- The template is never checked against a list, so a newer app's template syncs through an
-- older one unchanged. Clients write both through the table-level grants on public.cards
-- (20261014155006_sync_schema.sql), under its row-level security.
alter table public.cards
  add column template text,
  add column template_version smallint check (template_version >= 1);
