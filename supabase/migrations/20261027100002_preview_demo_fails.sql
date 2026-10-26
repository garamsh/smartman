-- Scratch migration for #402: fails on the seeded decks; never merged.
alter table public.decks add constraint preview_demo_check check (name = 'never');
