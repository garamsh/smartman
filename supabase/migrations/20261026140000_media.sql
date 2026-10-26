-- Media storage (#383, ADR 0107): a row per stored file, a private bucket holding each file under
-- {owner}/{media id}, its policies, and the deck's image as a media id. Additive: one table, one
-- bucket, one nullable column and their policies and grants, and no row is rewritten; a deck
-- without an image draws its icon.

-- One stored file. Cards and decks name it by id, never by URL, so moving the bytes elsewhere
-- changes how an id resolves and rewrites no row.
create table public.media (
  id uuid primary key,
  user_id uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('image', 'audio')),
  mime_type text not null check (char_length(mime_type) between 1 and 100),
  byte_size integer not null check (byte_size between 1 and 5242880),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create index media_user_id on public.media (user_id);

alter table public.media enable row level security;

-- A row is its owner's alone: written once, read and deleted by its owner, never updated.
revoke all on public.media from anon, authenticated;
grant select, insert, delete on public.media to authenticated;
create policy media_select on public.media for select to authenticated
  using ((select auth.uid()) = user_id);
create policy media_insert on public.media for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy media_delete on public.media for delete to authenticated
  using ((select auth.uid()) = user_id);

-- A deck's image, the id of one of its owner's media rows. No foreign key: a device pushes the
-- deck before its upload lands, and a reader draws the icon until the file can be read.
alter table public.decks add column image_media_id uuid;
grant insert (image_media_id) on public.decks to authenticated;
grant update (image_media_id) on public.decks to authenticated;

-- The private bucket; config.toml declares the same for the local stack. Its limits match the
-- table's checks.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('media', 'media', false, 5242880, array['image/jpeg'])
  on conflict (id) do nothing;

-- An object's name is {owner}/{media id}. Its owner writes it only after inserting the media row
-- it names, and reads and deletes it; no one updates one, so a stored file never changes.
create policy media_objects_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'media'
    and exists (
      select 1 from public.media as m
      where m.user_id = (select auth.uid()) and objects.name = m.user_id::text || '/' || m.id::text
    )
  );

-- The owner reads its own objects. Any signed-in user reads the image of a deck the decks policy
-- shows them as public: the deck must be the object's owner's, so no deck names another's file.
-- The object's name is qualified, since a deck has a name of its own.
create policy media_objects_select on storage.objects for select to authenticated
  using (
    bucket_id = 'media'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.decks as d
        where d.user_id::text = (storage.foldername(objects.name))[1]
          and d.image_media_id::text = storage.filename(objects.name)
          and d.visibility = 'public' and not d.hidden and d.deleted_at is null
      )
    )
  );

create policy media_objects_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
