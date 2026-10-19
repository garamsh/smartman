-- The read-only dry run of #228's migration of stored vocabulary backs to a senses block (#228):
-- which live cards it would convert, by which form, and which it leaves alone. It writes nothing,
-- and returns one row of JSON, the report supabase/senses-dry-run.sh formats.
--
-- The rules are the migration's, `private.senses_block` and the functions it calls
-- (supabase/migrations/20261019180002_senses_migration.sql), so the dry run reads what the apply
-- converts: a card converts only when its back is one text block whose every non-empty line is a
-- recognised sense line. A card with any other line (mixed) is left alone, so a note or free text
-- is never touched.
with forms as (
  select form, rank from private.sense_forms()
),
-- A front as its text blocks' text, for the report.
live as (
  select id, back,
    (select string_agg(block->'payload'->>'text', ' ')
      from jsonb_array_elements(front) as block
      where block->>'type' = 'text') as front
  from public.cards
  where deleted_at is null
),
-- A back of exactly one text block, its text.
texts as (
  select id, front, back->0->'payload'->>'text' as text
  from live
  where jsonb_array_length(back) = 1
    and back->0->>'type' = 'text'
    and jsonb_typeof(back->0->'payload'->'text') = 'string'
),
lines as (
  select texts.id, line.number, btrim(line.text) as text
  from texts,
    regexp_split_to_table(texts.text, E'\r?\n') with ordinality as line (text, number)
  where btrim(line.text) <> ''
),
-- Each line's first matching form, with its label, category and meaning.
matched as (
  select lines.id, lines.number, lines.text, s.form, s.label, s.category, s.meaning
  from lines
  left join lateral private.sense_line(lines.text) as s on true
),
cards as (
  select texts.id, texts.front, texts.text,
    count(matched.number) as lines,
    count(matched.form) as recognised,
    array_agg(distinct matched.form) filter (where matched.form is not null) as forms
  from texts
  left join matched on matched.id = texts.id
  group by texts.id, texts.front, texts.text
),
convertible as (
  select cards.* from cards
  join live on live.id = cards.id
  where private.senses_block(live.back) is not null
),
sample as (
  select form, jsonb_agg(card order by id) as cards
  from (
    select form, id, jsonb_build_object('id', id, 'front', front, 'back', text) as card,
      row_number() over (partition by form order by id) as n
    from convertible, unnest(forms) as form
  ) as each
  where n <= 5
  group by form
)
select jsonb_build_object(
  'live_cards', (select count(*) from live),
  'text_backs', (select count(*) from texts),
  'convertible', (select count(*) from convertible),
  'left_alone', jsonb_build_object(
    'not_one_text_block', (select count(*) from live) - (select count(*) from texts),
    'mixed', (select count(*) from cards where recognised > 0 and recognised < lines),
    'no_sense_line', (select count(*) from cards where recognised = 0)
  ),
  'forms', (
    select jsonb_agg(jsonb_build_object(
      'form', form,
      'cards', (select count(*) from convertible where form = any (convertible.forms)),
      'lines', (
        select count(*) from matched
        join convertible on convertible.id = matched.id
        where matched.form = forms.form
      ),
      'samples', coalesce((select cards from sample where sample.form = forms.form), '[]')
    ) order by rank)
    from forms
  ),
  -- Every bare-form line a conversion would take, for review: the label could be the first
  -- word of a meaning.
  'bare', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', matched.id, 'line', matched.text, 'label', matched.label,
      'category', matched.category, 'meaning', matched.meaning
    ) order by matched.id, matched.number), '[]')
    from matched
    join convertible on convertible.id = matched.id
    where matched.form = 'bare'
  ),
  -- A sample of the cards left alone with some sense lines, which a person may want converted.
  'mixed_samples', (
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'front', front, 'back', text)
      order by id), '[]')
    from (
      select * from cards where recognised > 0 and recognised < lines order by id limit 5
    ) as mixed
  )
) as report;
