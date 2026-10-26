-- Scratch migration for #402: shows the preview job; never merged.
alter table public.decks add column archived boolean not null default false;
update public.study_settings set daily_minutes = daily_minutes + 5;
delete from public.user_blocks;
