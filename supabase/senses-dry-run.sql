-- The read-only dry run of #228's migration of stored vocabulary backs to a senses block (#228):
-- which live cards it would convert, by which form, and which it leaves alone. It writes nothing,
-- and returns one row of JSON, the report supabase/senses-dry-run.sh formats.
--
-- A card converts only when its back is one text block whose every non-empty line is a
-- recognised sense line: a known short form as a label, in brackets, in parentheses, with a dot,
-- or bare and followed by a space and more text, then the meaning. A card with any other line
-- (mixed) is left alone, so a note or free text is never touched.
with labels (label, category) as (
  values
    ('명', 'noun'), ('동', 'verb'), ('형', 'adjective'), ('부', 'adverb'), ('대', 'pronoun'),
    ('전', 'preposition'), ('접', 'conjunction'), ('감', 'interjection'), ('관', 'determiner'),
    ('수', 'numeral'), ('조', 'particle'), ('조동', 'auxiliary'), ('양', 'classifier'),
    ('구', 'phrase'),
    ('n', 'noun'), ('v', 'verb'), ('vt', 'verb'), ('vi', 'verb'), ('adj', 'adjective'),
    ('adv', 'adverb'), ('pron', 'pronoun'), ('prep', 'preposition'), ('conj', 'conjunction'),
    ('int', 'interjection'), ('interj', 'interjection'), ('det', 'determiner'),
    ('art', 'determiner'), ('num', 'numeral'), ('aux', 'auxiliary'), ('phr', 'phrase')
),
-- The alternation of every label, longest first, so 조동 is tried before 조.
alternation as (
  select string_agg(label, '|' order by length(label) desc, label) as labels from labels
),
-- Each form's pattern: the label, then the meaning, which must hold more than space.
forms (form, pattern, rank) as (
  select form, replace(pattern, 'L', alternation.labels), rank
  from alternation, (values
    ('bracket', '^\[(L)\.?\]\s*(\S.*)$', 1),
    ('paren', '^\((L)\.?\)\s*(\S.*)$', 2),
    ('dot', '^(L)\.\s*(\S.*)$', 3),
    ('bare', '^(L)\s+(\S.*)$', 4)
  ) as f (form, pattern, rank)
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
-- Each line's first matching form, in rank order, with its label and meaning.
matched as (
  select distinct on (lines.id, lines.number)
    lines.id, lines.number, lines.text, forms.form,
    (regexp_match(lines.text, forms.pattern, 'i'))[1] as label,
    (regexp_match(lines.text, forms.pattern, 'i'))[2] as meaning
  from lines
  left join forms on lines.text ~* forms.pattern
  order by lines.id, lines.number, forms.rank
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
  select * from cards where lines > 0 and recognised = lines
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
      'category', labels.category, 'meaning', matched.meaning
    ) order by matched.id, matched.number), '[]')
    from matched
    join convertible on convertible.id = matched.id
    join labels on labels.label = lower(matched.label)
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
