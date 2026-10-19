-- The admin area's users and decks (#234, ADR 0072): suspending a user, removing a public deck from
-- sharing for good, a user's decks read-only, and the user search as you type. Additive but for one
-- write ADR 0072 justifies: suspending sets the user's `auth.users.banned_until`, which Supabase Auth
-- reads to refuse the user's sign-in and refresh. No function here writes an email, a password or
-- a profile field. It changes no existing row and replaces no existing object; the write limits are
-- new restrictive policies beside the existing ones.

-- The suspended users: who suspended each, why and when. A user without a row is active.
create table private.suspensions (
  user_id uuid primary key references auth.users on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  suspended_by uuid references auth.users on delete set null,
  suspended_at timestamptz not null default now()
);

-- The public decks removed from sharing for good: who removed each, why and when. Such a deck
-- stays its owner's, private, and cannot be made public again.
create table private.deck_removals (
  deck_id uuid primary key references public.decks on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  removed_by uuid references auth.users on delete set null,
  removed_at timestamptz not null default now()
);

create index suspensions_suspended_by on private.suspensions (suspended_by);
create index deck_removals_removed_by on private.deck_removals (removed_by);

alter table private.suspensions enable row level security;
alter table private.deck_removals enable row level security;
revoke all on private.suspensions, private.deck_removals from public, anon, authenticated;

-- Whether the caller is suspended. The write policies below read it; a client may ask it of itself.
create function public.is_suspended() returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select from private.suspensions as s where s.user_id = (select auth.uid()));
$$;

-- Whether [user_id] is suspended, for extract-cards, which asks with the service role.
create function public.user_suspended(user_id uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select from private.suspensions as s where s.user_id = user_suspended.user_id);
$$;

-- Whether [deck_id] was removed from sharing, for the policy that keeps it private.
create function public.deck_removed_from_sharing(deck_id uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select from private.deck_removals as r where r.deck_id = deck_removed_from_sharing.deck_id);
$$;

revoke all on function public.is_suspended(), public.user_suspended(uuid),
  public.deck_removed_from_sharing(uuid) from public, anon;
grant execute on function public.is_suspended(), public.deck_removed_from_sharing(uuid) to authenticated;
revoke all on function public.user_suspended(uuid) from authenticated;
grant execute on function public.user_suspended(uuid) to service_role;

-- A suspended user writes none of the synced rows: restrictive policies, which every write must
-- also pass beside the owner's policies. Each reads the caller's suspension once per statement.
create policy decks_not_suspended_insert on public.decks as restrictive for insert to authenticated
  with check (not (select public.is_suspended()));
create policy decks_not_suspended_update on public.decks as restrictive for update to authenticated
  using (not (select public.is_suspended())) with check (not (select public.is_suspended()));
create policy decks_not_suspended_delete on public.decks as restrictive for delete to authenticated
  using (not (select public.is_suspended()));
create policy cards_not_suspended_insert on public.cards as restrictive for insert to authenticated
  with check (not (select public.is_suspended()));
create policy cards_not_suspended_update on public.cards as restrictive for update to authenticated
  using (not (select public.is_suspended())) with check (not (select public.is_suspended()));
create policy cards_not_suspended_delete on public.cards as restrictive for delete to authenticated
  using (not (select public.is_suspended()));
create policy reviews_not_suspended_insert on public.reviews as restrictive for insert to authenticated
  with check (not (select public.is_suspended()));
create policy reviews_not_suspended_update on public.reviews as restrictive for update to authenticated
  using (not (select public.is_suspended())) with check (not (select public.is_suspended()));
create policy card_states_not_suspended_insert on public.card_states as restrictive for insert to authenticated
  with check (not (select public.is_suspended()));
create policy card_states_not_suspended_update on public.card_states as restrictive for update to authenticated
  using (not (select public.is_suspended())) with check (not (select public.is_suspended()));
create policy card_states_not_suspended_delete on public.card_states as restrictive for delete to authenticated
  using (not (select public.is_suspended()));

-- A deck removed from sharing cannot be made public again.
create policy decks_removed_stay_private_insert on public.decks as restrictive for insert to authenticated
  with check (visibility <> 'public' or not public.deck_removed_from_sharing(id));
create policy decks_removed_stay_private_update on public.decks as restrictive for update to authenticated
  using (true) with check (visibility <> 'public' or not public.deck_removed_from_sharing(id));

-- Suspends [user_id] with [reason] and records it: 'suspended'; 'already' for a suspended user,
-- 'self' for the caller, or 'no_user', recording nothing. It sets the user's `banned_until`, the one
-- auth column an admin function writes, so Supabase Auth refuses the user's sign-in and refresh.
create function public.admin_suspend_user(user_id uuid, reason text) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := private.require_admin();
  suspended_email text;
begin
  select u.email into suspended_email from auth.users as u where u.id = admin_suspend_user.user_id;
  if not found then
    return 'no_user';
  end if;
  if admin_suspend_user.user_id = caller then
    return 'self';
  end if;
  insert into private.suspensions (user_id, reason, suspended_by)
    values (admin_suspend_user.user_id, btrim(admin_suspend_user.reason), caller)
    on conflict on constraint suspensions_pkey do nothing;
  if not found then
    return 'already';
  end if;
  update auth.users as u set banned_until = now() + interval '100 years'
    where u.id = admin_suspend_user.user_id;
  perform private.audit('suspend_user', 'user', admin_suspend_user.user_id::text,
    jsonb_build_object('email', coalesce(suspended_email, ''), 'reason', btrim(admin_suspend_user.reason)));
  return 'suspended';
