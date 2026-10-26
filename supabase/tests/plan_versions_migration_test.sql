-- The plan versions migration (20261026005136_plan_versions.sql, ADR 0097): on this database's
-- seed, what it made; then, on settings and grants as production holds them, each plan's settings
-- kept as its first version with its model and the owner's terms after them, Special's grants and
-- calls made Max's, everything it changed backed up, existing users kept on the terms before until
-- their renewal, a second run changing nothing, and the revert putting every plan back.
begin;
select plan(27);

-- What extract-cards gets for one photo of the user whose id ends in [who].
create function pg_temp.start(who text)
returns table (plan text, model text, photo_limit integer, period text)
language plpgsql as $$
begin
  perform set_config('role', 'service_role', true);
  return query select b.plan, b.model, b.photo_limit, b.period
    from public.begin_extraction(('00000000-0000-4000-8000-00000000000' || who)::uuid) as b;
  perform set_config('role', 'none', true);
end;
$$;

-- What the migration made of the seed: three plans on Haiku 5.5 at 30 a day.

select results_eq(
  $$select v.plan, v.quota, v.amount, v.model, v.applies_to_all, v.starts_at = b.updated_at
    from private.plan_versions as v
    join private.plans_before_versions as b on b.id = case v.plan when 'max' then 'special' else v.plan end
    order by array_position(array['free', 'pro', 'max'], v.plan), v.id$$,
  $$values
    ('free', 'daily', 30, 'anthropic/claude-haiku-5.5', false, true),
    ('free', 'monthly', 10, 'anthropic/claude-haiku-5.5', false, false),
    ('pro', 'daily', 30, 'anthropic/claude-haiku-5.5', false, true),
    ('pro', 'daily', 100, 'anthropic/claude-haiku-5.5', true, false),
    ('max', 'daily', 30, 'anthropic/claude-haiku-5.5', false, true),
    ('max', 'unlimited', 1000, 'anthropic/claude-haiku-5.5', true, false)$$,
  'on the seed: each plan''s settings as its first version from when they were set, then the owner''s terms on the same model, for all where they are in the users'' favour');
select results_eq(
  $$select id, model, daily_limit from private.plans_before_versions order by id$$,
  $$values ('free', 'anthropic/claude-haiku-5.5', 30), ('pro', 'anthropic/claude-haiku-5.5', 30),
           ('special', 'anthropic/claude-haiku-5.5', 30)$$,
  'the settings before are kept verbatim');
select results_eq(
  $$select admin_id, admin_email, action, target_kind, target_id, detail->>'quota'
    from private.admin_audit where action = 'create_plan_version' order by id$$,
  $$values
    (null::uuid, 'migration (owner delegated to PM, 2026-10-26)', 'create_plan_version', 'plan', 'free', 'monthly'),
    (null::uuid, 'migration (owner delegated to PM, 2026-10-26)', 'create_plan_version', 'plan', 'pro', 'daily'),
    (null::uuid, 'migration (owner delegated to PM, 2026-10-26)', 'create_plan_version', 'plan', 'max', 'unlimited')$$,
  'each version of the owner''s terms is recorded, by the migration');

-- Production's state before: Free on its own model at 30, Pro at 100 and Special at 200, each on
-- its model, set ten days before this month; a Pro grant, Special grants with an end, without one
-- and ended; and calls served by Special and by Free.

delete from private.admin_audit;
delete from private.user_plans;
delete from private.plan_versions;
update private.plans_before_versions as p set
  model = 'vendor/' || p.id || '-model',
  daily_limit = case p.id when 'free' then 30 when 'pro' then 100 else 200 end,
  updated_at = date_trunc('month', now(), 'Asia/Seoul') - interval '10 days';

insert into auth.users (id, email, created_at) values
  ('00000000-0000-4000-8000-00000000000a', 'admin@example.com', now() - interval '90 days'),
  ('00000000-0000-4000-8000-00000000000b', 'free@example.com', now() - interval '90 days'),
  ('00000000-0000-4000-8000-00000000000c', 'pro@example.com', now() - interval '90 days'),
  ('00000000-0000-4000-8000-00000000000d', 'special-end@example.com', now() - interval '90 days'),
  ('00000000-0000-4000-8000-00000000000e', 'special@example.com', now() - interval '90 days'),
  ('00000000-0000-4000-8000-00000000000f', 'ended@example.com', now() - interval '90 days'),
  ('00000000-0000-4000-8000-000000000001', 'this-month@example.com',
    date_trunc('month', now(), 'Asia/Seoul') + (now() - date_trunc('month', now(), 'Asia/Seoul')) / 4),
  ('00000000-0000-4000-8000-000000000002', 'new@example.com', now());
