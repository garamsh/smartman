-- Plans (ADR 0071): each user's plan resolves to Free, Pro or an unended Special; extract-cards
-- counts a photo by its plan's limit and learns its model; only an admin sets plans and grants
-- them, each write recorded.
begin;
select plan(34);

-- The log starts empty here: a migration may record a change of its own, as
-- 20261019230002_activate_prompt_v9.sql records prompt v9's activation.
delete from private.admin_audit;

-- A is an admin, B a signed-in user who is not, C, D and E users on each plan.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'admin@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'user@example.com'),
  ('00000000-0000-4000-8000-00000000000c', 'pro@example.com'),
  ('00000000-0000-4000-8000-00000000000d', 'special@example.com'),
  ('00000000-0000-4000-8000-00000000000e', 'ended@example.com');
insert into private.admins (user_id) values ('00000000-0000-4000-8000-00000000000a');
insert into private.user_plans (user_id, plan, ends_at) values
  ('00000000-0000-4000-8000-00000000000c', 'pro', null),
  ('00000000-0000-4000-8000-00000000000d', 'special', now() + interval '1 day'),
  ('00000000-0000-4000-8000-00000000000e', 'special', now() - interval '1 second');

-- Signs in as the user whose id ends in [who], or as anon for null.
create function pg_temp.sign_in(who text) returns void language plpgsql as $$
begin
  if who is null then
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  else
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims',
      format('{"sub":"00000000-0000-4000-8000-00000000000%s","role":"authenticated"}', who), true);
  end if;
end;
$$;
grant execute on function pg_temp.sign_in(text) to public;

-- Every admin plan function, called with arguments that change nothing.
create function pg_temp.calls() returns setof text language sql as $$
  values
    ($q$select * from public.admin_plans()$q$),
    ($q$select public.admin_set_plan('none', 'anthropic/claude-haiku-5.5', 30)$q$),
    ($q$select * from public.admin_user_plan('00000000-0000-4000-8000-00000000000b')$q$),
    ($q$select public.admin_grant_plan('00000000-0000-4000-8000-00000000ffff', 'pro')$q$),
    ($q$select public.admin_revoke_plan('00000000-0000-4000-8000-00000000000b')$q$)
$$;
grant execute on function pg_temp.calls() to public;

-- The calls [who] is refused with insufficient_privilege, or the error of one that failed otherwise.
create function pg_temp.refused_as(who text) returns setof text language plpgsql as $$
declare
  call text;
begin
  for call in select * from pg_temp.calls() loop
    -- A refusal rolls the block back, the sign-in with it.
    begin
      perform pg_temp.sign_in(who);
      execute call;
      perform set_config('role', 'none', true);
    exception
      when insufficient_privilege then
        return next call;
      when others then
        return next 'failed: ' || call || ': ' || sqlerrm;
    end;
  end loop;
end;
$$;

-- What extract-cards gets for one photo of the user whose id ends in [who].
create function pg_temp.start(who text) returns table (plan text, model text, daily_limit integer, allowed boolean)
language plpgsql as $$
begin
  perform set_config('role', 'service_role', true);
  return query select b.plan, b.model, b.daily_limit, b.allowed
    from public.begin_extraction(('00000000-0000-4000-8000-00000000000' || who)::uuid) as b;
  perform set_config('role', 'none', true);
end;
$$;

-- The seed and the role.

select results_eq(
  $$select id, model, daily_limit from private.plans order by id$$,
  $$values ('free', 'anthropic/claude-haiku-5.5', 30), ('pro', 'anthropic/claude-haiku-5.5', 30),
           ('special', 'anthropic/claude-haiku-5.5', 30)$$,
  'the migration seeds the three plans on the model and the limit production runs now');

select results_eq(
  $$select count(*) from pg_temp.refused_as('b') as r (call) where call not like 'failed: %'$$,
  $$values (5::bigint)$$,
  'a signed-in user who is not an admin is refused by every admin plan function');
