-- extraction_usage: users read only their own rows, and only service_role records one, through
-- consume_extraction, which lets at most the daily limit through per user and UTC day.
begin;
select plan(18);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
-- One row each today, and one for A just before today began, which the limit does not count.
insert into public.extraction_usage (user_id, created_at) values
  ('00000000-0000-4000-8000-00000000000a', now()),
  ('00000000-0000-4000-8000-00000000000b', now()),
  ('00000000-0000-4000-8000-00000000000a', date_trunc('day', now(), 'UTC') - interval '1 second');

select results_eq(
  'select count(*) from public.extraction_usage',
  array[3::bigint],
  'the fixture holds three rows');

-- The privileges alone refuse every write, whatever the policies would allow.
select results_eq(
  $$select privilege from unnest(array['select', 'insert', 'update', 'delete']) as privilege
    where has_table_privilege('authenticated', 'public.extraction_usage', privilege)
    union all
    select 'service_role ' || privilege from unnest(array['insert', 'update', 'delete']) as privilege
    where has_table_privilege('service_role', 'public.extraction_usage', privilege)$$,
  array['select'],
  'authenticated may only select, and service_role may write only through consume_extraction');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

select results_eq(
  'select count(*) from public.extraction_usage where user_id = ''00000000-0000-4000-8000-00000000000a''',
  array[2::bigint],
  'A reads its own rows');
select results_eq(
  'select count(*) from public.extraction_usage where user_id = ''00000000-0000-4000-8000-00000000000b''',
  array[0::bigint],
  'A reads none of B''s rows');
select throws_ok(
  $$insert into public.extraction_usage (user_id) values ('00000000-0000-4000-8000-00000000000a')$$,
  '42501', null, 'A cannot insert a row, even its own');
select throws_ok('update public.extraction_usage set created_at = now()', '42501', null,
  'A cannot update its rows');
select throws_ok('delete from public.extraction_usage', '42501', null, 'A cannot delete its rows');
select throws_ok(
  $$select public.consume_extraction('00000000-0000-4000-8000-00000000000a', 30)$$,
  '42501', null, 'A cannot call consume_extraction');

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select throws_ok('select * from public.extraction_usage', '42501', null, 'anon cannot select');
select throws_ok(
  $$select public.consume_extraction('00000000-0000-4000-8000-00000000000a', 30)$$,
  '42501', null, 'anon cannot call consume_extraction');

reset role;
set local role service_role;
set local request.jwt.claims to '{"role":"service_role"}';

select throws_ok(
  $$insert into public.extraction_usage (user_id) values ('00000000-0000-4000-8000-00000000000a')$$,
  '42501', null, 'service_role cannot insert a row except through consume_extraction');

-- A has one row today, so 29 more are let through and the 30th call after them is refused.
select results_eq(
  $$select bool_and(public.consume_extraction('00000000-0000-4000-8000-00000000000a', 30))
    from generate_series(1, 29)$$,
  array[true],
  'consume_extraction lets A through until A has 30 rows today');
select is(
  public.consume_extraction('00000000-0000-4000-8000-00000000000a', 30), false,
  'consume_extraction refuses A''s 31st extraction today');
select results_eq(
  $$select count(*) from public.extraction_usage
    where user_id = '00000000-0000-4000-8000-00000000000a'
      and created_at >= date_trunc('day', now(), 'UTC')$$,
  array[30::bigint],
  'the refused call recorded no row');
select is(
  public.consume_extraction('00000000-0000-4000-8000-00000000000b', 30), true,
  'B is let through while A is refused');
select is(
  public.consume_extraction('00000000-0000-4000-8000-00000000000a', 31), true,
  'the limit is the one passed in: A is let through under a limit of 31');

reset role;
select ok(
  exists (
    select from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and granted
      and classid::bigint = (hashtextextended('00000000-0000-4000-8000-00000000000a', 1) >> 32) & 4294967295
      and objid::bigint = hashtextextended('00000000-0000-4000-8000-00000000000a', 1) & 4294967295
  ),
  'consume_extraction holds A''s usage lock until commit');
select ok(
  not exists (
    select from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and granted
      and classid::bigint = (hashtextextended('00000000-0000-4000-8000-00000000000a', 0) >> 32) & 4294967295
      and objid::bigint = hashtextextended('00000000-0000-4000-8000-00000000000a', 0) & 4294967295
  ),
  'consume_extraction does not take A''s revision lock');

select * from finish();
rollback;