insert into private.user_plans_before_versions (user_id, plan, ends_at, granted_by, granted_at) values
  ('00000000-0000-4000-8000-00000000000c', 'pro', null, '00000000-0000-4000-8000-00000000000a', now() - interval '60 days'),
  ('00000000-0000-4000-8000-00000000000d', 'special', now() + interval '20 days', '00000000-0000-4000-8000-00000000000a', now() - interval '60 days'),
  ('00000000-0000-4000-8000-00000000000e', 'special', null, null, now() - interval '60 days'),
  ('00000000-0000-4000-8000-00000000000f', 'special', now() - interval '1 day', null, now() - interval '60 days');
create temp table fixture_calls (usage_id bigint, plan text);
with usage as (
  insert into public.extraction_usage (user_id) values
    ('00000000-0000-4000-8000-00000000000e'), ('00000000-0000-4000-8000-00000000000e'),
    ('00000000-0000-4000-8000-00000000000b')
  returning id
), numbered as (select id, row_number() over (order by id) as n from usage),
calls as (
  insert into private.extraction_calls (usage_id, plan, model, prompt_version_id)
    select id, case when n < 3 then 'special' else 'free' end, 'vendor/model', 1 from numbered
    returning usage_id, plan
) insert into fixture_calls select usage_id, plan from calls;

select private.migrate_plan_versions();

select results_eq(
  $$select plan, quota, amount, model, applies_to_all, starts_at = now()
    from private.plan_versions order by array_position(array['free', 'pro', 'max'], plan), id$$,
  $$values
    ('free', 'daily', 30, 'vendor/free-model', false, false),
    ('free', 'monthly', 10, 'vendor/free-model', false, true),
    ('pro', 'daily', 100, 'vendor/pro-model', false, false),
    ('max', 'daily', 200, 'vendor/special-model', false, false),
    ('max', 'unlimited', 1000, 'vendor/special-model', true, true)$$,
  'Free''s 10 a month from now, from each user''s renewal; Pro, already at 100 a day, given no second version; Max on Special''s model, unlimited, for all at once');
select results_eq(
  $$select g.user_id, g.plan, g.ends_at = b.ends_at or (g.ends_at is null and b.ends_at is null),
      g.granted_by is not distinct from b.granted_by, g.granted_at = b.granted_at, v.plan, v.amount
    from private.user_plans as g
    join private.user_plans_before_versions as b using (user_id)
    join private.plan_versions as v on v.id = g.version_id
    order by g.user_id$$,
  $$values
    ('00000000-0000-4000-8000-00000000000c'::uuid, 'pro', true, true, true, 'pro', 100),
    ('00000000-0000-4000-8000-00000000000d'::uuid, 'max', true, true, true, 'max', 200),
    ('00000000-0000-4000-8000-00000000000e'::uuid, 'max', true, true, true, 'max', 200),
    ('00000000-0000-4000-8000-00000000000f'::uuid, 'max', true, true, true, 'max', 200)$$,
  'each Special grant is Max''s, its end, granter and time kept, and every grant points at its plan''s first version');
select results_eq(
  $$select user_id, plan from private.user_plans_before_versions order by user_id$$,
  $$values ('00000000-0000-4000-8000-00000000000c'::uuid, 'pro'), ('00000000-0000-4000-8000-00000000000d'::uuid, 'special'),
           ('00000000-0000-4000-8000-00000000000e'::uuid, 'special'), ('00000000-0000-4000-8000-00000000000f'::uuid, 'special')$$,
  'the grants before are kept verbatim');
select results_eq(
  $$select c.plan, count(*) from private.extraction_calls as c join fixture_calls as f using (usage_id)
    group by c.plan order by c.plan$$,
  $$values ('free', 1::bigint), ('max', 2::bigint)$$,
  'each call served by Special is Max''s, and Free''s stays');
select set_eq(
  $$select usage_id from private.extraction_calls_before_versions$$,
  $$select usage_id from fixture_calls where plan = 'special'$$,
  'the converted calls'' ids are kept');
select results_eq(
  $$select target_id, detail->>'quota', (detail->>'amount')::int, detail->>'model', (detail->>'applies_to_all')::boolean,
      detail->>'quota_before', (detail->>'amount_before')::int
    from private.admin_audit order by id$$,
  $$values ('free', 'monthly', 10, 'vendor/free-model', false, 'daily', 30),
           ('max', 'unlimited', 1000, 'vendor/special-model', true, 'daily', 200)$$,
  'and each version of the owner''s terms is recorded');

-- Each user's terms.

select results_eq($$select * from pg_temp.start('b')$$, $$values ('free', 'vendor/free-model', 30, 'day')$$,
  'an existing Free user keeps 30 a day, now counted from 00:00 in Seoul, until its renewal');
reset role;
select results_eq($$select * from pg_temp.start('1')$$, $$values ('free', 'vendor/free-model', 30, 'day')$$,
  'and so does one who signed up this month before the migration');
reset role;
select results_eq($$select photo_limit from pg_temp.start('2')$$, $$values (10)$$,
  'control: a user who signs up after it is on 10 a month at once');
