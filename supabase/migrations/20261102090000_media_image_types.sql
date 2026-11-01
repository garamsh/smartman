-- PNG and WebP photos (#531, ADR 0144): an MCP card's photo is stored as it was fetched, so the
-- media bucket accepts PNG and WebP beside the types it took. Additive: the bucket's settings alone
-- change, and no row of public.media, public.cards or storage.objects is rewritten.

update storage.buckets
  set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'audio/mp4', 'audio/mpeg']
  where id = 'media';
