-- Card sounds (#391, ADR 0112): the media bucket accepts AAC in MPEG-4, as both phones record it,
-- and MP3, as a picked file may be, beside the JPEG it took; and a public deck's card sound is
-- read as its card photo is. Additive: the bucket's settings and one function's body change, its
-- signature, grants and the policy calling it stay, and no row of public.media, public.cards or
-- storage.objects is rewritten.

-- The bucket's ceiling stays 10 MiB a file; the app keeps a sound to 60 seconds and 5 MiB.
update storage.buckets
  set allowed_mime_types = array['image/jpeg', 'audio/mp4', 'audio/mpeg']
  where id = 'media';

-- Whether a live card of [owner_id]'s, in a deck of theirs that is public, not hidden and not
-- deleted, holds an image or an audio block naming [media_id] on its front or its back. As
-- 20261027100000_media_card_read.sql made it, otherwise: it runs as its definer, and a folder that
-- is not an id in its stored form names no card's file, and no cast is tried.
create or replace function public.media_in_public_card(owner_id text, media_id text) returns boolean
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
        where b.block ->> 'type' in ('image', 'audio')
          and b.block -> 'payload' ->> 'media' = media_id
      )
  );
end;
$$;
