-- The horizon and the watermark: sync_horizon returns the stored horizon, 0 until a purge stores
-- one, and the revision sequence's last value read under the caller's revision lock.
begin;
select plan(11);

-- Whether this transaction holds the advisory lock the revision trigger takes for the user.
create function pg_temp.holds_revision_lock(user_id uuid) returns boolean language sql as $$
  select exists (
    select from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and granted
      and classid::bigint = (hashtextextended(user_id::text, 0) >> 32) & 4294967295
      and objid::bigint = hashtextextended(user_id::text, 0) & 4294967295
      and objsubid = 1
  )
$$;

-- sync_horizon as [who], signed in.
create function pg_temp.horizon_of(who uuid) returns table (horizon bigint, watermark bigint)
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', who, 'role', 'authenticated')::text, true);
  set local role authenticated;
  return query select * from public.sync_horizon();
  reset role;
end;
$$;

-- Written in replica mode, which fires no trigger, so no lock is taken before the call under test.
set local session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'caller@example.com'),
  ('00000000-0000-4000-8000-0000000000b1', 'other@example.com');
reset session_replication_role;

select is(
  (select count(*) from pg_locks where locktype = 'advisory' and pid = pg_backend_pid()),
  0::bigint,
  'the setup took no advisory lock');

-- The caller writes a deck, which draws a revision and takes the caller's lock, so the lock check
-- below is made for the other user.
insert into public.decks (id, user_id, name, created_at, updated_at)
  values ('d0000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1',
    'D', now(), now());

select is(
  (select horizon from pg_temp.horizon_of('00000000-0000-4000-8000-0000000000a1')),
  0::bigint,
  'the horizon is 0 while no purge has stored one');
select is(
  (select watermark from pg_temp.horizon_of('00000000-0000-4000-8000-0000000000a1')),
  (select last_value from private.revision),
  'the watermark is the revision sequence''s last value');
select cmp_ok(
  (select watermark from pg_temp.horizon_of('00000000-0000-4000-8000-0000000000a1')),
  '>=',
  (select revision from public.decks where id = 'd0000000-0000-4000-8000-0000000000a1'),
  'the caller''s latest row is at or below the watermark');

select is(
  (select count(*) from pg_temp.horizon_of('00000000-0000-4000-8000-0000000000a1')),
  1::bigint,
  'one row is returned');

-- The lock check runs for the other user, whose lock no write above took.
select ok(not pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000b1'),
  'control: the other user''s revision lock is not held before its call');
select pg_temp.horizon_of('00000000-0000-4000-8000-0000000000b1');
select ok(pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000b1'),
  'the call takes the caller''s revision lock, the key the revision trigger takes');

-- A write after the call draws a revision above the watermark it returned.
create temp table seen as
  select watermark from pg_temp.horizon_of('00000000-0000-4000-8000-0000000000a1');
insert into public.decks (id, user_id, name, created_at, updated_at)
  values ('d0000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a1',
    'E', now(), now());
select cmp_ok(
  (select revision from public.decks where id = 'd0000000-0000-4000-8000-0000000000a2'),
  '>',
  (select watermark from seen),
  'a row written after the call is above the watermark it returned');

-- A purge stores the mark it purged below; the call then returns it.
update private.sync_horizon set revision = 42;
select is(
  (select horizon from pg_temp.horizon_of('00000000-0000-4000-8000-0000000000a1')),
  42::bigint,
  'a stored horizon is returned');

select function_privs_are('public', 'sync_horizon', array[]::text[],
  'anon', array[]::text[], 'anon may not call it');
select results_eq(
  $$select prosecdef, provolatile = 'v', proconfig = array['search_path=""'],
      has_function_privilege('authenticated', oid, 'EXECUTE')
    from pg_proc where oid = 'public.sync_horizon()'::regprocedure$$,
  $$values (true, true, true, true)$$,
  'it runs as its owner, is volatile, sets an empty search_path, and authenticated may call it');

select * from finish();
rollback;
