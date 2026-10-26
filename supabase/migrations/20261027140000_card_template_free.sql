-- Every card as a 자유 card (#438, ADR 0114): each live card whose template is one an earlier app
-- wrote, `flip`, `cloze` or `table` at version 1, or none at all, becomes `free` at version 1, the
-- one template the app's editor now writes. Its content is not touched: a template only decides how
-- the editor opens a card, and study draws by the blocks (ADR 0106). It changes existing data, which
-- the owner approved on 2026-10-27. Each card's template before is kept in a backup table no client
-- can read, and `private.revert_card_template_free()` restores it.
--
-- A card's revision is drawn anew by its update trigger, so every device pulls it; its `updated_at`
-- is left as it was. A device holding the card synced takes the server's copy on the tie, and a
-- device edit not yet pushed wins the tie, or is later, and is pushed over this (sync.md). The app's
-- schema step 13 makes the same change on each device. A template, or a version, no app knows is
-- left as it is, and so is a tombstone, whose revision the purge reads.

-- Each migrated card's template and edit time as they were, the revert path. Readable by no client.
create table private.card_template_free_backup (
  card_id uuid primary key references public.cards (id) on delete cascade,
  template text,
  template_version smallint,
  updated_at timestamptz not null,
  migrated_at timestamptz not null default now()
);

alter table private.card_template_free_backup enable row level security;
revoke all on private.card_template_free_backup from public, anon, authenticated;

-- Makes every live card of a template an earlier app wrote, or of none, `free` at version 1,
-- keeping its template in the backup first, and returns how many it changed. A second run changes
-- none, since `free` is not among the templates it reads, and a card changed before keeps its first
-- backup.
create function private.migrate_card_template_free() returns integer
language plpgsql
set search_path = ''
as $$
declare
  changed integer;
begin
  -- The rows are locked as they are read, so the template kept is the template replaced.
  with locked as (
    select c.id, c.template, c.template_version, c.updated_at
    from public.cards as c
    where c.deleted_at is null
      and (c.template is null
        or (c.template in ('flip', 'cloze', 'table') and c.template_version = 1))
    for update
  ),
  kept as (
    insert into private.card_template_free_backup (card_id, template, template_version, updated_at)
    select locked.id, locked.template, locked.template_version, locked.updated_at from locked
    on conflict (card_id) do nothing
  )
  update public.cards as c
  set template = 'free', template_version = 1
  from locked
  where c.id = locked.id;
  get diagnostics changed = row_count;
  return changed;
end;
$$;

-- Restores each backed-up template on a live card still `free` at version 1 and not edited since,
-- its `updated_at` the one backed up, and returns how many it restored. A card edited since keeps
-- its edit. Like the migration, it draws new revisions and leaves `updated_at` as it was.
create function private.revert_card_template_free() returns integer
language plpgsql
set search_path = ''
as $$
declare
  restored integer;
begin
  update public.cards as c
  set template = b.template, template_version = b.template_version
  from private.card_template_free_backup as b
  where c.id = b.card_id
    and c.deleted_at is null
    and c.template = 'free'
    and c.template_version = 1
    and c.updated_at = b.updated_at;
  get diagnostics restored = row_count;
  return restored;
end;
$$;

revoke all on function private.migrate_card_template_free(), private.revert_card_template_free()
  from public, anon, authenticated;

select private.migrate_card_template_free();
