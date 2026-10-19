-- extraction_allowance: the caller's own plan's daily limit and today's photos, which agree with
-- what begin_extraction resolves and counts, on each plan and a Special that has ended; anon is
-- refused.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000b', 'free@example.com'),
  ('00000000-0000-4000-8000-00000000000c', 'pro@example.com'),
  ('00000000-0000-4000-8000-00000000000d', 'special@example.com'),
  ('00000000-0000-4000-8000-00000000000e', 'ended@example.com');
insert into private.user_plans (user_id, plan, ends_at) values
  ('00000000-0000-4000-8000-00000000000c', 'pro', null),
  ('00000000-0000-4000-8000-00000000000d', 'special', now() + interval '1 day'),
  ('00000000-0000-4000-8000-00000000000e', 'special', now() - interval '1 second');
update private.plans set daily_limit = 2 where id = 'free';
update private.plans set daily_limit = 3 where id = 'pro';
update private.plans set daily_limit = 5 where id = 'special';
-- One photo yesterday for the Free user, which today does not count.
insert into public.extraction_usage (user_id, created_at) values
  ('00000000-0000-4000-8000-00000000000b', date_trunc('day', now(), 'UTC') - interval '1 second');

-- What [who] reads, signed in.
create function pg_temp.allowance(who text) returns table (daily_limit integer, used integer)
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-4000-8000-00000000000' || who, 'role', 'authenticated')::text,
    true);
  perform set_config('role', 'authenticated', true);
  return query select * from public.extraction_allowance();
  perform set_config('role', 'none', true);
end;
$$;

-- The daily limit begin_extraction resolves for [who], recording one photo when allowed.
create function pg_temp.begin(who text) returns table (daily_limit integer, allowed boolean)
language plpgsql as $$
begin
  perform set_config('role', 'service_role', true);
  return query select b.daily_limit, b.allowed
    from public.begin_extraction(('00000000-0000-4000-8000-00000000000' || who)::uuid) as b;
  perform set_config('role', 'none', true);
end;
$$;

select results_eq($$select * from pg_temp.allowance('b')$$, $$values (2, 0)$$,
  'a Free user reads Free''s limit and no photo today, yesterday''s left out');
reset role;
select results_eq($$select * from pg_temp.allowance('c')$$, $$values (3, 0)$$,
  'a Pro user reads Pro''s limit');
reset role;
select results_eq($$select * from pg_temp.allowance('d')$$, $$values (5, 0)$$,
  'a Special user before its end reads Special''s limit');
reset role;
select results_eq($$select * from pg_temp.allowance('e')$$, $$values (2, 0)$$,
  'a Special that has ended reads Free''s limit');
reset role;

-- The two agree: begin_extraction's limit for each user is the one the allowance read, and each
-- photo it lets through is one more used.
select results_eq(
  $$select daily_limit from pg_temp.begin('b') union all select daily_limit from pg_temp.begin('c')
    union all select daily_limit from pg_temp.begin('d') union all select daily_limit from pg_temp.begin('e')$$,
  $$values (2), (3), (5), (2)$$,
  'begin_extraction resolves the same limit for each');
reset role;
select results_eq($$select * from pg_temp.allowance('b')$$, $$values (2, 1)$$,
  'a photo begin_extraction let through is one more used');
reset role;
select results_eq($$select allowed from pg_temp.begin('b') union all select allowed from pg_temp.begin('b')$$,
  $$values (true), (false)$$, 'control: begin_extraction refuses once used reaches the limit');
reset role;

select function_privs_are('public', 'extraction_allowance', '{}', 'authenticated', '{EXECUTE}',
  'control: authenticated may call it');
set local role anon;
select throws_ok($$select * from public.extraction_allowance()$$, '42501', null,
  'anon is refused');
reset role;

select * from finish();
rollback;