reset role;
select results_eq(
  $$select quota, amount from private.plan_version_at('free', date_trunc('month', now(), 'Asia/Seoul') + interval '1 month')$$,
  $$values ('monthly', 10)$$, 'the version an existing Free user renews onto on the 1st of next month');
select results_eq($$select * from pg_temp.start('c')$$, $$values ('pro', 'vendor/pro-model', 100, 'day')$$,
  'a Pro user keeps 100 a day');
reset role;
select results_eq(
  $$select * from pg_temp.start('d') union all select * from pg_temp.start('e')$$,
  $$values ('max', 'vendor/special-model', 1000, 'day'), ('max', 'vendor/special-model', 1000, 'day')$$,
  'a Special user is on Max at once, unlimited with 1,000 a day, on Special''s model');
reset role;
select results_eq($$select plan, photo_limit from pg_temp.start('f')$$, $$values ('free', 30)$$,
  'an ended Special is on Free');
reset role;
select results_eq(
  $$select count(*) from public.extraction_usage where user_id = '00000000-0000-4000-8000-00000000000e'$$,
  $$values (3::bigint)$$,
  'the photos counted before the migration stay counted: the Max user''s two and the one just begun');

select throws_ok(
  $$insert into private.user_plans (user_id, plan, version_id) values
    ('00000000-0000-4000-8000-00000000000b', 'special', (select min(id) from private.plan_versions))$$,
  '23514', null, 'no grant can be Special''s any more');
select throws_ok(
  $$insert into private.user_plans (user_id, plan, version_id) values
    ('00000000-0000-4000-8000-00000000000b', 'pro', (select min(id) from private.plan_versions where plan = 'max'))$$,
  '23503', null, 'nor point at another plan''s version');

-- A second run.

create temp table counts as select
  (select count(*) from private.plan_versions) as versions,
  (select count(*) from private.admin_audit) as audit,
  (select string_agg(user_id || plan || version_id, ',' order by user_id) from private.user_plans) as grants,
  (select count(*) from private.extraction_calls_before_versions) as calls;
select private.migrate_plan_versions();
select results_eq(
  $$select (select count(*) from private.plan_versions), (select count(*) from private.admin_audit),
      (select string_agg(user_id || plan || version_id, ',' order by user_id) from private.user_plans),
      (select count(*) from private.extraction_calls_before_versions)$$,
  $$select versions, audit, grants, calls from counts$$,
  'a second run changes nothing');

-- No client reaches the backups or the migration's functions.

select results_eq(
  $$select count(*) from unnest(array['private.plans_before_versions', 'private.user_plans_before_versions',
      'private.extraction_calls_before_versions', 'private.plan_versions']) as t
    cross join unnest(array['anon', 'authenticated']) as r
    where has_table_privilege(r, t, 'select') or has_table_privilege(r, t, 'insert')$$,
  $$values (0::bigint)$$, 'no client role reads or writes the versions or the backups');
select results_eq(
  $$select count(*) from unnest(array['private.migrate_plan_versions()', 'private.revert_plan_versions()',
      'private.entitlement_of(uuid)']) as f
    cross join unnest(array['anon', 'authenticated', 'service_role']) as r
    where has_function_privilege(r, f, 'execute')$$,
  $$values (0::bigint)$$, 'and none runs the migration''s functions');
select ok(has_function_privilege('service_role', 'public.begin_extraction(uuid)', 'execute'),
  'control: service_role runs begin_extraction, which calls them as its owner');

-- The revert.

select is(private.revert_plan_versions(), 3, 'the revert adds a version for each plan');
select results_eq(
  $$select * from pg_temp.start('2') union all select * from pg_temp.start('c')
    union all select * from pg_temp.start('e')$$,
  $$values ('free', 'vendor/free-model', 30, 'day'), ('pro', 'vendor/pro-model', 100, 'day'),
           ('max', 'vendor/special-model', 200, 'day')$$,
  'putting every user, new or existing, back on its plan''s settings before');
reset role;
select results_eq(
  $$select admin_email, target_id, (detail->>'amount')::int from private.admin_audit
    where admin_email like 'revert%' order by id$$,
  $$values ('revert of 20261026005136_plan_versions.sql (PM)', 'free', 30),
           ('revert of 20261026005136_plan_versions.sql (PM)', 'pro', 100),
           ('revert of 20261026005136_plan_versions.sql (PM)', 'max', 200)$$,
  'each recorded');

-- Account deletion.

delete from auth.users where id in ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000d');
select results_eq(
  $$select user_id, granted_by from private.user_plans_before_versions order by user_id$$,
  $$values ('00000000-0000-4000-8000-00000000000c'::uuid, null::uuid), ('00000000-0000-4000-8000-00000000000e'::uuid, null::uuid),
           ('00000000-0000-4000-8000-00000000000f'::uuid, null::uuid)$$,
  'a deleted user''s backed-up grant goes with it, and a deleted granter is cleared');

select * from finish();
rollback;
