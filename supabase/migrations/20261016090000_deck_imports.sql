-- Deck imports (#67): a public deck's import_count counts each user who copied it once.
-- Additive: it creates deck_imports and replaces record_deck_import with the same signature, and
-- changes no row. Copies made before it were not recorded per user, so an existing import_count
-- stays as it is and later copies add to it.

-- One row per deck and user who copied it; its owner never has one. Written only by
-- record_deck_import; clients hold no privilege on it.
create table public.deck_imports (
  deck_id text not null references public.decks on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (deck_id, user_id)
);

revoke all on public.deck_imports from anon, authenticated;

alter table public.deck_imports enable row level security;

-- Called when a user copies a public deck: true when the deck is public and visible, false
-- otherwise. A user's first copy of someone else's deck adds one to its import_count; a later
-- copy by that user, or a copy of one's own, does not. A concurrent second copy by the same user
-- waits on the primary key and then inserts nothing, so it adds nothing.
create or replace function public.record_deck_import(deck_id text) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.decks as d
    where d.id = record_deck_import.deck_id
      and d.visibility = 'public' and not d.hidden and d.deleted_at is null
  ) then
    return false;
  end if;
  insert into public.deck_imports (deck_id, user_id)
    select d.id, (select auth.uid()) from public.decks as d
    where d.id = record_deck_import.deck_id and d.user_id <> (select auth.uid())
    on conflict do nothing;
  if found then
    update public.decks as d set import_count = d.import_count + 1
      where d.id = record_deck_import.deck_id;
  end if;
  return true;
end;
$$;
