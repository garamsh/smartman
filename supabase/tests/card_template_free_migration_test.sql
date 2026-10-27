-- The migration of every card to 자유 (#438, ADR 0114): each live card of `flip`, `cloze` or
-- `table` at version 1, or of no template, becomes `free` at version 1; a card already `free`, one of
-- a template or a version no app knows, and a deleted card are left alone; no front, back, card key,
-- edit time, review or card state changes, while each changed card's revision does; and a second run
-- changes nothing; neither anon nor authenticated can run it.
begin;
select plan(10);

insert into auth.users (id, email) values ('00000000-0000-4000-8000-00000000000a', 'a@example.com');
insert into public.decks (id, user_id, name, created_at, updated_at)
  values ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'Words',
    now(), now());
insert into public.cards (id, user_id, deck_id, front, back, card_key, source, template,
  template_version, created_at, updated_at, deleted_at)
select ('c0000000-0000-4000-8000-000000000' || id)::uuid, '00000000-0000-4000-8000-00000000000a',
  'd0000000-0000-4000-8000-00000000000a',
  jsonb_build_array(jsonb_build_object('type', 'text', 'v', 1, 'payload',
    jsonb_build_object('text', id))),
  '[{"type":"text","v":1,"payload":{"text":"back"}}]'::jsonb, id, 'manual', template, version,
  '2026-10-01 09:00:00+00', '2026-10-02 09:00:00.123+00', deleted
from (values
  ('c01', 'flip', 1::smallint, null::timestamptz),
  ('c02', 'cloze', 1, null),
  ('c03', 'table', 1, null),
  ('c04', null, null, null),
  ('c05', 'free', 1, null),
  ('c06', 'mindmap', 1, null),
  ('c07', 'flip', 2, null),
  ('c08', 'flip', 1, '2026-10-03 09:00:00+00')
) as fixture (id, template, version, deleted);
insert into public.reviews (id, user_id, card_id, rating, reviewed_at, duration_ms, updated_at)
  values ('e0000000-0000-4000-8000-000000000c01', '00000000-0000-4000-8000-00000000000a',
    'c0000000-0000-4000-8000-000000000c01', 'good', now(), 4000, now());
insert into public.card_states (user_id, card_id, stability, difficulty, last_review, due,
  updated_at)
  values ('00000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000c01', 3, 5,
    now(), now(), now());

create temp table cards_before as select * from public.cards;
create temp table reviews_before as select * from public.reviews;
create temp table states_before as select * from public.card_states;
create function pg_temp.cards(variadic ns text[]) returns setof uuid language sql as $$
  select ('c0000000-0000-4000-8000-000000000' || n)::uuid from unnest(ns) as n
$$;

select is(private.migrate_card_template_free(), 4,
  'the migration changes the four live cards of flip, cloze, table or no template');
select results_eq(
  $$ select id, template, template_version::int from public.cards order by id $$,
  $$ values
    ('c0000000-0000-4000-8000-000000000c01'::uuid, 'free', 1),
    ('c0000000-0000-4000-8000-000000000c02', 'free', 1),
    ('c0000000-0000-4000-8000-000000000c03', 'free', 1),
    ('c0000000-0000-4000-8000-000000000c04', 'free', 1),
    ('c0000000-0000-4000-8000-000000000c05', 'free', 1),
    ('c0000000-0000-4000-8000-000000000c06', 'mindmap', 1),
    ('c0000000-0000-4000-8000-000000000c07', 'flip', 2),
    ('c0000000-0000-4000-8000-000000000c08', 'flip', 1) $$,
  'each live card of an earlier template or none is free at version 1, and the free card, the unknown template, the newer version and the deleted card keep theirs');
select results_eq(
  $$ select id, revision from public.cards where id in (select pg_temp.cards('c05', 'c06', 'c07', 'c08'))
     order by id $$,
  $$ select id, revision from cards_before where id in (select pg_temp.cards('c05', 'c06', 'c07', 'c08'))
     order by id $$,
  'a card the migration leaves alone keeps its revision, a tombstone included, so the purge reads it as before');
select is((select count(*) from public.cards as c join cards_before as b using (id)
  where c.revision > b.revision)::int, 4,
  'each changed card takes a new revision, so every device pulls it');
select results_eq(
  $$ select id, front, back, card_key, source, created_at, updated_at, deleted_at, deck_id, user_id
     from public.cards order by id $$,
  $$ select id, front, back, card_key, source, created_at, updated_at, deleted_at, deck_id, user_id
     from cards_before order by id $$,
  'no content, card key or edit time changes, so a device edit not yet pushed still wins the merge');
select results_eq($$ select * from public.reviews $$, $$ select * from reviews_before $$,
  'no review changes');
select results_eq($$ select * from public.card_states $$, $$ select * from states_before $$,
  'no card state changes');

select is(private.migrate_card_template_free(), 0, 'a second run changes nothing');

select function_privs_are('private', 'migrate_card_template_free', '{}', 'authenticated', '{}',
  'authenticated cannot run the migration');
select function_privs_are('private', 'migrate_card_template_free', '{}', 'anon', '{}',
  'anon cannot run the migration');

select * from finish();
rollback;