end;
$$;

-- Lifts [user_id]'s suspension and records it, returning true; false, recording nothing, for an
-- active user. It clears `banned_until`, so the user signs in again; the data was kept.
create function public.admin_unsuspend_user(user_id uuid) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  unsuspended_email text;
begin
  perform private.require_admin();
  delete from private.suspensions as s where s.user_id = admin_unsuspend_user.user_id;
  if not found then
    return false;
  end if;
  update auth.users as u set banned_until = null where u.id = admin_unsuspend_user.user_id
    returning u.email into unsuspended_email;
  perform private.audit('unsuspend_user', 'user', admin_unsuspend_user.user_id::text,
    jsonb_build_object('email', coalesce(unsuspended_email, '')));
  return true;
end;
$$;

-- [user_id]'s suspension: why, when and by whom, or no row for an active user.
create function public.admin_user_suspension(user_id uuid)
returns table (reason text, suspended_at timestamptz, suspended_by_email text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select s.reason, s.suspended_at, b.email::text
  from private.suspensions as s
  left join auth.users as b on b.id = s.suspended_by
  where s.user_id = admin_user_suspension.user_id;
end;
$$;

-- A page of the users whose email holds [query], ignoring case: those it starts first, then by
-- email, [page_size] from [page_offset], each with whether it is suspended and the matches in all.
create function public.admin_search_users(query text, page_size integer default 20, page_offset integer default 0)
returns table (user_id uuid, email text, created_at timestamptz, suspended boolean, total bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select u.id, u.email::text, u.created_at,
    exists (select from private.suspensions as s where s.user_id = u.id),
    count(*) over ()
  from auth.users as u
  where not u.is_anonymous and btrim(admin_search_users.query) <> ''
    and strpos(lower(u.email), lower(btrim(admin_search_users.query))) > 0
  order by strpos(lower(u.email), lower(btrim(admin_search_users.query))) <> 1, u.email, u.id
  limit least(greatest(admin_search_users.page_size, 1), 100)
  offset greatest(admin_search_users.page_offset, 0);
end;
$$;

-- Every live deck of [user_id], newest first, public or private: its state, whether it was removed
-- from sharing, and its live cards.
create function public.admin_user_decks(user_id uuid)
returns table (
  deck_id uuid, name text, visibility text, hidden boolean, removed boolean, cards bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select d.id, d.name, d.visibility, d.hidden,
    exists (select from private.deck_removals as r where r.deck_id = d.id),
    (select count(*) from public.cards as c
      where c.user_id = d.user_id and c.deck_id = d.id and c.deleted_at is null),
    d.created_at
  from public.decks as d
  where d.user_id = admin_user_decks.user_id and d.deleted_at is null
  order by d.created_at desc, d.id;
end;
$$;

-- Any deck, read-only, as `admin_deck` reads a public or reported one, with its removal from
-- sharing when there is one. No row for a deck that does not exist.
create function public.admin_user_deck(deck_id uuid)
returns table (
  id uuid, name text, description text, owner_id uuid, owner_email text, owner_name text,
  visibility text, hidden boolean, deleted boolean, import_count integer, reports bigint,
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
    d.hidden, d.deleted_at is not null, d.import_count,
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

-- The live cards of any deck, oldest first, with both sides.
create function public.admin_user_deck_cards(deck_id uuid)
returns table (card_id uuid, front jsonb, back jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select c.id, c.front, c.back
  from public.decks as d
  join public.cards as c on c.user_id = d.user_id and c.deck_id = d.id and c.deleted_at is null
  where d.id = admin_user_deck_cards.deck_id
  order by c.created_at, c.id;
end;
$$;

-- Removes a deck from sharing for good with [reason] and records it, returning true: the deck
-- becomes private with an edit time of now, so its owner's devices pull it, and the policy above
-- keeps it so. False, recording nothing, for a deck that does not exist or was removed already.
create function public.admin_remove_deck(deck_id uuid, reason text) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := private.require_admin();
  deck_name text;
begin
  select d.name into deck_name from public.decks as d where d.id = admin_remove_deck.deck_id;
  if not found then
    return false;
  end if;
  insert into private.deck_removals (deck_id, reason, removed_by)
    values (admin_remove_deck.deck_id, btrim(admin_remove_deck.reason), caller)
    on conflict on constraint deck_removals_pkey do nothing;
  if not found then
    return false;
  end if;
  update public.decks as d set visibility = 'private', updated_at = now()
    where d.id = admin_remove_deck.deck_id and d.visibility = 'public';
  perform private.audit('remove_deck', 'deck', admin_remove_deck.deck_id::text,
    jsonb_build_object('name', deck_name, 'reason', btrim(admin_remove_deck.reason)));
  return true;
end;
$$;

revoke all on function
  public.admin_suspend_user(uuid, text),
  public.admin_unsuspend_user(uuid),
  public.admin_user_suspension(uuid),
  public.admin_search_users(text, integer, integer),
  public.admin_user_decks(uuid),
  public.admin_user_deck(uuid),
  public.admin_user_deck_cards(uuid),
  public.admin_remove_deck(uuid, text)
  from public, anon;
grant execute on function
  public.admin_suspend_user(uuid, text),
  public.admin_unsuspend_user(uuid),
  public.admin_user_suspension(uuid),
  public.admin_search_users(text, integer, integer),
  public.admin_user_decks(uuid),
  public.admin_user_deck(uuid),
  public.admin_user_deck_cards(uuid),
  public.admin_remove_deck(uuid, text)
  to authenticated;
