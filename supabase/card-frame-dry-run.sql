-- The read-only dry run of ADR 0137's migration of every card to the 칸 frame (#488): one row of
-- JSON that puts each live card in one placement of #475 and reports the cases the owner's choices
-- O2 and O3 decide, each with its count and up to five card ids. It is one select, so it writes
-- nothing, and it returns no card content.
--
-- A placement is the first of these that holds, so the placements add up to the live cards:
--   left         the migration leaves it: a template or version no build wrote, or a block of a
--                type or version no build wrote.
--   placement_6  a photo with boxes on either side, whatever else the card holds.
--   placement_1  an import or a copy of front [cloze], back [text].
--   placement_2  an import or a copy of front [text, table], back [text].
--   placement_3  front [cloze], any other back: the former 빈칸 form, which no stored field names.
--   placement_4  any other card with a blank on its front.
--   placement_5  a blank on its back alone.
--   placement_7  no blank, and a text block on either side holding a literal ___.
--   no_blank     every other card.
--
-- The rest overlap the placements and each other, and leave out the cards in `left`:
--   derived_filled_text  a back of one text block equal to a blanked front's filled text, which
--                        the migration drops.
--   derived_source       a back of one text block on a blanked front that differs from its filled
--                        text, on an import or a copy, which the migration keeps as a 글's back
--                        (ADR 0140).
--   o2                   a blanked front with any other back, which O2 shows after the answer.
--   o2_back_blank        the O2 cards whose back holds a blank, which the migration shows after
--                        the answer: a cloze or table as a 글's back of its filled text, a boxed
--                        image on the back without its boxes (ADR 0140).
--   o3                   a blank on the back alone beside a back text block, which O3 shows after
--                        the answer.
--
-- A blank is what `_hasBlank` in app/lib/deck/src/content.dart reads: any cloze or table block, or
-- an image with a box. A front's filled text is `plainText` of the same file. It is read here for
-- text, cloze and table blocks, the only ones photo import writes beside a blank, and a front
-- holding any other block equals no back.
with known (type, version) as (
  values ('text', 1), ('cloze', 1), ('table', 2), ('senses', 1), ('image', 1), ('audio', 1)
),
live as (
  select id, front, back, source, template, template_version
  from public.cards
  where deleted_at is null
),
blocks as (
  select live.id, sides.side, each.position, each.block->>'type' as type,
    each.block->'payload' as payload,
    exists (
      select 1 from known
      where known.type = each.block->>'type'
        and jsonb_typeof(coalesce(each.block->'v', '1')) = 'number'
        and (coalesce(each.block->'v', '1'))::numeric <= known.version
    ) as known
  from live
  cross join lateral (values ('front', live.front), ('back', live.back)) as sides (side, blocks)
  cross join lateral jsonb_array_elements(sides.blocks) with ordinality as each (block, position)
),
marked as (
  select blocks.*,
    type = 'image' and coalesce(payload->'boxes', '[]') not in ('[]', 'null') as boxed,
    type = 'text' and position('___' in coalesce(payload->>'text', '')) > 0 as literal,
    case type
      when 'text' then payload->>'text'
      when 'cloze' then (
        select string_agg(part.text || coalesce(payload->'answers'->>(part.number::int - 1), ''),
          '' order by part.number)
        from string_to_table(payload->>'text', '___') with ordinality as part (text, number)
      )
      when 'table' then (
        select string_agg(line.text, E'\n' order by line.number)
        from (
          select row.number, (
            select string_agg(cell.text, ' | ' order by cell.number)
            from jsonb_array_elements_text(jsonb_path_query_array(row.cells, '$[*]'))
              with ordinality as cell (text, number)
          ) as text
          from jsonb_array_elements(
            jsonb_build_array(payload->'columns') || jsonb_path_query_array(payload, '$.rows[*]')
          ) with ordinality as row (cells, number)
        ) as line
      )
    end as filled
  from blocks
),
cards as (
  select live.id, live.source,
    live.template is null
      or (live.template in ('free', 'flip', 'cloze', 'table') and live.template_version = 1)
      as template_known,
    coalesce(bool_and(marked.known), true) as blocks_known,
    coalesce(bool_or(marked.boxed), false) as boxed,
    coalesce(bool_or(marked.literal), false) as literal,
    coalesce(bool_or(marked.type in ('cloze', 'table') or marked.boxed)
      filter (where marked.side = 'front'), false) as front_blank,
    coalesce(bool_or(marked.type in ('cloze', 'table') or marked.boxed)
      filter (where marked.side = 'back'), false) as back_blank,
    coalesce(array_agg(marked.type order by marked.position)
      filter (where marked.side = 'front'), '{}') as front_types,
    coalesce(array_agg(marked.type order by marked.position)
      filter (where marked.side = 'back'), '{}') as back_types,
    string_agg(marked.filled, E'\n' order by marked.position)
      filter (where marked.side = 'front') as front_filled,
    coalesce(bool_and(marked.type in ('text', 'cloze', 'table'))
      filter (where marked.side = 'front'), true) as front_reads,
    (array_agg(marked.filled) filter (where marked.side = 'back'))[1] as back_text
  from live
  left join marked on marked.id = live.id
  group by live.id, live.source, live.template, live.template_version
),
derived as (
  select cards.*,
    not (template_known and blocks_known) as left_alone,
    source in ('import', 'copy') and back_types = '{text}' as derived_shape,
    case
      when not front_blank or back_types <> '{text}' then null
      when front_reads and back_text = front_filled then 'derived_filled_text'
      when source in ('import', 'copy') then 'derived_source'
    end as derived
  from cards
),
placed as (
  select derived.*,
    case
      when left_alone then 'left'
      when boxed then 'placement_6'
      when derived_shape and front_types = '{cloze}' then 'placement_1'
      when derived_shape and front_types = '{text,table}' then 'placement_2'
      when front_types = '{cloze}' then 'placement_3'
      when front_blank then 'placement_4'
      when back_blank then 'placement_5'
      when literal then 'placement_7'
      else 'no_blank'
    end as placement
  from derived
),
tagged as (
  select id, placement as tag from placed
  union all
  select id, derived from placed where not left_alone and derived is not null
  union all
  select id, 'o2' from placed
  where not left_alone and front_blank and back_types <> '{}' and derived is null
  union all
  select id, 'o2_back_blank' from placed
  where not left_alone and front_blank and back_blank and derived is null
  union all
  select id, 'o3' from placed
  where not left_alone and back_blank and not front_blank and 'text' = any (back_types)
),
ranked as (
  select tag, id, row_number() over (partition by tag order by id) as number
  from tagged
),
tags (tag) as (
  values ('placement_1'), ('placement_2'), ('placement_3'), ('placement_4'), ('placement_5'),
    ('placement_6'), ('placement_7'), ('no_blank'), ('left'), ('derived_filled_text'),
    ('derived_source'), ('o2'), ('o2_back_blank'), ('o3')
)
select jsonb_build_object('live_cards', (select count(*) from live))
  || jsonb_object_agg(tags.tag, jsonb_build_object(
    'cards', (select count(*) from ranked where ranked.tag = tags.tag),
    'samples', coalesce((
      select jsonb_agg(ranked.id order by ranked.id)
      from ranked
      where ranked.tag = tags.tag and ranked.number <= 5
    ), '[]')
  )) as report
from tags;