reset role;
select results_eq(
  $$select count(*) from pg_temp.refused_as(null) as r (call) where call not like 'failed: %'$$,
  $$values (5::bigint)$$,
  'anon is refused by every admin plan function');
reset role;
select is_empty($$select * from pg_temp.refused_as('a')$$,
  'control: an admin is refused by none, and none fails');
reset role;

select pg_temp.sign_in('b');
select throws_ok($$select * from public.begin_extraction('00000000-0000-4000-8000-00000000000b')$$,
  '42501', null, 'a signed-in user cannot start an extraction itself');
select throws_ok($$select * from private.plans$$, '42501', null, 'nor read the plans');
select throws_ok($$select * from private.user_plans$$, '42501', null, 'nor read the grants');
select throws_ok($$insert into private.user_plans (user_id, plan) values ('00000000-0000-4000-8000-00000000000b', 'pro')$$,
  '42501', null, 'nor grant itself a plan');
reset role;

-- Resolution and the count by the plan's limit.

update private.plans set model = 'vendor/free-model', daily_limit = 2 where id = 'free';
update private.plans set model = 'vendor/pro-model', daily_limit = 3 where id = 'pro';
update private.plans set model = 'vendor/special-model', daily_limit = 1 where id = 'special';

select results_eq($$select plan, model, daily_limit, allowed from pg_temp.start('b')$$,
  $$values ('free', 'vendor/free-model', 2, true)$$, 'a user without a grant is on Free');
reset role;
select results_eq($$select plan, model, allowed from pg_temp.start('c')$$,
  $$values ('pro', 'vendor/pro-model', true)$$, 'a Pro user is served by Pro''s model');
reset role;
select results_eq($$select plan, model, allowed from pg_temp.start('d')$$,
  $$values ('special', 'vendor/special-model', true)$$, 'a Special user before its end is on Special');
reset role;
select results_eq($$select plan, model, daily_limit from pg_temp.start('e')$$,
  $$values ('free', 'vendor/free-model', 2)$$, 'a Special user past its end is on Free');
reset role;

select results_eq($$select allowed from pg_temp.start('b')$$, $$values (true)$$, 'Free''s second photo is allowed');
reset role;
select results_eq($$select allowed from pg_temp.start('b')$$, $$values (false)$$,
  'Free''s third photo is over its limit of 2');
reset role;
select results_eq($$select allowed from pg_temp.start('c')$$, $$values (true)$$,
  'control: Pro''s second photo is allowed under its limit of 3');
reset role;
select results_eq($$select allowed from pg_temp.start('d')$$, $$values (false)$$,
  'Special''s second photo is over its limit of 1');
reset role;
select results_eq(
  $$select user_id, count(*) from public.extraction_usage group by user_id order by user_id$$,
  $$values ('00000000-0000-4000-8000-00000000000b'::uuid, 2::bigint), ('00000000-0000-4000-8000-00000000000c'::uuid, 2::bigint),
           ('00000000-0000-4000-8000-00000000000d'::uuid, 1::bigint), ('00000000-0000-4000-8000-00000000000e'::uuid, 1::bigint)$$,
  'only allowed photos are recorded');

delete from private.plans where id = 'free';
select is_empty($$select * from pg_temp.start('b')$$,
  'without Free''s settings, a Free user gets no plan, which the function answers as not configured');
reset role;

-- Admin writes.

select pg_temp.sign_in('a');
select results_eq($$select id, daily_limit from public.admin_plans()$$,
  $$values ('pro', 3), ('special', 1)$$, 'the plans, in plan order');
select is(public.admin_set_plan('pro', 'openai/gpt-6-luna', 10), true, 'set Pro''s model and limit');
select is(public.admin_set_plan('pro', 'openai/gpt-6-luna', 10), false, 'setting the same again changes nothing');
select throws_ok($$select public.admin_set_plan('pro', 'not a model', 10)$$, '23514', null,
  'a model id of another form cannot be saved');
