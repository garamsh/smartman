-- Media storage (ADR 0107): the media table is its owner's alone, and the private bucket's objects,
-- named {owner}/{media id}, are written and deleted by their owner and read by their owner and by
-- any user the image of a public deck is shown to.
begin;
select plan(26);

select results_eq(
  $$select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'media'$$,
  $$values (false, 10485760::bigint, array['image/jpeg'])$$,
  'the media bucket is private, holds JPEG files alone, and at most 10 MiB each');

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');
-- A's deck, private for now, whose image is A's media 1.
insert into public.decks (id, user_id, name, created_at, updated_at, image_media_id) values
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000a', 'A', now(), now(),
   'e0000000-0000-4000-8000-000000000001');
-- The bucket's delete guard stands in front of every statement; the tests below are of the policies.
set local storage.allow_delete_query to 'true';

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

-- The table.
select lives_ok(
  $$insert into public.media (id, user_id, kind, mime_type, byte_size, sha256) values
    ('e0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000000a', 'image',
     'image/jpeg', 1000, repeat('a', 64)),
    ('e0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'image',
     'image/jpeg', 1000, repeat('b', 64))$$,
  'the owner inserts its media rows');
select results_eq(
  $$select count(*)::int from public.media$$, $$values (2)$$,
  'the owner reads its media rows');
select throws_ok(
  $$insert into public.media (id, user_id, kind, mime_type, byte_size, sha256) values
    ('e0000000-0000-4000-8000-000000000009', '00000000-0000-4000-8000-00000000000b', 'image',
     'image/jpeg', 1000, repeat('a', 64))$$,
  '42501', null, 'A cannot insert a media row owned by B');
select throws_ok(
  $$update public.media set byte_size = 2 where id = 'e0000000-0000-4000-8000-000000000001'$$,
  '42501', null, 'no one updates a media row');
select throws_ok(
  $$insert into public.media (id, user_id, kind, mime_type, byte_size, sha256) values
    ('e0000000-0000-4000-8000-000000000008', '00000000-0000-4000-8000-00000000000a', 'video',
     'image/jpeg', 1000, repeat('a', 64))$$,
  '23514', null, 'a kind other than image or audio is refused');
select throws_ok(
  $$insert into public.media (id, user_id, kind, mime_type, byte_size, sha256) values
    ('e0000000-0000-4000-8000-000000000008', '00000000-0000-4000-8000-00000000000a', 'image',
     'image/jpeg', 10485761, repeat('a', 64))$$,
  '23514', null, 'a file over 10 MiB is refused');
-- Control: a row of exactly 10 MiB is stored, so the bound is the ceiling and no less.
select lives_ok(
  $$insert into public.media (id, user_id, kind, mime_type, byte_size, sha256) values
    ('e0000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-00000000000a', 'image',
     'image/jpeg', 10485760, repeat('c', 64))$$,
  'a file of exactly 10 MiB is stored');
select throws_ok(
  $$insert into public.media (id, user_id, kind, mime_type, byte_size, sha256) values
    ('e0000000-0000-4000-8000-000000000008', '00000000-0000-4000-8000-00000000000a', 'image',
     'image/jpeg', 1000, repeat('A', 64))$$,
  '23514', null, 'a digest that is not 64 lowercase hex digits is refused');

-- The objects.
select lives_ok(
  $$insert into storage.objects (bucket_id, name) values
    ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001'),
    ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000002')$$,
  'the owner uploads the objects its media rows name');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values
    ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000007')$$,
  '42501', null, 'an object no media row names is refused');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values
    ('media', 'x/00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'an object under any other path than {owner}/{media id} is refused');
select results_eq(
  $$select count(*)::int from storage.objects where bucket_id = 'media'$$, $$values (2)$$,
  'the owner reads its objects');

-- B, while A's deck is private.
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select is_empty($$select id from public.media$$, 'B reads none of A''s media rows');
select is_empty(
  $$delete from public.media returning id$$, 'B''s delete of A''s media rows touches none');
select is_empty(
  $$select name from storage.objects where bucket_id = 'media'$$,
  'B reads none of A''s objects while A''s deck is private');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values
    ('media', '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'B cannot upload into A''s folder, even under the name of A''s media row');

-- A publishes the deck.
reset role;
update public.decks set visibility = 'public', published_at = now()
  where id = 'd0000000-0000-4000-8000-00000000000a';
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';

select results_eq(
  $$select name from storage.objects where bucket_id = 'media'$$,
  $$values ('00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000001')$$,
  'B reads the image of A''s public deck, and none of A''s other objects');
select is_empty($$select id from public.media$$, 'B still reads none of A''s media rows');
select is_empty(
  $$update storage.objects set name = name || 'x' where bucket_id = 'media' returning name$$,
  'B''s update of the public deck''s image touches no object');
select is_empty(
  $$delete from storage.objects where bucket_id = 'media' returning name$$,
  'B''s delete of the public deck''s image touches no object');

-- A hidden deck shows its image to no one but its owner.
reset role;
update public.decks set hidden = true where id = 'd0000000-0000-4000-8000-00000000000a';
set local role authenticated;
select is_empty(
  $$select name from storage.objects where bucket_id = 'media'$$,
  'B reads nothing once A''s public deck is hidden');

-- A public deck of B's naming A's media reads nothing of A's.
reset role;
insert into public.decks (id, user_id, name, created_at, updated_at, visibility, published_at, image_media_id)
  values ('d0000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000b', 'B', now(), now(),
          'public', now(), 'e0000000-0000-4000-8000-000000000002');
set local role authenticated;
select is_empty(
  $$select name from storage.objects where bucket_id = 'media'$$,
  'a deck names only its owner''s files, so B''s deck naming A''s media reads nothing');

-- A deletes its object and row; the objects of no one else are touched.
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';
select results_eq(
  $$with gone as (delete from storage.objects where bucket_id = 'media'
      and name = '00000000-0000-4000-8000-00000000000a/e0000000-0000-4000-8000-000000000002' returning 1)
    select count(*)::int from gone$$,
  $$values (1)$$,
  'the owner deletes its object');
select results_eq(
  $$with gone as (delete from public.media where id = 'e0000000-0000-4000-8000-000000000002' returning 1)
    select count(*)::int from gone$$,
  $$values (1)$$,
  'the owner deletes its media row');

-- Deleting the account deletes its media rows by cascade.
reset role;
delete from auth.users where id = '00000000-0000-4000-8000-00000000000a';
select is_empty($$select id from public.media$$, 'deleting the user deletes its media rows');

select * from finish();
rollback;
