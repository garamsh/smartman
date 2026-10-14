-- Each write takes its user's advisory lock until commit, so one user's revisions follow commit order.
begin;
select plan(9);

-- Whether this transaction holds the advisory lock keyed by the user's id.
create function pg_temp.holds_revision_lock(user_id uuid) returns boolean language sql as $$
  select exists (
    select from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and granted
      and classid::bigint = (hashtextextended(user_id::text, 0) >> 32) & 4294967295
      and objid::bigint = hashtextextended(user_id::text, 0) & 4294967295
      and objsubid = 1
  )
$$;

-- One user per table, each owning a deck and a card. Written in replica mode, which fires no
-- trigger, so no lock is taken before the writes under test.
set local session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000d1', 'decks@example.com'),
  ('00000000-0000-4000-8000-0000000000c1', 'cards@example.com'),
  ('00000000-0000-4000-8000-0000000000e1', 'reviews@example.com'),
  ('00000000-0000-4000-8000-0000000000f1', 'states@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at, revision)
  select 'deck-' || u, u::uuid, 'D', now(), now(), 0
  from unnest(array['00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000c1',
    '00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1']) as u;
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at, revision)
  select 'card-' || user_id, user_id, id, '[]', '[]', 'k', 'manual', now(), now(), 0 from public.decks;
reset session_replication_role;

select is(
  (select count(*) from pg_locks where locktype = 'advisory' and pid = pg_backend_pid()),
  0::bigint,
  'the setup took no advisory lock');

insert into public.decks (id, user_id, name, created_at, updated_at)
  values ('deck-new', '00000000-0000-4000-8000-0000000000d1', 'N', now(), now());
select ok(pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000d1'),
  'inserting a deck takes its user''s lock');
select ok(not pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000c1'),
  'another user''s lock is not taken by that insert');

insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at)
  values ('card-new', '00000000-0000-4000-8000-0000000000c1',
    'deck-00000000-0000-4000-8000-0000000000c1', '[]', '[]', 'n', 'manual', now(), now());
select ok(pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000c1'),
  'inserting a card takes its user''s lock');
select ok(not pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000e1'),
  'another user''s lock is not taken by that insert');

insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at)
  values ('review-new', '00000000-0000-4000-8000-0000000000e1',
    'card-00000000-0000-4000-8000-0000000000e1', 'good', now(), 0, now());
select ok(pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000e1'),
  'inserting a review takes its user''s lock');
select ok(not pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000f1'),
  'another user''s lock is not taken by that insert');

insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due, updated_at)
  values ('00000000-0000-4000-8000-0000000000f1',
    'card-00000000-0000-4000-8000-0000000000f1', 1, 5, now(), now(), now());
select ok(pg_temp.holds_revision_lock('00000000-0000-4000-8000-0000000000f1'),
  'inserting a card state takes its user''s lock');

select is(
  (select count(*) from pg_locks where locktype = 'advisory' and pid = pg_backend_pid()),
  4::bigint,
  'four users'' writes hold four distinct locks');

select * from finish();
rollback;
