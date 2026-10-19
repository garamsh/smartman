-- The admin area's functions (ADR 0070): each refuses a signed-in user who is not an admin and
-- anon, with an admin as control, and each does what it says, recording every write.
begin;
select plan(58);

-- The log starts empty here: a migration may record a change of its own, as
-- 20261019230002_activate_prompt_v9.sql records prompt v9's activation.
delete from private.admin_audit;

-- A is an admin, B a signed-in user who is not, C owns the decks, D and E report.
insert into auth.users (id, email, created_at) values
  ('00000000-0000-4000-8000-00000000000a', 'admin@example.com', now() - interval '40 days'),
  ('00000000-0000-4000-8000-00000000000b', 'user@example.com', now() - interval '20 days'),
  ('00000000-0000-4000-8000-00000000000c', 'owner@example.com', now() - interval '3 days'),
  ('00000000-0000-4000-8000-00000000000d', 'd@example.com', now() - interval '40 days'),
  ('00000000-0000-4000-8000-00000000000e', 'e@example.com', now() - interval '40 days');
insert into private.admins (user_id) values ('00000000-0000-4000-8000-00000000000a');
insert into public.profiles (user_id, display_name) values ('00000000-0000-4000-8000-00000000000c', 'Owner');
insert into public.decks
  (id, user_id, name, visibility, published_at, created_at, updated_at) values
  ('d0000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-00000000000c', 'French', 'public', now() - interval '2 days', now(), now() - interval '1 hour'),
  ('d0000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-00000000000c', 'Spanish', 'public', now() - interval '1 day', now(), now()),
  ('d0000000-0000-4000-8000-0000000000c3', '00000000-0000-4000-8000-00000000000c', 'Diary', 'private', null, now(), now());
insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at, deleted_at) values
  ('c0000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-00000000000c', 'd0000000-0000-4000-8000-0000000000c1',
    '[{"type":"text","payload":{"text":"chat"}}]', '[{"type":"text","payload":{"text":"고양이"}}]', 'chat', 'manual', now() - interval '2 hours', now(), null),
  ('c0000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-00000000000c', 'd0000000-0000-4000-8000-0000000000c1',
    '[{"type":"text","payload":{"text":"chien"}}]', '[{"type":"text","payload":{"text":"개"}}]', 'chien', 'manual', now() - interval '1 hour', now(), null),
  ('c0000000-0000-4000-8000-0000000000c3', '00000000-0000-4000-8000-00000000000c', 'd0000000-0000-4000-8000-0000000000c1',
    '[]', '[]', 'gone', 'manual', now(), now(), now()),
  ('c0000000-0000-4000-8000-0000000000c4', '00000000-0000-4000-8000-00000000000c', 'd0000000-0000-4000-8000-0000000000c3',
    '[{"type":"text","payload":{"text":"secret"}}]', '[]', 'secret', 'manual', now(), now(), null);
insert into public.deck_reports (deck_id, reporter_id, reason, created_at) values
  ('d0000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-00000000000d', 'spam', now() - interval '2 hours'),
  ('d0000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-00000000000e', 'copyright', now() - interval '1 hour');
insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at) values
  ('e0000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-0000000000c1', 'good', now() - interval '1 hour', 1000, now()),
  ('e0000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-0000000000c2', 'good', now() - interval '3 days', 1000, now());
insert into public.extraction_usage (user_id, created_at) values
  ('00000000-0000-4000-8000-00000000000c', now()),
  ('00000000-0000-4000-8000-00000000000c', now()),
  ('00000000-0000-4000-8000-00000000000b', date_trunc('day', now(), 'UTC') - interval '1 day');

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

-- Every admin function, called with harmless arguments.
create function pg_temp.calls() returns setof text language sql as $$
  values
    ($q$select * from public.admin_overview(now(), now())$q$),
    ($q$select * from public.admin_extractions_by_day()$q$),
    ($q$select * from public.admin_reported_decks()$q$),
    ($q$select * from public.admin_public_decks()$q$),
    ($q$select * from public.admin_deck('d0000000-0000-4000-8000-0000000000c2')$q$),
    ($q$select * from public.admin_deck_cards('d0000000-0000-4000-8000-0000000000c2')$q$),
    ($q$select * from public.admin_find_users('example')$q$),
    ($q$select * from public.admin_user('00000000-0000-4000-8000-00000000000c')$q$),
    ($q$select * from public.admin_admins()$q$),
    ($q$select * from public.admin_audit_log()$q$),
    ($q$select public.admin_set_deck_hidden('d0000000-0000-4000-8000-00000000ffff', true)$q$),
    ($q$select public.admin_unpublish_deck('d0000000-0000-4000-8000-00000000ffff')$q$),
    ($q$select public.admin_dismiss_reports('d0000000-0000-4000-8000-00000000ffff')$q$),
    ($q$select public.admin_grant_admin('nobody@example.com')$q$),
    ($q$select public.admin_revoke_admin('00000000-0000-4000-8000-00000000ffff')$q$)
