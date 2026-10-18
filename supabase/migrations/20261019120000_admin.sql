-- The web admin area (#223, ADR 0070): the admin role and the audit log, both in the schema
-- `private`, which the API does not expose, and the functions the admin area calls. Each runs as
-- its owner and first checks that the caller is an admin, so every admin read and write is
-- authorised here and not in the web. Additive: it creates two tables and the functions, and
-- changes no existing row. The first admin is a row the PM inserts after deploy, not a seed.

-- The admins: one row per user who holds the role. A user without a row is not an admin.
create table private.admins (
  user_id uuid primary key references auth.users on delete cascade,
  granted_by uuid references auth.users on delete set null,
  granted_at timestamptz not null default now()
);

-- Every admin write: who, what, on what, when. `action` and `target_kind` are the names the
-- writing function gives (ADR 0070 lists them); a later function adds its own without a schema
-- change. `admin_email` keeps who acted readable once that account is gone.
create table private.admin_audit (
  id bigint generated always as identity primary key,
  admin_id uuid references auth.users on delete cascade,
  admin_email text not null,
  action text not null check (action ~ '^[a-z]+(_[a-z]+)*$'),
  target_kind text not null check (target_kind ~ '^[a-z]+(_[a-z]+)*$'),
  target_id text not null check (target_id <> ''),
  detail jsonb not null default '{}' check (jsonb_typeof(detail) = 'object'),
  created_at timestamptz not null default now()
);

-- The account-deletion cascade from auth.users through the columns no primary key leads with.
create index admins_granted_by on private.admins (granted_by);
create index admin_audit_admin_id on private.admin_audit (admin_id);

alter table private.admins enable row level security;
alter table private.admin_audit enable row level security;
revoke all on private.admins, private.admin_audit from public, anon, authenticated;

-- The caller's id when the caller is an admin; otherwise raises insufficient_privilege, so an
-- admin function called by anyone else reads and writes nothing.
create function private.require_admin() returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
begin
  if caller is null or not exists (select from private.admins as a where a.user_id = caller) then
    raise exception 'only an admin may call this' using errcode = '42501';
  end if;
  return caller;
end;
$$;

-- Records one admin write by the caller.
create function private.audit(action text, target_kind text, target_id text, detail jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.admin_audit (admin_id, admin_email, action, target_kind, target_id, detail)
  select u.id, coalesce(u.email, ''), audit.action, audit.target_kind, audit.target_id, audit.detail
  from auth.users as u
  where u.id = (select auth.uid());
$$;

revoke all on function private.require_admin(), private.audit(text, text, text, jsonb)
  from public, anon, authenticated;

-- Whether the caller is an admin. The web asks this before it shows the admin area.
create function public.is_admin() returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select from private.admins as a where a.user_id = (select auth.uid()));
$$;

-- The overview: users in total and new in the last 7 and 30 days, those with a live answer since
-- [today_start] and since [week_start], the study days' starts the web computes in the admin's
-- zone, and photo extractions since the start of the UTC day, the daily limit's day.
create function public.admin_overview(today_start timestamptz, week_start timestamptz)
returns table (
  users bigint,
  new_users_7d bigint,
  new_users_30d bigint,
  studied_today bigint,
  studied_7d bigint,
  extractions_today bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select
    (select count(*) from auth.users as u where not u.is_anonymous),
    (select count(*) from auth.users as u
      where not u.is_anonymous and u.created_at >= now() - interval '7 days'),
    (select count(*) from auth.users as u
      where not u.is_anonymous and u.created_at >= now() - interval '30 days'),
    (select count(distinct r.user_id) from public.reviews as r
      where r.deleted_at is null and r.reviewed_at >= admin_overview.today_start),
    (select count(distinct r.user_id) from public.reviews as r
      where r.deleted_at is null and r.reviewed_at >= admin_overview.week_start),
    (select count(*) from public.extraction_usage as e
      where e.created_at >= date_trunc('day', now(), 'UTC'));
end;
$$;

-- Photo extractions per UTC day over the last 30 days, today included, oldest first, a day
-- without one as 0.
create function public.admin_extractions_by_day()
returns table (day date, extractions bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select d.day::date, count(e.id)
  from generate_series(
    date_trunc('day', now(), 'UTC') - interval '29 days',
    date_trunc('day', now(), 'UTC'),
    interval '1 day'
  ) as d (day)
  left join public.extraction_usage as e
    on e.created_at >= d.day and e.created_at < d.day + interval '1 day'
  group by d.day
  order by d.day;
end;
$$;

-- Every reported deck, the latest report first: its owner, state, report count and the reasons
-- given, each once.
create function public.admin_reported_decks()
returns table (
  deck_id uuid,
  name text,
  owner_id uuid,
  owner_email text,
  owner_name text,
  visibility text,
  hidden boolean,
  deleted boolean,
  reports bigint,
  reasons text[],
  last_reported_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select d.id, d.name, d.user_id, u.email::text, p.display_name, d.visibility, d.hidden,
    d.deleted_at is not null, r.reports, r.reasons, r.last_reported_at
  from (
    select x.deck_id, count(*) as reports, array_agg(distinct x.reason order by x.reason) as reasons,
      max(x.created_at) as last_reported_at
    from public.deck_reports as x
    group by x.deck_id
  ) as r
  join public.decks as d on d.id = r.deck_id
  join auth.users as u on u.id = d.user_id
  left join public.profiles as p on p.user_id = d.user_id
  order by r.last_reported_at desc, d.id;
end;
$$;

-- Every public deck, newest published first, whose name holds [search] ignoring case, or of
-- [owner] when it is set: its owner, live card count, copy count, reports and whether it is
-- hidden. Deleted decks are left out.
create function public.admin_public_decks(search text default '', owner uuid default null)
returns table (
  deck_id uuid,
  name text,
  owner_id uuid,
  owner_email text,
  owner_name text,
  hidden boolean,
  cards bigint,
  import_count integer,
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
    d.import_count,
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

-- One deck, when it is public or reported: its name, description, owner and state. Nothing for
-- another deck, so a user's private decks stay out of the admin area.
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
  import_count integer,
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
    d.hidden, d.deleted_at is not null, d.import_count,
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

-- The live cards of a deck [admin_deck] returns, oldest first, with both sides.
create function public.admin_deck_cards(deck_id uuid)
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
  where d.id = admin_deck_cards.deck_id
    and (d.visibility = 'public'
      or exists (select from public.deck_reports as x where x.deck_id = d.id))
  order by c.created_at, c.id;
end;
$$;

-- At most 50 users whose email holds [query] ignoring case, by email.
create function public.admin_find_users(query text)
returns table (user_id uuid, email text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select u.id, u.email::text, u.created_at
  from auth.users as u
  where not u.is_anonymous and admin_find_users.query <> ''
    and strpos(lower(u.email), lower(admin_find_users.query)) > 0
  order by u.email, u.id
  limit 50;
end;
$$;

-- One user: email, sign-up time, latest live answer, live decks and cards, extractions since
-- the start of the UTC day, and whether the user is an admin.
create function public.admin_user(user_id uuid)
returns table (
  id uuid,
  email text,
  created_at timestamptz,
  last_answer_at timestamptz,
  decks bigint,
  cards bigint,
  extractions_today bigint,
  admin boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select u.id, u.email::text, u.created_at,
    (select max(r.reviewed_at) from public.reviews as r
      where r.user_id = u.id and r.deleted_at is null),
    (select count(*) from public.decks as d where d.user_id = u.id and d.deleted_at is null),
    (select count(*) from public.cards as c
      join public.decks as d on d.user_id = c.user_id and d.id = c.deck_id and d.deleted_at is null
      where c.user_id = u.id and c.deleted_at is null),
    (select count(*) from public.extraction_usage as e
      where e.user_id = u.id and e.created_at >= date_trunc('day', now(), 'UTC')),
    exists (select from private.admins as a where a.user_id = u.id)
  from auth.users as u
  where u.id = admin_user.user_id;
end;
$$;

-- The admins, earliest granted first, with who granted each where that is known.
create function public.admin_admins()
returns table (user_id uuid, email text, granted_at timestamptz, granted_by_email text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select a.user_id, u.email::text, a.granted_at, g.email::text
  from private.admins as a
  join auth.users as u on u.id = a.user_id
  left join auth.users as g on g.id = a.granted_by
  order by a.granted_at, a.user_id;
end;
$$;

-- The audit log, newest first, [page_size] rows before the row [before] when it is set.
create function public.admin_audit_log(before bigint default null, page_size integer default 100)
returns table (
  id bigint,
  created_at timestamptz,
  admin_email text,
  action text,
  target_kind text,
  target_id text,
  detail jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select l.id, l.created_at, l.admin_email, l.action, l.target_kind, l.target_id, l.detail
  from private.admin_audit as l
  where admin_audit_log.before is null or l.id < admin_audit_log.before
  order by l.id desc
  limit least(greatest(admin_audit_log.page_size, 1), 500);
end;
$$;

-- Hides or unhides a deck and records it, returning true; false, recording nothing, for a deck
-- that does not exist or is already so. The update takes a new revision, as every deck write does.
create function public.admin_set_deck_hidden(deck_id uuid, hidden boolean) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  deck_name text;
begin
  perform private.require_admin();
  update public.decks as d set hidden = admin_set_deck_hidden.hidden
    where d.id = admin_set_deck_hidden.deck_id and d.hidden <> admin_set_deck_hidden.hidden
    returning d.name into deck_name;
  if not found then
    return false;
  end if;
  perform private.audit(case when admin_set_deck_hidden.hidden then 'hide_deck' else 'unhide_deck' end,
    'deck', admin_set_deck_hidden.deck_id::text, jsonb_build_object('name', deck_name));
  return true;
end;
$$;

-- Makes a public deck private and records it, returning true; false, recording nothing, for a
-- deck that is not public. Its edit time is now, so it wins over an older edit on a device, and
-- the owner's devices pull it as they pull a publish (sync.md).
create function public.admin_unpublish_deck(deck_id uuid) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  deck_name text;
begin
  perform private.require_admin();
  update public.decks as d set visibility = 'private', updated_at = now()
    where d.id = admin_unpublish_deck.deck_id and d.visibility = 'public'
    returning d.name into deck_name;
  if not found then
    return false;
  end if;
  perform private.audit('unpublish_deck', 'deck', admin_unpublish_deck.deck_id::text,
    jsonb_build_object('name', deck_name));
  return true;
end;
$$;

-- Deletes a deck's reports and records how many, returning that count; 0, recording nothing,
-- when it has none. A hidden deck stays hidden, and three new reports hide it again.
create function public.admin_dismiss_reports(deck_id uuid) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  dismissed integer;
begin
  perform private.require_admin();
  delete from public.deck_reports as x where x.deck_id = admin_dismiss_reports.deck_id;
  get diagnostics dismissed = row_count;
  if dismissed > 0 then
    perform private.audit('dismiss_reports', 'deck', admin_dismiss_reports.deck_id::text,
      jsonb_build_object('reports', dismissed));
  end if;
  return dismissed;
end;
$$;

-- Makes the user with [email] an admin and records it: 'granted'; 'already' for an admin, or
-- 'no_user' when no user has that email, recording nothing.
create function public.admin_grant_admin(email text) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := private.require_admin();
  grantee uuid;
begin
  select u.id into grantee from auth.users as u
    where lower(u.email) = lower(trim(admin_grant_admin.email)) and not u.is_anonymous;
  if grantee is null then
    return 'no_user';
  end if;
  insert into private.admins (user_id, granted_by) values (grantee, caller)
    on conflict (user_id) do nothing;
  if not found then
    return 'already';
  end if;
  perform private.audit('grant_admin', 'user', grantee::text,
    jsonb_build_object('email', lower(trim(admin_grant_admin.email))));
  return 'granted';
end;
$$;

-- Removes [user_id]'s admin role and records it: 'revoked'; 'self' for the caller's own, so the
-- last admin always remains, or 'not_admin', recording nothing.
create function public.admin_revoke_admin(user_id uuid) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := private.require_admin();
  revoked_email text;
begin
  if admin_revoke_admin.user_id = caller then
    return 'self';
  end if;
  delete from private.admins as a where a.user_id = admin_revoke_admin.user_id;
  if not found then
    return 'not_admin';
  end if;
  select u.email into revoked_email from auth.users as u where u.id = admin_revoke_admin.user_id;
  perform private.audit('revoke_admin', 'user', admin_revoke_admin.user_id::text,
    jsonb_build_object('email', coalesce(revoked_email, '')));
  return 'revoked';
end;
$$;

-- Every function above is the signed-in caller's to call; each checks the role itself.
revoke all on function
  public.is_admin(),
  public.admin_overview(timestamptz, timestamptz),
  public.admin_extractions_by_day(),
  public.admin_reported_decks(),
  public.admin_public_decks(text, uuid),
  public.admin_deck(uuid),
  public.admin_deck_cards(uuid),
  public.admin_find_users(text),
  public.admin_user(uuid),
  public.admin_admins(),
  public.admin_audit_log(bigint, integer),
  public.admin_set_deck_hidden(uuid, boolean),
  public.admin_unpublish_deck(uuid),
  public.admin_dismiss_reports(uuid),
  public.admin_grant_admin(text),
  public.admin_revoke_admin(uuid)
  from public, anon;
grant execute on function
  public.is_admin(),
  public.admin_overview(timestamptz, timestamptz),
  public.admin_extractions_by_day(),
  public.admin_reported_decks(),
  public.admin_public_decks(text, uuid),
  public.admin_deck(uuid),
  public.admin_deck_cards(uuid),
  public.admin_find_users(text),
  public.admin_user(uuid),
  public.admin_admins(),
  public.admin_audit_log(bigint, integer),
  public.admin_set_deck_hidden(uuid, boolean),
  public.admin_unpublish_deck(uuid),
  public.admin_dismiss_reports(uuid),
  public.admin_grant_admin(text),
  public.admin_revoke_admin(uuid)
  to authenticated;
