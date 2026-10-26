-- Plans as versioned entitlements (#341, ADR 0097): Free 10 photos a calendar month in Asia/Seoul,
-- Pro 100 a day, and Max, which replaces Special, unlimited with a fair-use cap of 1,000 a day.
-- A plan's terms are versions, each with a start: a new grant takes the version in effect when it
-- begins, an existing one the version in effect at its renewal, the 1st of each month at 00:00
-- Asia/Seoul, and a version in the users' favour may apply to everyone from its start.
--
-- It changes existing data, by the owner's delegation to the PM (#341, 2026-10-26):
-- - each plan's settings become its first version, from when they were last set; the owner's
--   terms become a second version from now, for everyone at once where they are in the users'
--   favour and from each user's renewal otherwise;
-- - each Special grant becomes a Max grant, and each recorded call served by Special a call
--   served by Max.
-- Backups, read by nothing but the revert: `private.plans` is kept verbatim as
-- `private.plans_before_versions`, the grants as `private.user_plans_before_versions`, and the
-- converted calls' ids in `private.extraction_calls_before_versions`.
-- Revert: `select private.revert_plan_versions();` puts every plan back on its settings before.

-- The settings before, verbatim, as the backup of every plan row this migration replaces.
alter table private.plans rename to plans_before_versions;
alter index private.plans_updated_by rename to plans_before_versions_updated_by;
alter table private.user_plans drop constraint user_plans_plan_fkey;

-- Every grant before, verbatim. A row goes with its user, and a granter's deletion clears it.
create table private.user_plans_before_versions (
  user_id uuid primary key references auth.users on delete cascade,
  plan text not null,
  ends_at timestamptz,
  granted_by uuid references auth.users on delete set null,
  granted_at timestamptz not null
);
create index user_plans_before_versions_granted_by on private.user_plans_before_versions (granted_by);
insert into private.user_plans_before_versions (user_id, plan, ends_at, granted_by, granted_at)
  select p.user_id, p.plan, p.ends_at, p.granted_by, p.granted_at from private.user_plans as p;

-- Each version of a plan's terms. `quota` is how photos are counted: `monthly`, `amount` a
-- calendar month in Asia/Seoul; `daily`, `amount` a day there; or `unlimited`, with `amount` the
-- fair-use cap a day. `applies_to_all` puts existing users on it from its start, not their renewal.
create table private.plan_versions (
  id bigint generated always as identity primary key,
  plan text not null check (plan in ('free', 'pro', 'max')),
  quota text not null check (quota in ('monthly', 'daily', 'unlimited')),
  amount integer not null check (amount between 0 and 100000),
  model text not null check (model ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:-]+$'),
  starts_at timestamptz not null,
  applies_to_all boolean not null default false,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now(),
  unique (id, plan)
);
-- A plan's version at a time, the latest started by then; and the set null of an editor's deletion.
create index plan_versions_plan_starts_at_id on private.plan_versions (plan, starts_at, id);
create index plan_versions_created_by on private.plan_versions (created_by);

-- The ids of the calls this migration moved from Special to Max. A row goes with its call.
create table private.extraction_calls_before_versions (
  usage_id bigint primary key references private.extraction_calls on delete cascade
);

alter table private.plan_versions enable row level security;
alter table private.user_plans_before_versions enable row level security;
alter table private.extraction_calls_before_versions enable row level security;
revoke all on private.plan_versions, private.user_plans_before_versions,
  private.extraction_calls_before_versions
  from public, anon, authenticated, service_role;

-- A grant points at the version of its own plan in effect when it began.
alter table private.user_plans drop constraint user_plans_plan_check;
alter table private.user_plans drop constraint user_plans_check;
alter table private.user_plans add column version_id bigint;

-- [plan]'s version a term beginning at [at] takes: the latest started by then, or the plan's first
-- when none had; null for a plan without versions.
create function private.plan_version_at(plan text, at timestamptz) returns private.plan_versions
language sql
stable
set search_path = ''
as $$
  select v.* from private.plan_versions as v
  where v.plan = plan_version_at.plan
  order by v.starts_at <= plan_version_at.at desc,
    case when v.starts_at <= plan_version_at.at then v.starts_at end desc,
    v.starts_at, v.id desc
  limit 1;
$$;

-- Whether a version of [plan] on these terms from [starts_at] is in the users' favour: every
-- version started by then has the same model, counts no more generously (monthly, then daily,
-- then unlimited) and allows no more photos in its period.
create function private.in_favour(
  plan text, quota text, amount integer, model text, starts_at timestamptz
) returns boolean
language sql
stable
set search_path = ''
as $$
  select not exists (
    select from private.plan_versions as v
    where v.plan = in_favour.plan and v.starts_at <= in_favour.starts_at
      and (v.model <> in_favour.model
        or array_position(array['monthly', 'daily', 'unlimited'], v.quota)
          > array_position(array['monthly', 'daily', 'unlimited'], in_favour.quota)
        or v.amount > in_favour.amount)
  );
$$;

-- What [user_id] is entitled to now: the plan, its version and the start of the period its photos
-- are counted from. The plan is the grant's while it has not ended, else Free. A grant begun since
-- the last renewal keeps the version it began on, and an earlier one takes the version in effect at
-- that renewal; a Free user takes Free's version at its sign-up or the renewal, the later. A later
-- version of the plan that applies to all and has started overrides either. No row when the plan
-- has no version.
create function private.entitlement_of(user_id uuid)
returns table (
  plan text, version_id bigint, quota text, amount integer, model text, period_start timestamptz
)
language plpgsql
stable
set search_path = ''
as $$
declare
  renewed timestamptz := date_trunc('month', now(), 'Asia/Seoul');
  grant_row private.user_plans;
  signed_up timestamptz;
  base private.plan_versions;
  chosen private.plan_versions;
begin
  select g.* into grant_row from private.user_plans as g
    where g.user_id = entitlement_of.user_id and (g.ends_at is null or g.ends_at > now());
  if found and grant_row.granted_at > renewed then
    select v.* into base from private.plan_versions as v where v.id = grant_row.version_id;
  elsif found then
    base := private.plan_version_at(grant_row.plan, renewed);
  else
    select u.created_at into signed_up from auth.users as u where u.id = entitlement_of.user_id;
    base := private.plan_version_at('free', greatest(signed_up, renewed));
  end if;
  if base.id is null then
    return;
  end if;
  select v.* into chosen from private.plan_versions as v
    where v.plan = base.plan and v.applies_to_all and v.starts_at <= now()
      and (v.starts_at, v.id) > (base.starts_at, base.id)
    order by v.starts_at desc, v.id desc
    limit 1;
  if not found then
    chosen := base;
  end if;
  return query select chosen.plan, chosen.id, chosen.quota, chosen.amount, chosen.model,
    case chosen.quota
      when 'monthly' then date_trunc('month', now(), 'Asia/Seoul')
      else date_trunc('day', now(), 'Asia/Seoul')
    end;
end;
$$;

-- The period a quota's photos are counted over, as the function and the app name it.
create function private.quota_period(quota text) returns text
language sql
immutable
set search_path = ''
as $$
  select case quota_period.quota when 'monthly' then 'month' else 'day' end;
$$;

-- Moves the settings and grants before versions into versions, as this migration does once:
-- each plan in `private.plans_before_versions` without a version gets its settings as a first
-- version from when they were last set, Special's as Max's, and the owner's terms as a second
-- version from now, recorded, unless they are the first's; each grant in the backup whose user has
-- no versioned grant points at its plan's first version, Special's as Max; and each call recorded
-- as Special's becomes Max's, its id kept. A second run changes nothing.
create function private.migrate_plan_versions() returns void
language plpgsql
set search_path = ''
as $$
declare
  setting private.plans_before_versions;
  target text;
  original private.plan_versions;
  terms record;
  added bigint;
begin
  for setting in select * from private.plans_before_versions as p
    order by array_position(array['free', 'pro', 'special'], p.id)
  loop
    target := case setting.id when 'special' then 'max' else setting.id end;
    continue when exists (select from private.plan_versions as v where v.plan = target);
    insert into private.plan_versions (plan, quota, amount, model, starts_at, created_by)
      values (target, 'daily', setting.daily_limit, setting.model, setting.updated_at, setting.updated_by)
      returning * into original;
    select * into terms from (values
      ('free', 'monthly', 10), ('pro', 'daily', 100), ('max', 'unlimited', 1000)
    ) as t (plan, quota, amount) where t.plan = target;
    continue when terms.quota = original.quota and terms.amount = original.amount;
    insert into private.plan_versions (plan, quota, amount, model, starts_at, applies_to_all)
      values (target, terms.quota, terms.amount, original.model, now(),
        private.in_favour(target, terms.quota, terms.amount, original.model, now()))
      returning id into added;
    insert into private.admin_audit (admin_id, admin_email, action, target_kind, target_id, detail)
      select null, 'migration (owner delegated to PM, 2026-10-26)', 'create_plan_version', 'plan',
        target, jsonb_build_object('version_id', v.id, 'quota', v.quota, 'amount', v.amount,
          'model', v.model, 'starts_at', v.starts_at, 'applies_to_all', v.applies_to_all,
          'quota_before', original.quota, 'amount_before', original.amount, 'model_before', original.model)
      from private.plan_versions as v where v.id = added;
  end loop;

  insert into private.user_plans as g (user_id, plan, ends_at, granted_by, granted_at, version_id)
    select b.user_id, m.plan, b.ends_at, b.granted_by, b.granted_at,
      (select v.id from private.plan_versions as v where v.plan = m.plan
        order by v.starts_at, v.id limit 1)
    from private.user_plans_before_versions as b
    cross join lateral (select case b.plan when 'special' then 'max' else b.plan end as plan) as m
    on conflict on constraint user_plans_pkey do update
      set plan = excluded.plan, version_id = excluded.version_id
      where g.version_id is null;

  with converted as (
    update private.extraction_calls as c set plan = 'max' where c.plan = 'special'
      returning c.usage_id
  )
  insert into private.extraction_calls_before_versions (usage_id)
    select converted.usage_id from converted
    on conflict do nothing;
end;
$$;

select private.migrate_plan_versions();

alter table private.user_plans
  alter column version_id set not null,
  add constraint user_plans_plan_check check (plan in ('pro', 'max')),
  add constraint user_plans_check check (plan = 'max' or ends_at is null),
  add constraint user_plans_version_id_plan_fkey foreign key (version_id, plan)
    references private.plan_versions (id, plan);
-- The reference's check when a version is removed, which only a revert of a later change would do.
create index user_plans_version_id on private.user_plans (version_id);

-- Puts every plan back on its settings before this migration: a version holding them, from now,
-- for everyone at once, Special's as Max's, each recorded. Returns how many it added. Max keeps
-- its name; a return to the tables before is a later migration from the backups.
create function private.revert_plan_versions() returns integer
language plpgsql
set search_path = ''
as $$
declare
  added integer := 0;
  setting private.plans_before_versions;
  version private.plan_versions;
begin
  for setting in select * from private.plans_before_versions as p
    order by array_position(array['free', 'pro', 'special'], p.id)
  loop
    insert into private.plan_versions (plan, quota, amount, model, starts_at, applies_to_all)
      values (case setting.id when 'special' then 'max' else setting.id end, 'daily',
        setting.daily_limit, setting.model, now(), true)
      returning * into version;
    insert into private.admin_audit (admin_id, admin_email, action, target_kind, target_id, detail)
      values (null, 'revert of 20261026005136_plan_versions.sql (PM)', 'create_plan_version',
        'plan', version.plan, jsonb_build_object('version_id', version.id, 'quota', version.quota,
          'amount', version.amount, 'model', version.model, 'starts_at', version.starts_at,
          'applies_to_all', true));
    added := added + 1;
  end loop;
  return added;
end;
$$;

revoke all on function
  private.plan_version_at(text, timestamptz),
  private.in_favour(text, text, integer, text, timestamptz),
  private.entitlement_of(uuid),
  private.quota_period(text),
  private.migrate_plan_versions(),
  private.revert_plan_versions()
  from public, anon, authenticated;

drop function private.plan_of(uuid);

-- Resolves [user_id]'s plan, its version and prompt, and, under the version's quota for its
-- period, records the photo with what serves it, under the extraction lock. An admin is served the
-- 'test' version when one is set, everyone else the 'active' one. No row while the plan has no
-- version or the active prompt is missing.
drop function public.begin_extraction(uuid);
create function public.begin_extraction(user_id uuid)
returns table (
  plan text, model text, photo_limit integer, period text, allowed boolean,
  prompt_version_id bigint, prompt text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  entitled record;
  version private.prompt_versions;
  used bigint;
  usage bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(begin_extraction.user_id::text, 1));
  select * into entitled from private.entitlement_of(begin_extraction.user_id);
  if not found then
    return;
  end if;
  select v.* into version
  from private.prompt_labels as l
  join private.prompt_versions as v on v.id = l.version_id
  where l.label = 'active'
    or (l.label = 'test'
      and exists (select 1 from private.admins as a where a.user_id = begin_extraction.user_id))
  order by l.label = 'test' desc
  limit 1;
  if not found then
    return;
  end if;
  select count(*) into used from public.extraction_usage as u
    where u.user_id = begin_extraction.user_id and u.created_at >= entitled.period_start;
  if used < entitled.amount then
    insert into public.extraction_usage (user_id) values (begin_extraction.user_id)
      returning id into usage;
    insert into private.extraction_calls (usage_id, plan, model, prompt_version_id)
      values (usage, entitled.plan, entitled.model, version.id);
  end if;
  return query select entitled.plan, entitled.model, entitled.amount,
    private.quota_period(entitled.quota), used < entitled.amount, version.id, version.text;
end;
$$;

revoke all on function public.begin_extraction(uuid) from public, anon, authenticated;
grant execute on function public.begin_extraction(uuid) to service_role;

-- The caller's photo limit, the period it counts over and the photos counted in it: the version
-- begin_extraction resolves and the rows it counts, so the two agree. No row while the plan has no
-- version. Only the caller's own; it takes no user.
drop function public.extraction_allowance();
create function public.extraction_allowance()
returns table (photo_limit integer, period text, used integer)
language sql
stable
security definer
set search_path = ''
as $$
  select e.amount, private.quota_period(e.quota),
    (select count(*) from public.extraction_usage as u
      where u.user_id = (select auth.uid()) and u.created_at >= e.period_start)::integer
  from private.entitlement_of((select auth.uid())) as e
  where (select auth.uid()) is not null
$$;

revoke all on function public.extraction_allowance() from public, anon;
grant execute on function public.extraction_allowance() to authenticated;

drop function public.admin_plans();
drop function public.admin_set_plan(text, text, integer);
drop function public.admin_user_plan(uuid);

-- Every plan version, Free's first, then Pro's and Max's, each plan's latest start first, with
-- whether it is the one a user subscribing now takes, and who created it where that is known.
create function public.admin_plan_versions()
returns table (
  id bigint, plan text, quota text, amount integer, model text, starts_at timestamptz,
  applies_to_all boolean, current boolean, created_at timestamptz, created_by_email text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select v.id, v.plan, v.quota, v.amount, v.model, v.starts_at, v.applies_to_all,
    v.id = (private.plan_version_at(v.plan, now())).id, v.created_at, u.email::text
  from private.plan_versions as v
  left join auth.users as u on u.id = v.created_by
  order by array_position(array['free', 'pro', 'max'], v.plan), v.starts_at desc, v.id desc;
end;
$$;

-- Creates a version of [plan] on these terms from [starts_at], now when null, for users who
-- subscribe from then and for the others at their renewal, or for everyone from then with
-- [applies_to_all], and records it: 'created'; 'past_start' for a start before now, 'unchanged'
-- for the terms a user subscribing then would already get, and 'not_in_favour' for applying to
-- all terms not in the users' favour, each recording nothing. An unknown plan or quota, a model id
-- of another form and an amount outside 0 to 100,000 are refused by the table's checks.
create function public.admin_create_plan_version(
  plan text, quota text, amount integer, model text, starts_at timestamptz default null,
  applies_to_all boolean default false
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := private.require_admin();
  start timestamptz := coalesce(admin_create_plan_version.starts_at, now());
  previous private.plan_versions;
  added private.plan_versions;
begin
  if start < now() then
    return 'past_start';
  end if;
  -- Versions are created one at a time, under a lock seeded with 5, so two cannot read one previous.
  perform pg_advisory_xact_lock(hashtextextended('private.plan_versions', 5));
  previous := private.plan_version_at(admin_create_plan_version.plan, start);
  if previous.quota = admin_create_plan_version.quota
    and previous.amount = admin_create_plan_version.amount
    and previous.model = admin_create_plan_version.model
  then
    return 'unchanged';
  end if;
  if admin_create_plan_version.applies_to_all and not private.in_favour(
    admin_create_plan_version.plan, admin_create_plan_version.quota,
    admin_create_plan_version.amount, admin_create_plan_version.model, start)
  then
    return 'not_in_favour';
  end if;
  insert into private.plan_versions (plan, quota, amount, model, starts_at, applies_to_all, created_by)
    values (admin_create_plan_version.plan, admin_create_plan_version.quota,
      admin_create_plan_version.amount, admin_create_plan_version.model, start,
      admin_create_plan_version.applies_to_all, caller)
    returning * into added;
  perform private.audit('create_plan_version', 'plan', added.plan, jsonb_build_object(
    'version_id', added.id, 'quota', added.quota, 'amount', added.amount, 'model', added.model,
    'starts_at', added.starts_at, 'applies_to_all', added.applies_to_all,
    'quota_before', previous.quota, 'amount_before', previous.amount,
    'model_before', previous.model));
  return 'created';
end;
$$;

-- [user_id]'s entitlement now, with the photos counted in its period, and the grant behind it when
-- there is one: its plan, its end and who granted it when. A grant of Max that has ended shows with
-- the user on Free; the entitlement's columns are null while the plan has no version. No row for a
-- user that does not exist.
create function public.admin_user_plan(user_id uuid)
returns table (
  plan text,
  version_id bigint,
  quota text,
  amount integer,
  model text,
  used integer,
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
  select e.plan, e.version_id, e.quota, e.amount, e.model,
    case when e.plan is not null then (select count(*) from public.extraction_usage as x
      where x.user_id = u.id and x.created_at >= e.period_start)::integer end,
    g.plan, g.ends_at, g.granted_at, b.email::text
  from auth.users as u
  left join lateral private.entitlement_of(u.id) as e on true
  left join private.user_plans as g on g.user_id = u.id
  left join auth.users as b on b.id = g.granted_by
  where u.id = admin_user_plan.user_id;
end;
$$;

-- Puts [user_id] on Pro, or on Max until [ends_at] or without an end, on the plan's version a user
-- subscribing now takes, replacing any grant, and records it: 'granted'; 'no_user' for a user that
-- does not exist, 'bad_plan' for any other plan, a plan without a version, an end on Pro or an end
-- not in the future, recording nothing.
create or replace function public.admin_grant_plan(user_id uuid, plan text, ends_at timestamptz default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  version bigint;
begin
  perform private.require_admin();
  if not exists (select from auth.users as u where u.id = admin_grant_plan.user_id) then
    return 'no_user';
  end if;
  version := (private.plan_version_at(admin_grant_plan.plan, now())).id;
  if admin_grant_plan.plan not in ('pro', 'max')
    or version is null
    or (admin_grant_plan.plan = 'pro' and admin_grant_plan.ends_at is not null)
    or admin_grant_plan.ends_at <= now()
  then
    return 'bad_plan';
  end if;
  insert into private.user_plans (user_id, plan, ends_at, granted_by, version_id)
    values (admin_grant_plan.user_id, admin_grant_plan.plan, admin_grant_plan.ends_at,
      (select auth.uid()), version)
    on conflict on constraint user_plans_pkey do update
      set plan = excluded.plan, ends_at = excluded.ends_at, granted_by = excluded.granted_by,
        granted_at = now(), version_id = excluded.version_id;
  perform private.audit('grant_plan', 'user', admin_grant_plan.user_id::text, jsonb_build_object(
    'email', (select u.email from auth.users as u where u.id = admin_grant_plan.user_id),
    'plan', admin_grant_plan.plan, 'ends_at', admin_grant_plan.ends_at, 'version_id', version));
  return 'granted';
end;
$$;

revoke all on function
  public.admin_plan_versions(),
  public.admin_create_plan_version(text, text, integer, text, timestamptz, boolean),
  public.admin_user_plan(uuid)
  from public, anon;
grant execute on function
  public.admin_plan_versions(),
  public.admin_create_plan_version(text, text, integer, text, timestamptz, boolean),
  public.admin_user_plan(uuid)
  to authenticated;
