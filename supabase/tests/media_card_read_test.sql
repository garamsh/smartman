-- Card photos of public decks (ADR 0109): any signed-in user reads an object of the media bucket
-- that an image block names in a live card of its owner's, in a public deck that is not hidden or
-- deleted, on the card's front or its back; any other of the owner's objects stays the owner's.
begin;
select plan(20);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
-- A's decks: public, private, public and hidden, public and deleted. B's: one public, and one
-- private holding B's copy of A's front-photo card, which keeps A's media id as a copy does.
insert into public.decks (id, user_id, name, created_at, updated_at, visibility, published_at, hidden, deleted_at) values
  ('d0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000a', 'public', now(), now(), 'public', now(), false, null),
  ('d0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'private', now(), now(), 'private', null, false, null),
  ('d0000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-00000000000a', 'hidden', now(), now(), 'public', now(), true, null),
  ('d0000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-00000000000a', 'deleted', now(), now(), 'public', now(), false, now()),
  ('d0000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-00000000000b', 'B public', now(), now(), 'public', now(), false, null),
  ('d0000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-00000000000b', 'B copy', now(), now(), 'private', null, false, null);
-- Media n is the photo of A's card n: 1 on a front, 2 on a back, 3 in the private deck, 4 on a
-- card deleted below, 5 in the hidden deck, 8 in the deleted deck. Media 6 is in no card, and 7
-- is named only by B's public card.
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at) values
  ('c0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   '[{"type":"image","v":1,"id":"p1","payload":{"media":"e0000000-0000-4000-8000-000000000001","width":4,"height":3,"boxes":[]}}]', '[{"type":"text","v":1,"payload":"word"}]', 'front photo', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   '[{"type":"text","v":1,"payload":"word"}]', '[{"type":"image","v":1,"id":"p2","payload":{"media":"e0000000-0000-4000-8000-000000000002","width":4,"height":3,"boxes":[]}}]', 'back photo', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000002',
   '[{"type":"image","v":1,"id":"p3","payload":{"media":"e0000000-0000-4000-8000-000000000003","width":4,"height":3,"boxes":[]}}]', '[{"type":"text","v":1,"payload":"word"}]', 'private', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   '[{"type":"image","v":1,"id":"p4","payload":{"media":"e0000000-0000-4000-8000-000000000004","width":4,"height":3,"boxes":[]}}]', '[{"type":"text","v":1,"payload":"word"}]', 'deleted card', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000003',
   '[{"type":"image","v":1,"id":"p5","payload":{"media":"e0000000-0000-4000-8000-000000000005","width":4,"height":3,"boxes":[]}}]', '[{"type":"text","v":1,"payload":"word"}]', 'hidden', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-000000000008', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000004',
   '[{"type":"image","v":1,"id":"p8","payload":{"media":"e0000000-0000-4000-8000-000000000008","width":4,"height":3,"boxes":[]}}]', '[{"type":"text","v":1,"payload":"word"}]', 'deleted deck', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-0000000000b7', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-0000000000b1',
   '[{"type":"image","v":1,"id":"p7","payload":{"media":"e0000000-0000-4000-8000-000000000007","width":4,"height":3,"boxes":[]}}]', '[{"type":"text","v":1,"payload":"word"}]', 'naming A', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-0000000000b2',
   '[{"type":"image","v":1,"id":"p1","payload":{"media":"e0000000-0000-4000-8000-000000000001","width":4,"height":3,"boxes":[]}}]', '[{"type":"text","v":1,"payload":"word"}]', 'front photo', 'manual', now(), now());
update public.cards set deleted_at = now() where id = 'c0000000-0000-4000-8000-000000000004';
insert into storage.objects (bucket_id, name) values
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000002'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000003'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000004'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000005'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000006'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000007'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000008');

select results_eq(
  $$select count(*)::int from storage.objects where bucket_id = 'media'$$, $$values (8)$$,
  'setup: A owns eight objects');
select results_eq(
  $$select count(*)::int from public.cards where deleted_at is null$$, $$values (7)$$,
  'setup: every card but the deleted one is live');

-- The bucket's delete guard stands in front of every statement; the test below is of the policies.
set local storage.allow_delete_query to 'true';

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';

select results_eq(
  $$select name from storage.objects where bucket_id = 'media' order by name$$,
  $$values ('00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001'), ('00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000002')$$,
  'B reads the photos on the front and the back of A''s public cards, and none of A''s others');
select isnt_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001'$$, 'B, who copied the card, reads its photo in A''s folder');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000003'$$, 'a private deck''s card photo is refused');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000004'$$, 'a deleted card''s photo is refused');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000005'$$, 'a hidden deck''s card photo is refused');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000008'$$, 'a deleted deck''s card photo is refused');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000006'$$, 'a photo A keeps in no card is refused');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000007'$$, 'a public card of B''s naming A''s media reads nothing of A''s');
select is_empty(
  $$delete from storage.objects where bucket_id = 'media' returning name$$,
  'B deletes none of the photos it reads');

-- Controls: each refused photo is read once the one thing refusing it changes.
reset role;
update public.decks set visibility = 'public', published_at = now() where id = 'd0000000-0000-4000-8000-000000000002';
update public.cards set deleted_at = null where id = 'c0000000-0000-4000-8000-000000000004';
update public.decks set hidden = false where id = 'd0000000-0000-4000-8000-000000000003';
update public.decks set deleted_at = null where id = 'd0000000-0000-4000-8000-000000000004';
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at) values
  ('c0000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   '[{"type":"image","v":1,"id":"p6","payload":{"media":"e0000000-0000-4000-8000-000000000006","width":4,"height":3,"boxes":[]}}]', '[{"type":"text","v":1,"payload":"word"}]', 'photo six', 'manual', now(), now());
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select isnt_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000003'$$, 'control: the private deck''s card photo is read once the deck is public');
select isnt_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000004'$$, 'control: the deleted card''s photo is read once the card is live');
select isnt_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000005'$$, 'control: the hidden deck''s card photo is read once the deck is shown');
select isnt_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000008'$$, 'control: the deleted deck''s card photo is read once the deck is live');
select isnt_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000006'$$, 'control: the photo in no card is read once a public card holds it');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000007'$$, 'and B''s card still reads nothing of A''s');
select is(
  public.media_in_public_card('not-an-id', 'e0000000-0000-4000-8000-000000000001'), false,
  'a folder that is not an owner id names no card''s photo, and raises nothing');

-- Anyone not signed in reads none of them.
reset role;
set local role anon;
select is_empty(
  $$select name from storage.objects where bucket_id = 'media'$$,
  'a reader not signed in reads no photo');
select throws_ok(
  $$select public.media_in_public_card('00000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'nor calls the function that decides');

select * from finish();
rollback;
