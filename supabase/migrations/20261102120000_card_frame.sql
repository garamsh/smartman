-- Every card in the 칸 frame (#549, ADR 0137 as amended by ADR 0140): each live card of `free` v1,
-- or of no template or of `flip`, `cloze` or `table` v1, takes its 칸 list in `front`, `[]` in `back`
-- and `free` v2. It changes existing data, which the PM approved under the owner's goal on
-- 2026-11-02 on the dry run recorded on #488 (server.md §Gate).
--
-- `private.card_frame_backup` keeps every row changed whole, readable by no client, and
-- `private.revert_card_frame()` rolls the change back. A card's revision is drawn anew by its update
-- trigger, so every device pulls it; its `card_key` and `updated_at` stay, so a device holding the
-- card synced takes the server's copy on the tie and an edit not yet pushed wins it (sync.md). A
-- tombstone, a card already in the frame, and a template or version no build wrote are left alone.

-- Whether [text] holds nothing the app's `trim` would keep, which is what makes a 글 empty.
create function private.card_frame_is_empty(text text) returns boolean
language sql
immutable
set search_path = ''
as $$
  select text !~ E'[^\\u0009-\\u000d\\u0020\\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]';
$$;

-- Whether the conversion can read [block]: a type at a version some build wrote, holding the fields
-- the conversion reads, as `decodeBlock` in app/lib/deck/src/content.dart reads them.
create function private.card_frame_reads(block jsonb) returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(case
    when jsonb_typeof(block) is distinct from 'object'
      or coalesce(jsonb_typeof(block->'id'), 'null') not in ('null', 'string')
      or jsonb_typeof(coalesce(block->'v', '1')) <> 'number'
      or (coalesce(block->'v', '1'))::numeric < 1
      or (coalesce(block->'v', '1'))::numeric <> trunc((coalesce(block->'v', '1'))::numeric)
      or (coalesce(block->'v', '1'))::numeric > (case block->>'type' when 'table' then 2 else 1 end)
      then false
    else case block->>'type'
      when 'text' then jsonb_typeof(block->'payload'->'text') = 'string'
      when 'cloze' then jsonb_typeof(block->'payload'->'text') = 'string'
        and jsonb_typeof(block->'payload'->'answers') = 'array'
        and not jsonb_path_exists(block->'payload'->'answers', 'strict $[*] ? (@.type() != "string")')
        and jsonb_array_length(block->'payload'->'answers') > 0
        and array_length(string_to_array(block->'payload'->>'text', '___'), 1) - 1
          = jsonb_array_length(block->'payload'->'answers')
      when 'table' then jsonb_typeof(block->'payload'->'columns') = 'array'
        and jsonb_typeof(block->'payload'->'rows') = 'array'
        and jsonb_array_length(block->'payload'->'columns') > 0
        and jsonb_array_length(block->'payload'->'rows') > 0
        and not jsonb_path_exists(block->'payload'->'columns', 'strict $[*] ? (@.type() != "string")')
        and not jsonb_path_exists(block->'payload'->'rows', 'strict $[*] ? (@.type() != "array")')
        and not jsonb_path_exists(block->'payload'->'rows', 'strict $[*][*] ? (@.type() != "string")')
      when 'senses' then jsonb_typeof(block->'payload'->'senses') = 'array'
        and jsonb_array_length(block->'payload'->'senses') > 0
      when 'image' then jsonb_typeof(block->'payload'->'media') = 'string'
        and jsonb_typeof(block->'payload'->'boxes') = 'array'
        and not jsonb_path_exists(block->'payload'->'boxes', 'strict $[*] ? (@.type() != "object")')
      when 'audio' then jsonb_typeof(block->'payload'->'media') = 'string'
      else false
    end
  end, false);
$$;

-- Whether [block] holds blanks: a cloze, a table or an image with a box.
create function private.card_frame_has_blank(block jsonb) returns boolean
language sql
immutable
set search_path = ''
as $$
  select block->>'type' in ('cloze', 'table')
    or (block->>'type' = 'image' and block->'payload'->'boxes' <> '[]');
$$;

-- A cloze with each blank filled, or a table as text, as `filled` in content.dart has them.
create function private.card_frame_filled(block jsonb) returns text
language sql
immutable
set search_path = ''
as $$
  select case block->>'type'
    when 'cloze' then (
      select string_agg(part.text || coalesce(block->'payload'->'answers'->>(part.number::int - 1), ''),
        '' order by part.number)
      from unnest(string_to_array(block->'payload'->>'text', '___')) with ordinality
        as part (text, number)
    )
    when 'table' then (
      select string_agg(line.text, E'\n' order by line.number)
      from (
        select row.number, (
          select string_agg(cell.text, ' | ' order by cell.number)
          from jsonb_array_elements_text(row.cells) with ordinality as cell (text, number)
        ) as text
        from jsonb_array_elements(
          jsonb_build_array(block->'payload'->'columns') || (block->'payload'->'rows')
        ) with ordinality as row (cells, number)
      ) as line
    )
  end;
$$;

-- [fields] as a stored block of [type] at version 2, with [owner]'s id when it has one.
create function private.card_frame_cell(type text, fields jsonb, owner jsonb) returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('type', type, 'v', 2, 'payload', fields)
    || case when jsonb_typeof(owner->'id') = 'string'
      then jsonb_build_object('id', owner->'id') else '{}'::jsonb end;
$$;

-- What [cell], a `text` block read or written by the conversion, shows before and adds by the reveal.
create function private.card_frame_text_front(cell jsonb) returns text
language sql
immutable
set search_path = ''
as $$
  select case when cell->>'v' = '2' then cell->'payload'->>'front'
    else cell->'payload'->>'text' end;
$$;

create function private.card_frame_text_back(cell jsonb) returns text
language sql
immutable
set search_path = ''
as $$
  select case when cell->>'v' = '2' then cell->'payload'->>'back' else '' end;
$$;

-- A card's two side lists as its 칸 list, by the rule of ADR 0137 as amended by ADR 0140, the rule of
-- `cellsFromSides` in app/lib/deck/src/card_frame.dart and supabase/fixtures/card-frame/. Null when
-- the card stays as it is: a block it cannot read, or a 글 it would write holding no text, which
-- no client reads as a stored 칸 and which only the backup could then keep.
create function private.card_frame(front jsonb, back jsonb) returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  cells jsonb := front;
  block jsonb;
  at integer;
  front_blank boolean;
  answers text;
begin
  if not coalesce((
    select bool_and(private.card_frame_reads(each.block))
    from jsonb_array_elements(front || back) as each (block)
  ), true) then
    return null;
  end if;

  front_blank := coalesce((
    select bool_or(private.card_frame_has_blank(each.block))
    from jsonb_array_elements(front) as each (block)
  ), false);

  -- The derived back: the front's filled text, exactly (ADR 0140).
  if front_blank and jsonb_array_length(back) = 1 and back->0->>'type' = 'text' and not exists (
    select 1 from jsonb_array_elements(front) as each (block)
    where each.block->>'type' not in ('text', 'cloze', 'table')
  ) and back->0->'payload'->>'text' = (
    select string_agg(
      case when each.block->>'type' = 'text' then each.block->'payload'->>'text'
        else private.card_frame_filled(each.block) end,
      E'\n' order by each.number)
    from jsonb_array_elements(front) with ordinality as each (block, number)
  ) then
    return cells;
  end if;

  -- A front's one word takes a back of one text as its term.
  if jsonb_array_length(back) = 1 and back->0->>'type' = 'text' and (
    select count(*) from jsonb_array_elements(front) as each (block)
    where each.block->>'type' = 'senses'
  ) = 1 then
    select each.number::int - 1, each.block into at, block
    from jsonb_array_elements(front) with ordinality as each (block, number)
    where each.block->>'type' = 'senses';
    return jsonb_set(cells, array[at::text], private.card_frame_cell('senses',
      block->'payload' || jsonb_build_object('term', back->0->'payload'->'text', 'ask', 'meaning'),
      block));
  end if;

  for block in select each.block from jsonb_array_elements(back) as each (block) loop
    case
      when block->>'type' = 'text' then
        select min(each.number)::int - 1 into at
        from jsonb_array_elements(cells) with ordinality as each (block, number)
        where each.block->>'type' = 'text'
          and private.card_frame_text_front(each.block) <> ''
          and private.card_frame_text_back(each.block) = '';
        if at is null then
          cells := cells || private.card_frame_cell('text',
            jsonb_build_object('front', '', 'back', block->'payload'->'text'), block);
        else
          cells := jsonb_set(cells, array[at::text], private.card_frame_cell('text',
            jsonb_build_object('front', private.card_frame_text_front(cells->at),
              'back', block->'payload'->'text'), cells->at));
        end if;

      when block->>'type' = 'senses' then
        if jsonb_array_length(cells) = 1 and cells->0->>'type' = 'text'
          and private.card_frame_text_back(cells->0) = '' then
          cells := jsonb_build_array(private.card_frame_cell('senses',
            block->'payload' || jsonb_build_object(
              'term', private.card_frame_text_front(cells->0), 'ask', 'term'),
            cells->0));
        else
          cells := cells || private.card_frame_cell('senses',
            block->'payload' || jsonb_build_object('term', '', 'ask', 'term'), block);
        end if;

      when block->>'type' in ('cloze', 'table') and front_blank then
        cells := cells || private.card_frame_cell('text',
          jsonb_build_object('front', '', 'back', private.card_frame_filled(block)), block);

      when block->>'type' = 'image' and front_blank and private.card_frame_has_blank(block) then
        cells := cells || private.card_frame_cell('image',
          block->'payload' || '{"boxes": [], "side": "back"}', block);
        select string_agg(box.value->>'answer', E'\n' order by box.number) into answers
        from jsonb_array_elements(block->'payload'->'boxes') with ordinality
          as box (value, number);
        if answers is not null then
          cells := cells || private.card_frame_cell('text',
            jsonb_build_object('front', '', 'back', answers), '{}');
        end if;

      when private.card_frame_has_blank(block) then
        cells := cells || block;

      else
        cells := cells || private.card_frame_cell(block->>'type',
          block->'payload' || '{"side": "back"}', block);
    end case;
  end loop;

  if exists (
    select 1 from jsonb_array_elements(cells) as each (cell)
    where each.cell->>'type' = 'text' and each.cell->>'v' = '2'
      and private.card_frame_is_empty(private.card_frame_text_front(each.cell))
      and private.card_frame_is_empty(private.card_frame_text_back(each.cell))
  ) then
    return null;
  end if;
  return cells;
end;
$$;

-- Each row the migration changed, whole, with the `front` it wrote. Readable by no client, and gone
-- with its card, so with its account too; a later migration drops it once the owner closes the
-- window.
create table private.card_frame_backup (
  card_id uuid primary key references public.cards (id) on delete cascade,
  user_id uuid not null,
  front jsonb not null,
  back jsonb not null,
  template text,
  template_version smallint,
  written jsonb not null,
  migrated_at timestamptz not null default now()
);

alter table private.card_frame_backup enable row level security;
revoke all on private.card_frame_backup from public, anon, authenticated;

-- Converts every live card of a template some build wrote at version 1, or of none, keeping each
-- row in the backup first, and returns how many it converted. A second run converts none: `free` v2
-- is not among the templates it reads. A card it left is named by a notice's count.
create function private.migrate_card_frame() returns integer
language plpgsql
set search_path = ''
as $$
declare
  converted integer;
  remaining integer;
begin
  -- Held before any row is read, so the row kept is the row replaced and no writer holding a user's
  -- revision lock can wait on a row of this transaction. Reads go on.
  lock table public.cards in share row exclusive mode;

  with frames as (
    select c.id, c.user_id, c.front, c.back, c.template, c.template_version,
      private.card_frame(c.front, c.back) as written
    from public.cards as c
    where c.deleted_at is null
      and (c.template is null
        or (c.template in ('free', 'flip', 'cloze', 'table') and c.template_version = 1))
  ),
  kept as (
    insert into private.card_frame_backup
      (card_id, user_id, front, back, template, template_version, written)
    select id, user_id, front, back, template, template_version, written
    from frames
    where written is not null
    on conflict (card_id) do nothing
  )
  update public.cards as c
  set front = frames.written, back = '[]', template = 'free', template_version = 2
  from frames
  where c.id = frames.id and frames.written is not null;
  get diagnostics converted = row_count;

  select count(*) into remaining
  from public.cards as c
  where c.deleted_at is null
    and (c.template is null
      or (c.template in ('free', 'flip', 'cloze', 'table') and c.template_version = 1));
  raise notice 'card frame: % cards converted, % left as they are', converted, remaining;
  return converted;
end;
$$;

-- The side and block of each part of [cell], in order, as `sidesOf` in card_frame.dart projects it:
-- every part shown before the reveal on the front, every part added by it on the back, and a 칸
-- with blanks or of a shape this function does not know on the front, as it is stored.
create function private.card_frame_parts(cell jsonb)
returns table (side text, block jsonb)
language plpgsql
immutable
set search_path = ''
as $$
declare
  ids jsonb := case when jsonb_typeof(cell->'id') = 'string'
    then jsonb_build_object('id', cell->'id') else '{}'::jsonb end;
  payload jsonb := cell->'payload';
  term jsonb;
  meanings jsonb;
begin
  if cell->>'type' = 'text' and cell->>'v' = '2' and jsonb_typeof(payload->'front') = 'string'
    and jsonb_typeof(payload->'back') = 'string' then
    if payload->>'front' <> '' then
      side := 'front';
      block := jsonb_build_object('type', 'text', 'v', 1,
        'payload', jsonb_build_object('text', payload->'front')) || ids;
      return next;
    end if;
    if payload->>'back' <> '' then
      side := 'back';
      block := jsonb_build_object('type', 'text', 'v', 1,
        'payload', jsonb_build_object('text', payload->'back'))
        || case when payload->>'front' = '' then ids else '{}'::jsonb end;
      return next;
    end if;
    return;
  end if;

  if cell->>'type' = 'senses' and cell->>'v' = '2' and jsonb_typeof(payload->'term') = 'string'
    and payload->>'ask' in ('term', 'meaning') then
    meanings := jsonb_build_object('type', 'senses', 'v', 1,
      'payload', payload - 'term' - 'ask') || ids;
    term := case when payload->>'term' <> '' then jsonb_build_object('type', 'text', 'v', 1,
      'payload', jsonb_build_object('text', payload->'term')) end;
    if payload->>'ask' = 'term' then
      if term is not null then
        side := 'front';
        block := term;
        return next;
      end if;
      side := 'back';
      block := meanings;
      return next;
    else
      side := 'front';
      block := meanings;
      return next;
      if term is not null then
        side := 'back';
        block := term;
        return next;
      end if;
    end if;
    return;
  end if;

  if cell->>'type' in ('image', 'audio') and cell->>'v' = '2' then
    side := case when payload->>'side' = 'back' then 'back' else 'front' end;
    block := jsonb_build_object('type', cell->'type', 'v', 1, 'payload', payload - 'side') || ids;
    return next;
    return;
  end if;

  side := 'front';
  block := cell;
  return next;
end;
$$;

-- Rolls the frame back, and returns how many cards it changed; it runs again until no device writes
-- the frame. A backed-up card still as the migration wrote it takes back its row exactly. Any other
-- live card in the frame, written there since or before the migration, takes the projection of its
-- 칸 list at `free` v1. Each takes a new revision and keeps `updated_at` and `card_key`. A tombstone
-- stays, and so does a card a build has since written outside the frame.
create function private.revert_card_frame() returns integer
language plpgsql
set search_path = ''
as $$
declare
  restored integer;
  projected integer;
begin
  lock table public.cards in share row exclusive mode;

  update public.cards as c
  set front = b.front, back = b.back, template = b.template, template_version = b.template_version
  from private.card_frame_backup as b
  where c.id = b.card_id
    and c.deleted_at is null
    and c.template = 'free' and c.template_version = 2
    and c.front = b.written and c.back = '[]';
  get diagnostics restored = row_count;

  update public.cards as c
  set front = sides.front, back = sides.back || c.back, template = 'free', template_version = 1
  from public.cards as framed
  cross join lateral (
    select
      coalesce(jsonb_agg(part.block order by each.number, part.number)
        filter (where part.side = 'front'), '[]') as front,
      coalesce(jsonb_agg(part.block order by each.number, part.number)
        filter (where part.side = 'back'), '[]') as back
    from jsonb_array_elements(framed.front) with ordinality as each (cell, number)
    cross join lateral private.card_frame_parts(each.cell) with ordinality
      as part (side, block, number)
  ) as sides
  where c.id = framed.id
    and framed.deleted_at is null
    and framed.template = 'free' and framed.template_version = 2;
  get diagnostics projected = row_count;

  return restored + projected;
end;
$$;

revoke all on function private.card_frame_is_empty(text), private.card_frame_reads(jsonb),
  private.card_frame_has_blank(jsonb), private.card_frame_filled(jsonb),
  private.card_frame_cell(text, jsonb, jsonb), private.card_frame_text_front(jsonb),
  private.card_frame_text_back(jsonb), private.card_frame(jsonb, jsonb),
  private.migrate_card_frame(), private.card_frame_parts(jsonb), private.revert_card_frame()
  from public, anon, authenticated;

select private.migrate_card_frame();