$$;
grant execute on function pg_temp.calls() to public;

-- Runs each call as [who] and returns those it refused with insufficient_privilege, or the error
-- of one that failed otherwise.
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

-- Whether this transaction holds the advisory lock revokes take.
create function pg_temp.holds_admins_lock() returns boolean language sql as $$
  select exists (
    select from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and granted
      and classid::bigint = (hashtextextended('private.admins', 3) >> 32) & 4294967295
      and objid::bigint = hashtextextended('private.admins', 3) & 4294967295
      and objsubid = 1
  )
$$;
grant execute on function pg_temp.holds_admins_lock() to public;

-- The role.

select results_eq(
  $$select count(*) from pg_temp.refused_as('b') as r (call) where call not like 'failed: %'$$,
  $$values (15::bigint)$$,
  'a signed-in user who is not an admin is refused by every admin function');
reset role;
select results_eq(
  $$select count(*) from pg_temp.refused_as(null) as r (call) where call not like 'failed: %'$$,
  $$values (15::bigint)$$,
  'anon is refused by every admin function');
reset role;
select is((select pg_temp.holds_admins_lock()), false,
  'control: no admin call has taken the admins lock yet');
select is_empty(
  $$select * from pg_temp.refused_as('a')$$,
  'control: an admin is refused by none, and none fails');
reset role;
select is((select pg_temp.holds_admins_lock()), true,
  'an admin''s revoke takes the admins lock, held to commit, so concurrent revokes run one after another');

select pg_temp.sign_in('b');
select is((select public.is_admin()), false, 'is_admin is false for a user without the role');
select throws_ok($$select * from private.admins$$, '42501', null,
  'a signed-in user cannot read the admins table');
select throws_ok($$select * from private.admin_audit$$, '42501', null,
  'a signed-in user cannot read the audit log''s table');
select throws_ok($$insert into private.admins (user_id) values ('00000000-0000-4000-8000-00000000000b')$$,
  '42501', null, 'a signed-in user cannot make itself an admin');
reset role;
select pg_temp.sign_in('a');
select is((select public.is_admin()), true, 'control: is_admin is true for an admin');
select throws_ok($$select * from private.admins$$, '42501', null,
  'even an admin reads the role only through the functions');
reset role;
select pg_temp.sign_in(null);
select throws_ok($$select public.is_admin()$$, '42501', null, 'anon cannot ask');
reset role;

select ok(
  (select prosecdef and proconfig = array['search_path=""']
    from pg_proc where oid = 'public.admin_set_deck_hidden(uuid, boolean)'::regprocedure),
  'the functions run as their owner with an empty search_path');

-- The overview and extractions.

select pg_temp.sign_in('a');
select results_eq(
  $$select users, new_users_7d, new_users_30d, studied_today, studied_7d, extractions_today
    from public.admin_overview(now() - interval '2 hours', now() - interval '7 days')$$,
  $$values (5::bigint, 1::bigint, 2::bigint, 1::bigint, 1::bigint, 2::bigint)$$,
  'the overview counts users, new users, users who studied and today''s extractions');
select results_eq(
  $$select count(*), sum(extractions), max(day) from public.admin_extractions_by_day()$$,
  $$values (30::bigint, 3::numeric, (date_trunc('day', now(), 'UTC'))::date)$$,
  'extractions per UTC day: 30 days, today last, every extraction counted');
select results_eq(
  $$select extractions from public.admin_extractions_by_day() order by day desc limit 2$$,
  $$values (2::bigint), (1::bigint)$$,
  'today''s two and yesterday''s one');

-- Reports and decks.

select results_eq(
  $$select deck_id, name, owner_email, owner_name, hidden, reports, reasons from public.admin_reported_decks()$$,
  $$values ('d0000000-0000-4000-8000-0000000000c1'::uuid, 'French', 'owner@example.com', 'Owner', false, 2::bigint, array['copyright', 'spam'])$$,
  'a reported deck with its owner, report count and reasons, and no unreported deck');