select throws_ok($$select public.admin_set_plan('pro', 'openai/gpt-6-luna', 1001)$$, '23514', null,
  'nor a limit over 1000');

select is(public.admin_grant_plan('00000000-0000-4000-8000-00000000000b', 'special', now() + interval '7 days'), 'granted',
  'grant Special with an end');
select results_eq(
  $$select plan, daily_limit, granted_plan, ends_at > now(), granted_by_email from public.admin_user_plan('00000000-0000-4000-8000-00000000000b')$$,
  $$values ('special', 1, 'special', true, 'admin@example.com')$$,
  'the user is on Special, with its limit and the grant behind it');
select is(public.admin_grant_plan('00000000-0000-4000-8000-00000000000b', 'pro'), 'granted', 'replace it with Pro');
select results_eq($$select plan, ends_at from public.admin_user_plan('00000000-0000-4000-8000-00000000000b')$$,
  $$values ('pro', null::timestamptz)$$, 'one grant per user, the latest');
select results_eq(
  $$select public.admin_grant_plan('00000000-0000-4000-8000-00000000000b', 'pro', now() + interval '1 day'),
           public.admin_grant_plan('00000000-0000-4000-8000-00000000000b', 'special', now() - interval '1 day'),
           public.admin_grant_plan('00000000-0000-4000-8000-00000000000b', 'free'),
           public.admin_grant_plan('00000000-0000-4000-8000-00000000ffff', 'pro')$$,
  $$values ('bad_plan', 'bad_plan', 'bad_plan', 'no_user')$$,
  'Pro with an end, Special ending in the past, Free and an unknown user are refused');
select results_eq($$select plan, granted_plan from public.admin_user_plan('00000000-0000-4000-8000-00000000000e')$$,
  $$values (null::text, 'special')$$,
  'an ended Special shows its grant beside no plan when Free''s settings are missing');
select is(public.admin_revoke_plan('00000000-0000-4000-8000-00000000000b'), true, 'revoke the plan');
select is(public.admin_revoke_plan('00000000-0000-4000-8000-00000000000b'), false, 'revoking again changes nothing');
reset role;
select results_eq(
  $$select action, target_kind, target_id, detail - 'ends_at' from private.admin_audit order by id$$,
  $$values
    ('set_plan', 'plan', 'pro', '{"model": "openai/gpt-6-luna", "daily_limit": 10, "model_before": "vendor/pro-model", "daily_limit_before": 3}'::jsonb),
    ('grant_plan', 'user', '00000000-0000-4000-8000-00000000000b', '{"email": "user@example.com", "plan": "special"}'::jsonb),
    ('grant_plan', 'user', '00000000-0000-4000-8000-00000000000b', '{"email": "user@example.com", "plan": "pro"}'::jsonb),
    ('revoke_plan', 'user', '00000000-0000-4000-8000-00000000000b', '{"email": "user@example.com", "plan": "pro"}'::jsonb)$$,
  'each change is recorded once, and the refusals and no-ops not at all');

-- Account deletion.

update private.user_plans set granted_by = '00000000-0000-4000-8000-00000000000a' where user_id = '00000000-0000-4000-8000-00000000000c';
delete from auth.users where id in ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000d');
select results_eq(
  $$select user_id, granted_by from private.user_plans order by user_id$$,
  $$values ('00000000-0000-4000-8000-00000000000c'::uuid, null::uuid), ('00000000-0000-4000-8000-00000000000e'::uuid, null::uuid)$$,
  'a deleted user''s grant goes with it, and a deleted admin''s grants stay with no granter');
select results_eq($$select updated_by from private.plans where id = 'pro'$$, $$values (null::uuid)$$,
  'and the plan it set stays, with no editor');

select * from finish();
rollback;
