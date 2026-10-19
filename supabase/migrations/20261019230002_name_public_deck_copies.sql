-- Copying a public deck is named "copy" everywhere, and "import" is left to photo import alone
-- (ADR 0082, issue #218): the table deck_imports becomes deck_copies, decks.import_count becomes
-- copy_count, record_deck_import becomes record_deck_copy, and a copied card's source 'shared'
-- becomes 'copy'. Every rename is in place, so no row is lost. The source remap changes the
-- copied cards' rows: each takes a new revision, so devices pull it, and its edit time stays.

alter table public.deck_imports rename to deck_copies;
alter table public.deck_copies rename constraint deck_imports_pkey to deck_copies_pkey;
alter table public.deck_copies rename constraint deck_imports_deck_id_fkey to deck_copies_deck_id_fkey;
alter table public.deck_copies rename constraint deck_imports_user_id_fkey to deck_copies_user_id_fkey;
alter index public.deck_imports_user_id rename to deck_copies_user_id;

alter table public.decks rename column import_count to copy_count;
alter table public.decks rename constraint decks_import_count_check to decks_copy_count_check;

-- A copied card's source: both checks name the value, so both are replaced around the remap.
alter table public.cards drop constraint cards_source_check;
alter table public.cards drop constraint cards_origin_deck_id_check;
update public.cards set source = 'copy' where source = 'shared';
alter table public.cards add constraint cards_source_check
  check (source in ('manual', 'import', 'copy'));
alter table public.cards add constraint cards_origin_deck_id_check
  check ((source = 'copy') = (origin_deck_id is not null));

-- The functions that name the old column or table, recreated under the new names with the same
-- bodies and privileges. A returned column's name is part of a function's type, so each is dropped
-- first.
drop function public.record_deck_import(uuid);
drop function public.list_public_decks(text, text, integer, integer);
drop function public.admin_public_decks(text, uuid);
drop function public.admin_deck(uuid);
drop function public.admin_user_deck(uuid);

-- record_deck_import as 20261016180000_uuid_keys.sql defined it, under the new names.
create function public.record_deck_copy(deck_id uuid) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.decks as d
    where d.id = record_deck_copy.deck_id
      and d.visibility = 'public' and not d.hidden and d.deleted_at is null
  ) then
    return false;
  end if;
  insert into public.deck_copies (deck_id, user_id)
    select d.id, (select auth.uid()) from public.decks as d
    where d.id = record_deck_copy.deck_id and d.user_id <> (select auth.uid())
    on conflict do nothing;
  if found then
    update public.decks as d set copy_count = d.copy_count + 1
      where d.id = record_deck_copy.deck_id;
  end if;
  return true;
end;
$$;

revoke all on function public.record_deck_copy(uuid) from public, anon;
grant execute on function public.record_deck_copy(uuid) to authenticated;

-- list_public_decks as 20261016180000_uuid_keys.sql defined it, under the new names.
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
  copy_count integer,
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
    d.copy_count, d.published_at
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
    case when sort = 'copied' then d.copy_count end desc nulls last,
    d.published_at desc,
    d.id
  limit page_size offset page_offset;
end;
$$;

revoke all on function public.list_public_decks(text, text, integer, integer) from public, anon;
grant execute on function public.list_public_decks(text, text, integer, integer) to authenticated;

-- admin_public_decks as 20261019120000_admin.sql defined it, under the new names.
create function public.admin_public_decks(search text default '', owner uuid default null)
returns table (
  deck_id uuid,
  name text,
  owner_id uuid,
  owner_email text,
  owner_name text,
  hidden boolean,
  cards bigint,
  copy_count integer,
  reports bigint,
  published_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select d.id, d.name, d.user_id, u.email::text, p.display_name, d.hidden,
    (select count(*) from public.cards as c
      where c.user_id = d.user_id and c.deck_id = d.id and c.deleted_at is null),
    d.copy_count,
    (select count(*) from public.deck_reports as x where x.deck_id = d.id),
    d.published_at
  from public.decks as d
  join auth.users as u on u.id = d.user_id
  left join public.profiles as p on p.user_id = d.user_id
  where d.visibility = 'public' and d.deleted_at is null
    and (admin_public_decks.owner is null or d.user_id = admin_public_decks.owner)
    and (admin_public_decks.search = ''
      or strpos(lower(d.name), lower(admin_public_decks.search)) > 0)
  order by d.published_at desc, d.id;
end;
$$;

revoke all on function public.admin_public_decks(text, uuid) from public, anon;
grant execute on function public.admin_public_decks(text, uuid) to authenticated;

-- admin_deck as 20261019120000_admin.sql defined it, under the new names.
create function public.admin_deck(deck_id uuid)
returns table (
  id uuid,
  name text,
  description text,
  owner_id uuid,
  owner_email text,
  owner_name text,
  visibility text,
  hidden boolean,
  deleted boolean,
  copy_count integer,
  reports bigint,
  reasons text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select d.id, d.name, d.description, d.user_id, u.email::text, p.display_name, d.visibility,
    d.hidden, d.deleted_at is not null, d.copy_count,
    (select count(*) from public.deck_reports as x where x.deck_id = d.id),
    coalesce((select array_agg(distinct x.reason order by x.reason)
      from public.deck_reports as x where x.deck_id = d.id), '{}')
  from public.decks as d
  join auth.users as u on u.id = d.user_id
  left join public.profiles as p on p.user_id = d.user_id
  where d.id = admin_deck.deck_id
    and (d.visibility = 'public'
      or exists (select from public.deck_reports as x where x.deck_id = d.id));
end;
$$;

revoke all on function public.admin_deck(uuid) from public, anon;
grant execute on function public.admin_deck(uuid) to authenticated;

-- admin_user_deck as 20261019200000_admin_users.sql defined it, under the new names.
create function public.admin_user_deck(deck_id uuid)
returns table (
  id uuid, name text, description text, owner_id uuid, owner_email text, owner_name text,
  visibility text, hidden boolean, deleted boolean, copy_count integer, reports bigint,
  reasons text[], removal_reason text, removed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select d.id, d.name, d.description, d.user_id, u.email::text, p.display_name, d.visibility,
    d.hidden, d.deleted_at is not null, d.copy_count,
    (select count(*) from public.deck_reports as x where x.deck_id = d.id),
    coalesce((select array_agg(distinct x.reason order by x.reason)
      from public.deck_reports as x where x.deck_id = d.id), '{}'),
    r.reason, r.removed_at
  from public.decks as d
  join auth.users as u on u.id = d.user_id
  left join public.profiles as p on p.user_id = d.user_id
  left join private.deck_removals as r on r.deck_id = d.id
  where d.id = admin_user_deck.deck_id;
end;
$$;

revoke all on function public.admin_user_deck(uuid) from public, anon;
grant execute on function public.admin_user_deck(uuid) to authenticated;
