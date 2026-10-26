-- Card photos of public decks (#389, ADR 0109): a card's image block names its owner's media id,
-- and a copy of the card keeps that id, so a reader of a public deck, and anyone who copied it,
-- reads the photo from the owner's folder. Additive: one function and one select policy beside
-- media_objects_select (20261026140000_media.sql), and no row is rewritten.

-- Whether a live card of [owner_id]'s, in a deck of theirs that is public, not hidden and not
-- deleted, holds an image block naming [media_id] on its front or its back. It runs as its
-- definer, so the reader's row-level security on cards and decks does not decide it. A folder
-- that is not an id in its stored form names no card's photo, and no cast is tried.
create function public.media_in_public_card(owner_id text, media_id text) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if owner_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1 from public.cards as c
    join public.decks as d on d.user_id = c.user_id and d.id = c.deck_id
    where c.user_id = owner_id::uuid
      and c.deleted_at is null
      and d.visibility = 'public' and not d.hidden and d.deleted_at is null
      and exists (
        select 1 from jsonb_array_elements(c.front || c.back) as b(block)
        where b.block ->> 'type' = 'image' and b.block -> 'payload' ->> 'media' = media_id
      )
  );
end;
$$;

revoke all on function public.media_in_public_card(text, text) from public, anon;
grant execute on function public.media_in_public_card(text, text) to authenticated;

-- Any signed-in user reads an object of the bucket that such a card of its owner's names.
create policy media_objects_select_public_card on storage.objects for select to authenticated
  using (
    bucket_id = 'media'
    and public.media_in_public_card((storage.foldername(name))[1], storage.filename(name))
  );