select results_eq(
  $$select deck_id, cards, reports from public.admin_public_decks()$$,
  $$values ('d0000000-0000-4000-8000-0000000000c2'::uuid, 0::bigint, 0::bigint),
           ('d0000000-0000-4000-8000-0000000000c1'::uuid, 2::bigint, 2::bigint)$$,
  'every public deck, newest published first, with its live cards and reports, and no private one');
select results_eq(
  $$select deck_id from public.admin_public_decks('fre')$$,
  $$values ('d0000000-0000-4000-8000-0000000000c1'::uuid)$$,
  'public decks whose name holds the search, ignoring case');
select is_empty(
  $$select * from public.admin_public_decks('', '00000000-0000-4000-8000-00000000000b')$$,
  'public decks of another owner: none');
select results_eq(
  $$select front->0->'payload'->>'text' from public.admin_deck_cards('d0000000-0000-4000-8000-0000000000c1')$$,
  $$values ('chat'), ('chien')$$,
  'a reported deck''s live cards, oldest first, without its deleted card');
select results_eq(
  $$select name, visibility, reports, reasons from public.admin_deck('d0000000-0000-4000-8000-0000000000c1')$$,
  $$values ('French', 'public', 2::bigint, array['copyright', 'spam'])$$,
  'a reported deck, with its reports');
select is_empty(
  $$select * from public.admin_deck('d0000000-0000-4000-8000-0000000000c3')$$,
  'a private deck no one reported is not readable in the admin area');
select is_empty(
  $$select * from public.admin_deck_cards('d0000000-0000-4000-8000-0000000000c3')$$,
  'nor its cards');

-- Actions on decks, each recorded.

select is(public.admin_set_deck_hidden('d0000000-0000-4000-8000-0000000000c1', true), true, 'hide a deck');
select is(public.admin_set_deck_hidden('d0000000-0000-4000-8000-0000000000c1', true), false,
  'hiding a hidden deck changes nothing');
reset role;
select results_eq(
  $$select hidden from public.decks where id = 'd0000000-0000-4000-8000-0000000000c1'$$,
  $$values (true)$$, 'the deck is hidden');
select results_eq(
  $$select admin_email, action, target_kind, target_id, detail from private.admin_audit order by id$$,
  $$values ('admin@example.com', 'hide_deck', 'deck', 'd0000000-0000-4000-8000-0000000000c1', '{"name": "French"}'::jsonb)$$,
  'the hide is recorded once, and the no-op not at all');

select pg_temp.sign_in('a');
select is(public.admin_set_deck_hidden('d0000000-0000-4000-8000-0000000000c1', false), true, 'unhide it');
reset role;
select results_eq(
  $$select (select hidden from public.decks where id = 'd0000000-0000-4000-8000-0000000000c1'),
    (select action from private.admin_audit order by id desc limit 1)$$,
  $$values (false, 'unhide_deck')$$, 'the deck is visible again, and the unhide recorded');

create temp table before_unpublish as
  select revision, updated_at from public.decks where id = 'd0000000-0000-4000-8000-0000000000c1';
grant select on before_unpublish to public;
select pg_temp.sign_in('a');
select is(public.admin_unpublish_deck('d0000000-0000-4000-8000-0000000000c1'), true, 'unpublish a deck');
select is(public.admin_unpublish_deck('d0000000-0000-4000-8000-0000000000c1'), false,
  'unpublishing a private deck changes nothing');
reset role;
select results_eq(
  $$select d.visibility, d.revision > b.revision, d.updated_at > b.updated_at
    from public.decks as d, before_unpublish as b where d.id = 'd0000000-0000-4000-8000-0000000000c1'$$,
  $$values ('private', true, true)$$,
  'the deck is private, with a new revision and edit time, so the owner''s devices pull it');
select results_eq(
  $$select count(*) from private.admin_audit where action = 'unpublish_deck'$$,
  $$values (1::bigint)$$, 'the unpublish is recorded once');

select pg_temp.sign_in('a');
select results_eq(
  $$select name from public.admin_deck('d0000000-0000-4000-8000-0000000000c1')$$,
  $$values ('French')$$,
  'an unpublished deck stays readable while it has reports');
