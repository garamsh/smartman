-- The sync schema: the app's four local tables, owned per user, with the sync columns
-- updated_at (the device's edit time), deleted_at (a tombstone) and revision (server-set).

-- Holds what clients never reach: the revision sequence and its trigger function.
-- The API exposes only the schemas in config.toml's [api] schemas, and this is not one.
create schema private;

-- One sequence for every table, so a client pulls each table by one cursor.
create sequence private.revision as bigint;

-- Overwrites any revision the client sent, on insert and on update.
create function private.set_revision() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.revision := nextval('private.revision');
  return new;
end;
$$;

revoke all on function private.set_revision() from public;

create table public.decks (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  revision bigint not null,
  -- The target of the composite foreign keys that keep a user's references inside that user.
  unique (user_id, id)
);

create table public.cards (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  deck_id text not null,
  front jsonb not null check (jsonb_typeof(front) = 'array'),
  back jsonb not null check (jsonb_typeof(back) = 'array'),
  card_key text not null,
  source text not null check (source in ('manual', 'import')),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  revision bigint not null,
  unique (user_id, id),
  foreign key (user_id, deck_id) references public.decks (user_id, id) on delete cascade
);

create table public.reviews (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  card_id text not null,
  rating text not null check (rating in ('again', 'good')),
  reviewed_at timestamptz not null,
  duration_ms integer not null check (duration_ms >= 0),
  updated_at timestamptz not null,
  deleted_at timestamptz,
  revision bigint not null,
  foreign key (user_id, card_id) references public.cards (user_id, id) on delete cascade
);

create table public.card_states (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  card_id text not null,
  stability double precision not null,
  difficulty double precision not null,
  last_review timestamptz not null,
  due timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  revision bigint not null,
  primary key (user_id, card_id),
  foreign key (user_id, card_id) references public.cards (user_id, id) on delete cascade
);

-- The foreign keys' referencing columns, for the cascades, and the pull cursor per user.
create index cards_user_id_deck_id on public.cards (user_id, deck_id);
create index reviews_user_id_card_id on public.reviews (user_id, card_id);
create index decks_user_id_revision on public.decks (user_id, revision);
create index cards_user_id_revision on public.cards (user_id, revision);
create index reviews_user_id_revision on public.reviews (user_id, revision);
create index card_states_user_id_revision on public.card_states (user_id, revision);

create trigger set_revision before insert or update on public.decks
  for each row execute function private.set_revision();
create trigger set_revision before insert or update on public.cards
  for each row execute function private.set_revision();
create trigger set_revision before insert or update on public.reviews
  for each row execute function private.set_revision();
create trigger set_revision before insert or update on public.card_states
  for each row execute function private.set_revision();

-- Privileges are granted here rather than left to the project's default privileges:
-- anon gets nothing, and a review's only updatable columns are its rating and edit time.
revoke all on public.decks, public.cards, public.reviews, public.card_states
  from anon, authenticated;
grant select, insert, update, delete on public.decks, public.cards, public.card_states
  to authenticated;
grant select, insert on public.reviews to authenticated;
grant update (rating, updated_at) on public.reviews to authenticated;

alter table public.decks enable row level security;
alter table public.cards enable row level security;
alter table public.reviews enable row level security;
alter table public.card_states enable row level security;

create policy decks_select on public.decks for select to authenticated
  using ((select auth.uid()) = user_id);
create policy decks_insert on public.decks for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy decks_update on public.decks for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy decks_delete on public.decks for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy cards_select on public.cards for select to authenticated
  using ((select auth.uid()) = user_id);
create policy cards_insert on public.cards for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy cards_update on public.cards for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy cards_delete on public.cards for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy reviews_select on public.reviews for select to authenticated
  using ((select auth.uid()) = user_id);
create policy reviews_insert on public.reviews for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy reviews_update on public.reviews for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy reviews_delete on public.reviews for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy card_states_select on public.card_states for select to authenticated
  using ((select auth.uid()) = user_id);
create policy card_states_insert on public.card_states for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy card_states_update on public.card_states for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy card_states_delete on public.card_states for delete to authenticated
  using ((select auth.uid()) = user_id);
