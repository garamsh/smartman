-- Keys to uuid (ADR 0034 §1, step 2 of §9): every synced id, and every column that references one,
-- becomes uuid. The ids are cast in place, so every row keeps its id; the migration first refuses
-- to run while any value would come back from the cast in another form.

-- Postgres also reads upper case, braces and missing hyphens as a uuid, and writes every uuid back
-- in lowercase hyphenated form. A value in another form would return changed, and the phone, which
-- keeps ids as text, would then hold two ids for one row. So only the form that returns unchanged
-- passes, and the migration raises, changing nothing, naming each column holding another.
do $$
declare
  canonical constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  failing text;
begin
  select string_agg(format('%s (%s)', col, n), ', ') into failing
  from (
    select 'decks.id' as col, count(*) as n from public.decks where id !~ canonical
    union all select 'cards.id', count(*) from public.cards where id !~ canonical
    union all select 'cards.deck_id', count(*) from public.cards where deck_id !~ canonical
    union all select 'cards.origin_deck_id', count(*) from public.cards where origin_deck_id !~ canonical
    union all select 'reviews.id', count(*) from public.reviews where id !~ canonical
    union all select 'reviews.card_id', count(*) from public.reviews where card_id !~ canonical
    union all select 'card_states.card_id', count(*) from public.card_states where card_id !~ canonical
    union all select 'deck_reports.deck_id', count(*) from public.deck_reports where deck_id !~ canonical
    union all select 'deck_imports.deck_id', count(*) from public.deck_imports where deck_id !~ canonical
  ) as counts
  where n > 0;
  if failing is not null then
    raise exception 'ids not in canonical lowercase uuid form: %', failing using errcode = '22P02';
  end if;
end;
$$;

-- Postgres refuses to change the type of a column a policy reads, and a composite foreign key cannot
-- pair a text column with a uuid one, so these go first and return unchanged after the cast.
drop policy cards_select_public on public.cards;
drop policy deck_reports_insert on public.deck_reports;

alter table public.cards drop constraint cards_user_id_deck_id_fkey;
alter table public.reviews drop constraint reviews_user_id_card_id_fkey;
alter table public.card_states drop constraint card_states_user_id_card_id_fkey;
alter table public.deck_reports drop constraint deck_reports_deck_id_fkey;
alter table public.deck_imports drop constraint deck_imports_deck_id_fkey;

-- Their bodies compare these columns with text, for which uuid has no operator, and the listing
-- returns the id's type, so both are dropped here and created again below.
drop function public.list_public_decks(text, text, integer, integer);
drop function public.record_deck_import(text);

-- Each statement rewrites its table and indexes once, under an ACCESS EXCLUSIVE lock held to commit.
alter table public.decks alter column id type uuid using id::uuid;
alter table public.cards
  alter column id type uuid using id::uuid,
  alter column deck_id type uuid using deck_id::uuid,
  alter column origin_deck_id type uuid using origin_deck_id::uuid;
alter table public.reviews
  alter column id type uuid using id::uuid,
  alter column card_id type uuid using card_id::uuid;
alter table public.card_states alter column card_id type uuid using card_id::uuid;
alter table public.deck_reports alter column deck_id type uuid using deck_id::uuid;
alter table public.deck_imports alter column deck_id type uuid using deck_id::uuid;

alter table public.cards add constraint cards_user_id_deck_id_fkey
  foreign key (user_id, deck_id) references public.decks (user_id, id) on delete cascade;
alter table public.reviews add constraint reviews_user_id_card_id_fkey
  foreign key (user_id, card_id) references public.cards (user_id, id) on delete cascade;
alter table public.card_states add constraint card_states_user_id_card_id_fkey
  foreign key (user_id, card_id) references public.cards (user_id, id) on delete cascade;
alter table public.deck_reports add constraint deck_reports_deck_id_fkey
  foreign key (deck_id) references public.decks on delete cascade;
alter table public.deck_imports add constraint deck_imports_deck_id_fkey
  foreign key (deck_id) references public.decks on delete cascade;

create policy cards_select_public on public.cards for select to authenticated
  using (
    deleted_at is null
    and exists (
      select 1 from public.decks as d
      where d.user_id = cards.user_id and d.id = cards.deck_id
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null
    )
  );

create policy deck_reports_insert on public.deck_reports for insert to authenticated
  with check (
    (select auth.uid()) = reporter_id
    and exists (
      select 1 from public.decks as d
      where d.id = deck_reports.deck_id and d.user_id <> (select auth.uid())
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null
    )
  );

-- The public decks the caller may browse: not hidden, not deleted, not of a user the caller
-- blocked, whose name or description holds search (ignoring case), newest first or most copied
-- first. It runs as the caller, so row-level security decides what it reads.
create function public.list_public_decks(
  search text default '',
  sort text default 'newest',
  page_size integer default 50,
  page_offset integer default 0
) returns table (
  id uuid,
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
-- otherwise. A user's first copy of someone else's deck adds one to its import_count; a later
-- copy by that user, or a copy of one's own, does not. A concurrent second copy by the same user
-- waits on the primary key and then inserts nothing, so it adds nothing. It runs as its owner,
-- since clients hold no privilege on deck_imports or on import_count.
create function public.record_deck_import(deck_id uuid) returns boolean
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

revoke all on function public.record_deck_import(uuid) from public, anon;
grant execute on function public.record_deck_import(uuid) to authenticated;

-- Hides the deck once three distinct users have reported it, as before. Its lock key hashes the
-- deck's id as text, which the cast leaves unchanged, so the key is the one it took before; the
-- hash takes only text, so the uuid is cast to it here.
create or replace function private.hide_reported_deck() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.deck_id::text, 2));
  if (select count(*) from public.deck_reports as r where r.deck_id = new.deck_id) >= 3 then
    update public.decks set hidden = true where id = new.deck_id and not hidden;
  end if;
  return null;
end;
$$;
