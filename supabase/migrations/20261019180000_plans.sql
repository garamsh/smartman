-- Plans (#224, ADR 0071): each user is on Free, Pro or Special, and each plan has the model that
-- serves its photos and its daily photo limit, which an admin sets in the admin area. The
-- extract-cards function reads the caller's plan here at each call. Additive: it creates two
-- tables, seeds the three plans as data the admin area edits, and creates functions; it changes no
-- existing row or object. Every plan starts on the model and the limit production runs now.

-- The plans and their settings. A model id has the form `vendor/model`, the rule the function
-- applies before it calls a model.
create table private.plans (
  id text primary key check (id in ('free', 'pro', 'special')),
  model text not null check (model ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:-]+$'),
  daily_limit integer not null check (daily_limit between 0 and 1000),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users on delete set null
);

insert into private.plans (id, model, daily_limit) values
  ('free', 'anthropic/claude-haiku-5.5', 30),
  ('pro', 'anthropic/claude-haiku-5.5', 30),
  ('special', 'anthropic/claude-haiku-5.5', 30);

-- A user's plan other than Free. A user without a row is on Free, and so is one whose Special
-- plan has ended; only Special may end.
create table private.user_plans (
  user_id uuid primary key references auth.users on delete cascade,
  plan text not null references private.plans check (plan in ('pro', 'special')),
  ends_at timestamptz check (plan = 'special' or ends_at is null),
  granted_by uuid references auth.users on delete set null,
  granted_at timestamptz not null default now()
);

-- The account-deletion cascade and set null through the columns no primary key leads with.
create index plans_updated_by on private.plans (updated_by);
create index user_plans_granted_by on private.user_plans (granted_by);

alter table private.plans enable row level security;
alter table private.user_plans enable row level security;
revoke all on private.plans, private.user_plans from public, anon, authenticated;

-- The plan [user_id] is on now: its own Pro, or Special that has not ended, else Free.
create function private.plan_of(user_id uuid) returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.plan from private.user_plans as p
      where p.user_id = plan_of.user_id and (p.ends_at is null or p.ends_at > now())),
    'free'
  );
$$;

revoke all on function private.plan_of(uuid) from public, anon, authenticated;

-- What extract-cards does for one photo of [user_id]: the user's plan, its model and daily limit,
-- and whether the photo is allowed. An allowed photo is recorded, as consume_extraction records
-- one, under the same lock, so the two count together while both exist; a photo over the plan's
-- limit since the start of the UTC day records nothing. No row when the plan's settings are
-- missing, which the function answers as not configured.
create function public.start_extraction(user_id uuid)
returns table (plan text, model text, daily_limit integer, allowed boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings private.plans;
  used bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(start_extraction.user_id::text, 1));
  select * into settings from private.plans as p where p.id = private.plan_of(start_extraction.user_id);
  if not found then
    return;
  end if;
  select count(*) into used from public.extraction_usage as u
    where u.user_id = start_extraction.user_id
      and u.created_at >= date_trunc('day', now(), 'UTC');
  if used < settings.daily_limit then
    insert into public.extraction_usage (user_id) values (start_extraction.user_id);
  end if;
  return query select settings.id, settings.model, settings.daily_limit, used < settings.daily_limit;
end;
$$;

revoke all on function public.start_extraction(uuid) from public, anon, authenticated;
grant execute on function public.start_extraction(uuid) to service_role;

