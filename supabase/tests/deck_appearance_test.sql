-- A deck's appearance (ADR 0103): two nullable keys, bounded in length and never checked against
-- a list, which the owner writes as it writes the deck's other columns, under the same row-level
-- security.
begin;
select plan(13);

select col_is_null('public', 'decks', 'icon', 'decks.icon is nullable');
select col_is_null('public', 'decks', 'color', 'decks.color is nullable');

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
-- B's deck, written as a client from before the migration writes one: without the two keys.
insert into public.decks (id, user_id, name, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'B', now(), now());
select results_eq(
  $$select icon, color from public.decks where id = 'd0000000-0000-4000-8000-00000000000b'$$,
  $$values (null::text, null::text)$$,
  'a deck written without the keys holds neither, so it draws the default tile');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$insert into public.decks (id, user_id, name, created_at, updated_at, icon, color)
    values ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'A', now(), now(), 'book', 'violet')$$,
  'the owner inserts a deck with its icon and colour');
select lives_ok(
  $$update public.decks set icon = 'rocket', color = 'teal', updated_at = now()
    where id = 'd0000000-0000-4000-8000-00000000000a'$$,
  'the owner stores keys no client knows yet, since no list checks them');
select results_eq(
  $$select icon, color from public.decks where id = 'd0000000-0000-4000-8000-00000000000a'$$,
  $$values ('rocket', 'teal')$$,
  'the deck holds the keys as written');
select throws_ok(
  $$update public.decks set icon = repeat('x', 41) where id = 'd0000000-0000-4000-8000-00000000000a'$$,
  '23514', null, 'an icon key over 40 characters is refused');
select throws_ok(
  $$update public.decks set color = repeat('x', 41) where id = 'd0000000-0000-4000-8000-00000000000a'$$,
  '23514', null, 'a colour key over 40 characters is refused');
-- Control: a key of exactly 40 characters is stored, so the bound is the length and no less.
select lives_ok(
  $$update public.decks set icon = repeat('x', 40), color = repeat('y', 40)
    where id = 'd0000000-0000-4000-8000-00000000000a'$$,
  'keys of 40 characters are stored');

-- Row-level security still applies: A reaches B's private deck neither to read nor to write it.
select is_empty(
  $$select icon from public.decks where id = 'd0000000-0000-4000-8000-00000000000b'$$,
  'A reads nothing of B''s private deck, its keys included');
select is_empty(
  $$update public.decks set icon = 'star' where id = 'd0000000-0000-4000-8000-00000000000b' returning id$$,
  'A''s update of B''s icon touches no row');
select throws_ok(
  $$insert into public.decks (id, user_id, name, created_at, updated_at, icon)
    values ('d0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000b', 'X', now(), now(), 'star')$$,
  '42501', null, 'A cannot insert a deck with keys owned by B');

reset role;
select results_eq(
  $$select icon, color from public.decks where id = 'd0000000-0000-4000-8000-00000000000b'$$,
  $$values (null::text, null::text)$$,
  'B''s deck still holds neither key');

select * from finish();
rollback;
