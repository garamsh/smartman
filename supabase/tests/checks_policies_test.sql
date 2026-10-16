-- Checks and policies: the five row checks refuse what they name and admit their controls, each is
-- validated, and decks, cards and profiles each have one select policy, the owner's condition first.
begin;
select plan(22);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'A', now(), now());
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at) values
  ('c0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a',
   'd0000000-0000-4000-8000-00000000000a', '[]', '[]', 'a', 'manual', now(), now());

-- Inserts a deck of user A with the name and tombstone given.
create function pg_temp.deck(id uuid, name text, deleted_at timestamptz) returns void
language sql as $$
  insert into public.decks (id, user_id, name, created_at, updated_at, deleted_at)
  values (id, '00000000-0000-4000-8000-00000000000a', name, now(), now(), deleted_at)
$$;

-- Inserts a card of user A in its deck with the card key, source, origin and tombstone given.
create function pg_temp.card(id uuid, card_key text, source text, origin uuid, deleted_at timestamptz)
returns void language sql as $$
  insert into public.cards
    (id, user_id, deck_id, front, back, card_key, source, origin_deck_id, created_at, updated_at, deleted_at)
  values (id, '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000a', '[]', '[]',
    card_key, source, origin, now(), now(), deleted_at)
$$;

-- Writes user A's card state with the stability and difficulty given.
create function pg_temp.card_state(stability double precision, difficulty double precision) returns void
language sql as $$
  insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due, updated_at)
  values ('00000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-00000000000a', stability,
    difficulty, now(), now(), now())
  on conflict (user_id, card_id)
    do update set stability = excluded.stability, difficulty = excluded.difficulty
$$;

select throws_ok($$select pg_temp.deck('d0000000-0000-4000-8000-000000000001', '', null)$$,
  '23514', null, 'a live deck with an empty name is refused');
select lives_ok($$select pg_temp.deck('d0000000-0000-4000-8000-000000000002', '', now())$$,
  'a deck tombstone with an empty name is kept');

select throws_ok($$select pg_temp.card('c0000000-0000-4000-8000-000000000001', '', 'manual', null, null)$$,
  '23514', null, 'a live card with an empty card key is refused');
select lives_ok($$select pg_temp.card('c0000000-0000-4000-8000-000000000002', '', 'manual', null, now())$$,
  'a card tombstone with an empty card key is kept');

select throws_ok($$select pg_temp.card_state(0.0009, 5)$$,
  '23514', null, 'a stability below 0.001 is refused');
select lives_ok($$select pg_temp.card_state(0.001, 5)$$, 'a stability of 0.001 is accepted');
select throws_ok($$select pg_temp.card_state(1, 0.99)$$,
  '23514', null, 'a difficulty below 1 is refused');
select throws_ok($$select pg_temp.card_state(1, 10.01)$$,
  '23514', null, 'a difficulty above 10 is refused');
select lives_ok($$select pg_temp.card_state(1, 1)$$, 'a difficulty of 1 is accepted');
select lives_ok($$select pg_temp.card_state(1, 10)$$, 'a difficulty of 10 is accepted');

select throws_ok(
  $$select pg_temp.card('c0000000-0000-4000-8000-000000000003', 'b', 'shared', null, null)$$,
  '23514', null, 'a shared card without an origin is refused');
select throws_ok(
  $$select pg_temp.card('c0000000-0000-4000-8000-000000000004', 'b', 'manual',
    'd0000000-0000-4000-8000-000000000012', null)$$,
  '23514', null, 'a manual card with an origin is refused');
select lives_ok(
  $$select pg_temp.card('c0000000-0000-4000-8000-000000000005', 'b', 'shared',
    'd0000000-0000-4000-8000-000000000012', null)$$,
  'a shared card with an origin is accepted');
select lives_ok($$select pg_temp.card('c0000000-0000-4000-8000-000000000006', 'b', 'import', null, null)$$,
  'an imported card without an origin is accepted');

select results_eq(
  $$select conname::text collate "default", convalidated from pg_constraint
    where conname in ('decks_name_check', 'cards_card_key_check', 'card_states_stability_check',
      'card_states_difficulty_check', 'cards_origin_deck_id_check')
    order by conname::text collate "C"$$,
  $$values ('card_states_difficulty_check', true), ('card_states_stability_check', true),
    ('cards_card_key_check', true), ('cards_origin_deck_id_check', true), ('decks_name_check', true)$$,
  'the five checks exist and are validated');

select policies_are('public', 'decks', array['decks_select', 'decks_insert', 'decks_update', 'decks_delete'],
  'decks has one policy per command');
select policies_are('public', 'cards', array['cards_select', 'cards_insert', 'cards_update', 'cards_delete'],
  'cards has one policy per command');
select policies_are('public', 'profiles', array['profiles_select', 'profiles_insert', 'profiles_update'],
  'profiles has one policy per command it allows');

-- The condition Postgres stores for a select policy.
create function pg_temp.select_rule(table_name name) returns text language sql stable as $$
  select qual from pg_policies
  where schemaname = 'public' and tablename = table_name and cmd = 'SELECT'
$$;

select ok(pg_temp.select_rule('decks') like '((( SELECT auth.uid() AS uid) = user_id) OR %',
  'the decks select policy tests the owner first');
select ok(pg_temp.select_rule('cards') like '((( SELECT auth.uid() AS uid) = user_id) OR %',
  'the cards select policy tests the owner first');
select ok(pg_temp.select_rule('profiles') like '((( SELECT auth.uid() AS uid) = user_id) OR %',
  'the profiles select policy tests the owner first');
-- Control: the pattern matches only where the owner leads; the insert policy has no public rule.
select ok(
  (select with_check from pg_policies where policyname = 'decks_insert')
    not like '((( SELECT auth.uid() AS uid) = user_id) OR %',
  'a policy with no public rule does not match the owner-first pattern');

select * from finish();
rollback;