-- The plans and their settings, Free first, with who last changed each where that is known.
create function public.admin_plans()
returns table (id text, model text, daily_limit integer, updated_at timestamptz, updated_by_email text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select p.id, p.model, p.daily_limit, p.updated_at, u.email::text
  from private.plans as p
  left join auth.users as u on u.id = p.updated_by
  order by array_position(array['free', 'pro', 'special'], p.id);
end;
$$;

-- Sets [plan]'s model and daily limit and records it with the settings before, returning true;
-- false, recording nothing, for a plan that does not exist or already has them. A model id of
-- another form, or a limit outside 0 to 1000, is refused by the table's checks.
create function public.admin_set_plan(plan text, model text, daily_limit integer) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous private.plans;
begin
  perform private.require_admin();
  select * into previous from private.plans as p where p.id = admin_set_plan.plan for update;
  if not found
    or (previous.model = admin_set_plan.model and previous.daily_limit = admin_set_plan.daily_limit)
  then
    return false;
  end if;
  update private.plans as p
    set model = admin_set_plan.model, daily_limit = admin_set_plan.daily_limit,
      updated_at = now(), updated_by = (select auth.uid())
    where p.id = admin_set_plan.plan;
  perform private.audit('set_plan', 'plan', admin_set_plan.plan, jsonb_build_object(
    'model', admin_set_plan.model, 'daily_limit', admin_set_plan.daily_limit,
    'model_before', previous.model, 'daily_limit_before', previous.daily_limit));
  return true;
end;
$$;

-- [user_id]'s plan now, with its model and daily limit, and the grant behind it when there is
-- one: its plan, its end and who granted it when. A grant of Special that has ended shows with
-- the user on Free; the plan's columns are null while its settings are missing. No row for a user
-- that does not exist.
create function public.admin_user_plan(user_id uuid)
returns table (
  plan text,
  model text,
  daily_limit integer,
  granted_plan text,
  ends_at timestamptz,
  granted_at timestamptz,
  granted_by_email text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select s.id, s.model, s.daily_limit, g.plan, g.ends_at, g.granted_at, b.email::text
  from auth.users as u
  left join private.plans as s on s.id = private.plan_of(u.id)
  left join private.user_plans as g on g.user_id = u.id
  left join auth.users as b on b.id = g.granted_by
  where u.id = admin_user_plan.user_id;
end;
$$;

-- Puts [user_id] on Pro, or on Special until [ends_at] or without an end, replacing any grant,
-- and records it: 'granted'; 'no_user' for a user that does not exist, 'bad_plan' for any other
-- plan, an end on Pro or an end not in the future, recording nothing.
create function public.admin_grant_plan(user_id uuid, plan text, ends_at timestamptz default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  if not exists (select from auth.users as u where u.id = admin_grant_plan.user_id) then
    return 'no_user';
  end if;
  if admin_grant_plan.plan not in ('pro', 'special')
    or (admin_grant_plan.plan = 'pro' and admin_grant_plan.ends_at is not null)
    or admin_grant_plan.ends_at <= now()
  then
    return 'bad_plan';
  end if;
  insert into private.user_plans (user_id, plan, ends_at, granted_by)
    values (admin_grant_plan.user_id, admin_grant_plan.plan, admin_grant_plan.ends_at, (select auth.uid()))
    on conflict on constraint user_plans_pkey do update
      set plan = excluded.plan, ends_at = excluded.ends_at, granted_by = excluded.granted_by,
        granted_at = now();
  perform private.audit('grant_plan', 'user', admin_grant_plan.user_id::text, jsonb_build_object(
    'email', (select u.email from auth.users as u where u.id = admin_grant_plan.user_id),
    'plan', admin_grant_plan.plan, 'ends_at', admin_grant_plan.ends_at));
  return 'granted';
end;
$$;

-- Puts [user_id] back on Free and records it, returning true; false, recording nothing, for a
-- user without a grant.
create function public.admin_revoke_plan(user_id uuid) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  revoked text;
begin
  perform private.require_admin();
  delete from private.user_plans as p where p.user_id = admin_revoke_plan.user_id
    returning p.plan into revoked;
  if not found then
    return false;
  end if;
  perform private.audit('revoke_plan', 'user', admin_revoke_plan.user_id::text, jsonb_build_object(
    'email', coalesce((select u.email from auth.users as u where u.id = admin_revoke_plan.user_id), ''),
    'plan', revoked));
  return true;
end;
$$;

revoke all on function
  public.admin_plans(),
  public.admin_set_plan(text, text, integer),
  public.admin_user_plan(uuid),
  public.admin_grant_plan(uuid, text, timestamptz),
  public.admin_revoke_plan(uuid)
  from public, anon;
grant execute on function
  public.admin_plans(),
  public.admin_set_plan(text, text, integer),
  public.admin_user_plan(uuid),
  public.admin_grant_plan(uuid, text, timestamptz),
  public.admin_revoke_plan(uuid)
  to authenticated;
