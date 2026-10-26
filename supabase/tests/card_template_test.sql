-- A card's template and its version (ADR 0106): two nullable columns, the template never checked
-- against a list and the version a positive number, which the owner writes as it writes the
-- card's other columns, under the same row-level security.
begin;
select plan(13);

select col_is_null('public', 'cards', 'template', 'cards.template is nullable');
select col_is_null('public', 'cards', 'template_version', 'cards.template_version is nullable');

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'A', now(), now()),
  ('d0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'B', now(), now());
-- B's card, written as a client from before the migration writes one: without either column.
insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at) values
  ('c0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b',
   'd0000000-0000-4000-8000-00000000000b', '[]', '[]', 'b', 'manual', now(), now());
select results_eq(
  $$select template, template_version from public.cards where id = 'c0000000-0000-4000-8000-00000000000b'$$,
  $$values (null::text, null::smallint)$$,
  'a card written without the columns holds neither, so an app derives its template');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$insert into public.cards (id, deck_id, front, back, card_key, source, created_at, updated_at, template, template_version)
    values ('c0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000a',
      '[{"type":"text","v":1,"payload":{"text":"chat"}}]', '[]', 'chat', 'manual', now(), now(), 'flip', 1)$$,
  'the owner inserts a card with its template and version');
select lives_ok(
  $$update public.cards set template = 'image_occlusion', template_version = 2, updated_at = now()
    where id = 'c0000000-0000-4000-8000-00000000000a'$$,
  'the owner stores a template no client knows yet, since no list checks it');
select results_eq(
  $$select template, template_version from public.cards where id = 'c0000000-0000-4000-8000-00000000000a'$$,
  $$values ('image_occlusion'::text, 2::smallint)$$,
  'the card holds the template and version as written');
select throws_ok(
  $$update public.cards set template_version = 0 where id = 'c0000000-0000-4000-8000-00000000000a'$$,
  '23514', null, 'a template version below 1 is refused');
-- Control: a version of 1 is stored, so the check refuses nothing above its bound.
select lives_ok(
  $$update public.cards set template_version = 1 where id = 'c0000000-0000-4000-8000-00000000000a'$$,
  'a template version of 1 is stored');

-- Row-level security still applies: A reaches B's card neither to read nor to write it.
select is_empty(
  $$select template from public.cards where id = 'c0000000-0000-4000-8000-00000000000b'$$,
  'A reads nothing of B''s card, its template included');
select is_empty(
  $$update public.cards set template = 'flip' where id = 'c0000000-0000-4000-8000-00000000000b' returning id$$,
  'A''s update of B''s template touches no row');
select throws_ok(
  $$insert into public.cards (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at, template)
    values ('c0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000b',
      'd0000000-0000-4000-8000-00000000000b', '[]', '[]', 'x', 'manual', now(), now(), 'flip')$$,
  '42501', null, 'A cannot insert a card with a template owned by B');

reset role;
select results_eq(
  $$select template, template_version from public.cards where id = 'c0000000-0000-4000-8000-00000000000b'$$,
  $$values (null::text, null::smallint)$$,
  'B''s card still holds neither');
select is(
  (select count(*)::int from public.cards),
  2,
  'no other card was written');

select * from finish();
rollback;
