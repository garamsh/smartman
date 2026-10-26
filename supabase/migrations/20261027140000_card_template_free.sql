-- Every card as a 자유 card (#438, ADR 0114): each live card whose template is one an earlier app
-- wrote, `flip`, `cloze` or `table` at version 1, or none at all, becomes `free` at version 1, the
-- one template the app's editor now writes. Its content is not touched: a template only decides how
-- the editor opens a card, and study draws by the blocks (ADR 0106). It changes existing data, which
-- the owner approved on 2026-10-27. No backup is kept: the content is unchanged, and the template
-- before is what its front's blocks derive (ADR 0083), but for a card whose blocks were added to it
-- under ADR 0108.
--
-- A card's revision is drawn anew by its update trigger, so every device pulls it; its `updated_at`
-- is left as it was. A device holding the card synced takes the server's copy on the tie, and a
-- device edit not yet pushed wins the tie, or is later, and is pushed over this (sync.md). The app's
-- schema step 13 makes the same change on each device. A template, or a version, no app knows is
-- left as it is, and so is a tombstone, whose revision the purge reads.

-- Makes every live card of a template an earlier app wrote, or of none, `free` at version 1, and
-- returns how many it changed. A second run changes none, since `free` is not among the templates
-- it reads.
create function private.migrate_card_template_free() returns integer
language plpgsql
set search_path = ''
as $$
declare
  changed integer;
begin
  update public.cards as c
  set template = 'free', template_version = 1
  where c.deleted_at is null
    and (c.template is null
      or (c.template in ('flip', 'cloze', 'table') and c.template_version = 1));
  get diagnostics changed = row_count;
  return changed;
end;
$$;

revoke all on function private.migrate_card_template_free() from public, anon, authenticated;

select private.migrate_card_template_free();
