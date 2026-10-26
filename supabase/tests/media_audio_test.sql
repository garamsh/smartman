-- Card sounds (ADR 0112): any signed-in user reads an object of the media bucket that an audio
-- block names in a live card of its owner's, in a public deck that is not hidden or deleted, as a
-- card photo is read (ADR 0109); a sound in a private deck stays the owner's, and so does a file
-- a block of another type names.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
-- A's decks: one public, one private.
insert into public.decks (id, user_id, name, created_at, updated_at, visibility, published_at) values
  ('d0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000a', 'public', now(), now(), 'public', now()),
  ('d0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'private', now(), now(), 'private', null);
-- Sound 1 is on a public card's front, 2 on a public card's back, 3 on a private card's front.
-- Media 4 is named by a public card's block of an unknown type, as a later build might write.
insert into public.cards
  (id, user_id, deck_id, front, back, card_key, source, created_at, updated_at) values
  ('c0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   '[{"type":"audio","v":1,"id":"s1","payload":{"media":"e0000000-0000-4000-8000-000000000001","duration_ms":1200}}]', '[{"type":"text","v":1,"payload":{"text":"word"}}]', 'front sound', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   '[{"type":"text","v":1,"payload":{"text":"word"}}]', '[{"type":"audio","v":1,"id":"s2","payload":{"media":"e0000000-0000-4000-8000-000000000002","duration_ms":800}}]', 'back sound', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000002',
   '[{"type":"audio","v":1,"id":"s3","payload":{"media":"e0000000-0000-4000-8000-000000000003","duration_ms":800}}]', '[{"type":"text","v":1,"payload":{"text":"word"}}]', 'private sound', 'manual', now(), now()),
  ('c0000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   '[{"type":"video","v":1,"id":"v4","payload":{"media":"e0000000-0000-4000-8000-000000000004"}}]', '[{"type":"text","v":1,"payload":{"text":"word"}}]', 'other type', 'manual', now(), now());
insert into storage.objects (bucket_id, name) values
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000002'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000003'),
  ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000004');

select results_eq(
  $$select count(*)::int from storage.objects where bucket_id = 'media'$$, $$values (4)$$,
  'setup: A owns four objects');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';
select lives_ok(
  $$insert into public.media (user_id, id, kind, mime_type, byte_size, sha256) values
    ('00000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000001', 'audio',
     'audio/mp4', 9600, repeat('a', 64))$$,
  'A stores a row for a recording, of kind audio and type audio/mp4');

set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select results_eq(
  $$select name from storage.objects where bucket_id = 'media' order by name$$,
  $$values ('00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001'), ('00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000002')$$,
  'B reads the sounds on the front and the back of A''s public cards, and none of A''s others');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000003'$$, 'a private deck''s card sound is refused');
select is_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000004'$$, 'a file a block of another type names is refused');
select is(
  public.media_in_public_card('00000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000001'), true,
  'the function that decides names a public card''s sound');

-- Controls: the refused sound is read once its deck is public, and the other type's file once an
-- audio block names it.
reset role;
update public.decks set visibility = 'public', published_at = now() where id = 'd0000000-0000-4000-8000-000000000002';
update public.cards
  set front = '[{"type":"audio","v":1,"id":"s4","payload":{"media":"e0000000-0000-4000-8000-000000000004","duration_ms":500}}]'
  where id = 'c0000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select isnt_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000003'$$, 'control: the private deck''s card sound is read once the deck is public');
select isnt_empty($$select 1 from storage.objects where bucket_id = 'media' and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000004'$$, 'control: the other type''s file is read once an audio block names it');

-- Anyone not signed in reads none of them.
reset role;
set local role anon;
select is_empty(
  $$select name from storage.objects where bucket_id = 'media'$$,
  'a reader not signed in reads no sound');

select * from finish();
rollback;
