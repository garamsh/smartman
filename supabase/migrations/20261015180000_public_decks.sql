-- Public decks (#29): a deck's owner publishes it, other signed-in users list, preview and copy it,
-- and report or block. Moderation hides a deck that three users reported.

-- A deck's publishing state, synced like its name: visibility, when it was last published, and
-- an optional description. hidden and import_count are the server's: clients read them and never
-- write them (see the grants below).
alter table public.decks
  add column visibility text not null default 'private' check (visibility in ('private', 'public')),
  add column published_at timestamptz,
  add column description text check (char_length(description) <= 300),
  add column hidden boolean not null default false,
  add column import_count integer not null default 0 check (import_count >= 0),
  add constraint decks_published_at_check check (visibility = 'private' or published_at is not null);

-- A copied card names the deck it was copied from. No foreign key: that deck is another user's
-- and may be deleted.
alter table public.cards add column origin_deck_id text;

-- Copied cards carry source 'shared'. The check is replaced in one statement; no row changes.
alter table public.cards
  drop constraint cards_source_check,
  add constraint cards_source_check check (source in ('manual', 'import', 'shared'));

-- Clients write every deck column but hidden and import_count, as reviews are limited to the
-- columns a client may change (ADR 0010). A revision a client sends stays writable, since the
-- trigger overwrites it. Select and delete stay as they were.
revoke insert, update on public.decks from authenticated;
grant insert (id, user_id, name, created_at, updated_at, deleted_at, revision, visibility, published_at,
  description)
  on public.decks to authenticated;
grant update (id, user_id, name, created_at, updated_at, deleted_at, revision, visibility, published_at,
  description)
  on public.decks to authenticated;

-- The listing, published-first, reads this index.
create index decks_public_published_at on public.decks (published_at desc)
  where visibility = 'public' and not hidden and deleted_at is null;

-- Any signed-in user reads a public deck that is not hidden or deleted, and its live cards.
-- Policies of one command combine with or, so the owner's own policies still apply; writes stay
-- owner-only, since no write policy names another user's rows.
create policy decks_select_public on public.decks for select to authenticated
  using (visibility = 'public' and not hidden and deleted_at is null);

create policy cards_select_public on public.cards for select to authenticated
  using (
    deleted_at is null
    and exists (
      select 1 from public.decks as d
      where d.user_id = cards.user_id and d.id = cards.deck_id
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null
    )
  );

-- The name shown with a user's public decks, set on first publish. The email is never shown.
create table public.profiles (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  display_name text not null
    check (char_length(display_name) between 2 and 20 and display_name !~ '^\s|\s$'),
  created_at timestamptz not null default now()
);

revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant insert (user_id, display_name) on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

alter table public.profiles enable row level security;

create policy profiles_select on public.profiles for select to authenticated
  using ((select auth.uid()) = user_id);
create policy profiles_select_public on public.profiles for select to authenticated
  using (
    exists (
      select 1 from public.decks as d
      where d.user_id = profiles.user_id
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null
    )
  );
create policy profiles_insert on public.profiles for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy profiles_update on public.profiles for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- One report per reporter and deck. A reporter inserts and reads nothing back.
create table public.deck_reports (
  deck_id text not null references public.decks on delete cascade,
  reporter_id uuid not null default auth.uid() references auth.users on delete cascade,
  reason text not null check (reason in ('inappropriate', 'spam', 'copyright', 'other')),
  created_at timestamptz not null default now(),
  primary key (deck_id, reporter_id)
);

revoke all on public.deck_reports from anon, authenticated;
grant insert (deck_id, reporter_id, reason) on public.deck_reports to authenticated;

alter table public.deck_reports enable row level security;

-- Only a deck the reporter can read as public, and not the reporter's own.
create policy deck_reports_insert on public.deck_reports for insert to authenticated
  with check (
    (select auth.uid()) = reporter_id
    and exists (
      select 1 from public.decks as d
      where d.id = deck_reports.deck_id and d.user_id <> (select auth.uid())
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null
    )
  );

-- Hides the deck once three distinct users have reported it; the project's owner unhides it in
-- the dashboard. The lock, keyed by the deck and seeded with 2, makes concurrent reports count
-- one after another, so the third is never missed.
create function private.hide_reported_deck() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.deck_id, 2));
  if (select count(*) from public.deck_reports as r where r.deck_id = new.deck_id) >= 3 then
    update public.decks set hidden = true where id = new.deck_id and not hidden;
  end if;
  return null;
end;
$$;

revoke all on function private.hide_reported_deck() from public;

create trigger hide_reported_deck after insert on public.deck_reports
  for each row execute function private.hide_reported_deck();

-- A user's blocks: whose public decks the listing leaves out for that user.
create table public.user_blocks (
  blocker_id uuid not null default auth.uid() references auth.users on delete cascade,
  blocked_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

revoke all on public.user_blocks from anon, authenticated;
grant select, delete on public.user_blocks to authenticated;
grant insert (blocker_id, blocked_id) on public.user_blocks to authenticated;

alter table public.user_blocks enable row level security;

create policy user_blocks_select on public.user_blocks for select to authenticated
  using ((select auth.uid()) = blocker_id);
create policy user_blocks_insert on public.user_blocks for insert to authenticated
  with check ((select auth.uid()) = blocker_id);
create policy user_blocks_delete on public.user_blocks for delete to authenticated
  using ((select auth.uid()) = blocker_id);

-- The public decks the caller may browse: not hidden, not deleted, not of a user the caller
-- blocked, whose name or description holds search (ignoring case), newest first or most copied
-- first. It runs as the caller, so row-level security decides what it reads.
create function public.list_public_decks(
  search text default '',
  sort text default 'newest',
  page_size integer default 50,
  page_offset integer default 0
) returns table (
  id text,
  user_id uuid,
  name text,
  description text,
  display_name text,
  card_count bigint,
  import_count integer,
  published_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if sort not in ('newest', 'copied') then
    raise exception 'sort must be newest or copied, not %', sort using errcode = '22023';
  end if;
  return query
  select d.id, d.user_id, d.name, d.description, p.display_name,
    (select count(*) from public.cards as c
      where c.user_id = d.user_id and c.deck_id = d.id and c.deleted_at is null),
    d.import_count, d.published_at
  from public.decks as d
  join public.profiles as p on p.user_id = d.user_id
  where d.visibility = 'public' and not d.hidden and d.deleted_at is null
    and not exists (
      select 1 from public.user_blocks as b
      where b.blocker_id = (select auth.uid()) and b.blocked_id = d.user_id
    )
    and (
      search = ''
      or strpos(lower(d.name), lower(search)) > 0
      or strpos(lower(coalesce(d.description, '')), lower(search)) > 0
    )
  order by
    case when sort = 'copied' then d.import_count end desc nulls last,
    d.published_at desc,
    d.id
  limit page_size offset page_offset;
end;
$$;

revoke all on function public.list_public_decks(text, text, integer, integer) from public, anon;
grant execute on function public.list_public_decks(text, text, integer, integer) to authenticated;

-- Called when a user copies a public deck: true when the deck is public and visible, false
-- otherwise. A copy of someone else's deck adds one to its import_count; a copy of one's own
-- does not.
create function public.record_deck_import(deck_id text) returns boolean
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
  update public.decks as d set import_count = d.import_count + 1
    where d.id = record_deck_import.deck_id and d.user_id <> (select auth.uid());
  return true;
end;
$$;

revoke all on function public.record_deck_import(text) from public, anon;
grant execute on function public.record_deck_import(text) to authenticated;