select is(public.admin_dismiss_reports('d0000000-0000-4000-8000-0000000000c1'), 2, 'dismiss its two reports');
select is(public.admin_dismiss_reports('d0000000-0000-4000-8000-0000000000c1'), 0, 'nothing left to dismiss');
select is_empty($$select * from public.admin_reported_decks()$$, 'no reported deck remains');
select is_empty($$select * from public.admin_deck('d0000000-0000-4000-8000-0000000000c1')$$,
  'a private deck without reports leaves the admin area');
reset role;
select results_eq(
  $$select detail from private.admin_audit where action = 'dismiss_reports'$$,
  $$values ('{"reports": 2}'::jsonb)$$, 'the dismissal is recorded once, with its count');

-- Users.

select pg_temp.sign_in('a');
select results_eq(
  $$select email from public.admin_find_users('EXAMPLE.com') order by email limit 2$$,
  $$values ('admin@example.com'), ('d@example.com')$$,
  'find users by part of their email, ignoring case');
select is_empty($$select * from public.admin_find_users('')$$, 'an empty search finds no one');
select results_eq(
  $$select email, last_answer_at is not null, decks, cards, extractions_today, admin
    from public.admin_user('00000000-0000-4000-8000-00000000000c')$$,
  $$values ('owner@example.com', true, 3::bigint, 3::bigint, 2::bigint, false)$$,
  'a user''s email, latest answer, live decks and cards, today''s extractions and role');
select results_eq(
  $$select extractions_today, admin from public.admin_user('00000000-0000-4000-8000-00000000000b')$$,
  $$values (0::bigint, false)$$,
  'yesterday''s extraction is not today''s');

-- Admins.

select is(public.admin_grant_admin(' User@Example.com '), 'granted', 'grant the role by email');
select is(public.admin_grant_admin('user@example.com'), 'already', 'granting it again changes nothing');
select is(public.admin_grant_admin('nobody@example.com'), 'no_user', 'an email no user has grants nothing');
select results_eq(
  $$select email, granted_by_email from public.admin_admins()$$,
  $$values ('admin@example.com', null::text), ('user@example.com', 'admin@example.com')$$,
  'the admins, the first granted in the database and the second by A');
select is(public.admin_revoke_admin('00000000-0000-4000-8000-00000000000a'), 'self',
  'an admin cannot revoke its own role');
reset role;
select pg_temp.sign_in('b');
select is((select public.is_admin()), true, 'the grantee is an admin now');
select is(public.admin_revoke_admin('00000000-0000-4000-8000-00000000000a'), 'revoked', 'and revokes A');
select is(public.admin_revoke_admin('00000000-0000-4000-8000-00000000000a'), 'not_admin',
  'revoking a user without the role changes nothing');
reset role;
select pg_temp.sign_in('a');
select throws_ok($$select * from public.admin_admins()$$, '42501', null,
  'a revoked admin is refused at once');
reset role;
select results_eq(
  $$select admin_email, action, target_id, detail from private.admin_audit
    where target_kind = 'user' order by id$$,
  $$values ('admin@example.com', 'grant_admin', '00000000-0000-4000-8000-00000000000b', '{"email": "user@example.com"}'::jsonb),
           ('user@example.com', 'revoke_admin', '00000000-0000-4000-8000-00000000000a', '{"email": "admin@example.com"}'::jsonb)$$,
  'the grant and the revoke are recorded, each by who acted');

-- The audit log, read through its function.

select pg_temp.sign_in('b');
select results_eq(
  $$select action from public.admin_audit_log()$$,
  $$values ('revoke_admin'), ('grant_admin'), ('dismiss_reports'), ('unpublish_deck'), ('unhide_deck'), ('hide_deck')$$,
  'the audit log, newest first');
select results_eq(
  $$select action from public.admin_audit_log(
    (select id from public.admin_audit_log() where action = 'unpublish_deck'), 2)$$,
  $$values ('unhide_deck'), ('hide_deck')$$,
  'a page of the log before a row');
reset role;

-- Deleting an admin's account keeps the rows it wrote.

delete from auth.users where id = '00000000-0000-4000-8000-00000000000a';
select results_eq(
  $$select count(*), count(admin_id) from private.admin_audit where admin_email = 'admin@example.com'$$,
  $$values (5::bigint, 0::bigint)$$,
  'a deleted admin''s five writes stay in the log, by email, with no admin id');
select results_eq(
  $$select granted_by from private.admins where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  $$values (null::uuid)$$,
  'and the role it granted stays, with no granter');

select * from finish();
rollback;
