-- Stored vocabulary backs as senses blocks (#228, ADR 0075): every live card whose back is one text
-- block of sense lines, such as "[명] 사과", gets that back as one `senses` block, the shape the app
-- and the web draw. It changes existing data, which the owner approved for the 105 cards the dry
-- run found on production. Each original back is kept in a backup table no client can read, and
-- `private.revert_senses_migration()` restores it.
--
-- A card's revision is drawn anew by its update trigger, so every device pulls it; its
-- `updated_at` is left as it was, so a device edit not yet pushed, being later, wins the merge
-- and is pushed over this (sync.md). Its front, card key, review and card state are not touched.

-- The labels a sense line may start with, as a lower-case form, and the part of speech each names:
-- the short forms of ADR 0075 and the English abbreviations books print.
create function private.sense_labels() returns table (label text, category text)
language sql
immutable
set search_path = ''
as $$
  values
    ('명', 'noun'), ('동', 'verb'), ('형', 'adjective'), ('부', 'adverb'), ('대', 'pronoun'),
    ('전', 'preposition'), ('접', 'conjunction'), ('감', 'interjection'), ('관', 'determiner'),
    ('수', 'numeral'), ('조', 'particle'), ('조동', 'auxiliary'), ('양', 'classifier'),
    ('구', 'phrase'),
    ('n', 'noun'), ('v', 'verb'), ('vt', 'verb'), ('vi', 'verb'), ('adj', 'adjective'),
    ('adv', 'adverb'), ('pron', 'pronoun'), ('prep', 'preposition'), ('conj', 'conjunction'),
    ('int', 'interjection'), ('interj', 'interjection'), ('det', 'determiner'),
    ('art', 'determiner'), ('num', 'numeral'), ('aux', 'auxiliary'), ('phr', 'phrase');
$$;

-- The forms of a sense line, in the order they are tried, each pattern matching case-insensitively
-- a label, then the meaning, which holds more than space: in brackets, in parentheses, with a dot,
-- or bare and followed by a space. Every label is tried, longest first, so 조동 comes before 조.
create function private.sense_forms() returns table (form text, pattern text, rank integer)
language sql
immutable
set search_path = ''
as $$
  select f.form, replace(f.pattern, 'L', labels.alternation), f.rank
  from (
    select string_agg(l.label, '|' order by length(l.label) desc, l.label) as alternation
    from private.sense_labels() as l
  ) as labels,
  (values
    ('bracket', '^\[(L)\.?\]\s*(\S.*)$', 1),
    ('paren', '^\((L)\.?\)\s*(\S.*)$', 2),
    ('dot', '^(L)\.\s*(\S.*)$', 3),
    ('bare', '^(L)\s+(\S.*)$', 4)
  ) as f (form, pattern, rank);
$$;

-- [line], trimmed, as a sense line: the first form it matches, the label as printed, the part of
-- speech it names and the meaning; no row when it is not one.
create function private.sense_line(line text)
returns table (form text, label text, category text, meaning text)
language sql
immutable
set search_path = ''
as $$
  select f.form, r.m[1], l.category, r.m[2]
  from private.sense_forms() as f
  cross join lateral regexp_match(line, f.pattern, 'i') as r (m)
  join private.sense_labels() as l on l.label = lower(r.m[1])
  order by f.rank
  limit 1;
$$;

-- The senses block [back] becomes, or null when it does not convert. It converts only when it is
-- one text block whose every non-empty line, trimmed, is a sense line, so a note, free text or a
-- back mixing sense lines with other lines is never touched. Each line becomes one sense, in order,
-- its label a part of speech as printed and no example (ADR 0075).
create function private.senses_block(back jsonb) returns jsonb
language sql
immutable
set search_path = ''
as $$
  with lines as (
    select line.number, btrim(line.text) as text
    from regexp_split_to_table(back->0->'payload'->>'text', E'\r?\n') with ordinality
      as line (text, number)
    where jsonb_typeof(back) = 'array'
      and jsonb_array_length(back) = 1
      and back->0->>'type' = 'text'
      and jsonb_typeof(back->0->'payload'->'text') = 'string'
      and btrim(line.text) <> ''
  ),
  senses as (
    select lines.number, s.form, s.label, s.category, s.meaning
    from lines
    left join lateral private.sense_line(lines.text) as s on true
  )
  select jsonb_build_object('type', 'senses', 'payload', jsonb_build_object('senses',
    jsonb_agg(jsonb_build_object(
      'labels', jsonb_build_array(jsonb_build_object(
        'kind', 'part_of_speech', 'category', category, 'text', label)),
      'meaning', meaning,
      'examples', '[]'::jsonb
    ) order by number)))
  from senses
  having count(*) > 0 and count(form) = count(*);
$$;

-- Each converted card's back as it was before, the revert path. Readable by no client.
create table private.senses_migration_backup (
  card_id uuid primary key references public.cards (id) on delete cascade,
  back jsonb not null,
  migrated_at timestamptz not null default now()
);

alter table private.senses_migration_backup enable row level security;
revoke all on private.senses_migration_backup from public, anon, authenticated;

-- Converts every live card whose back converts, keeping its back in the backup first, and returns
-- how many it converted. A second run converts none: a senses block is not a text block. A card
-- converted before keeps its first backup.
create function private.migrate_senses() returns integer
language plpgsql
set search_path = ''
as $$
declare
  converted integer;
begin
  -- The rows are locked as they are read, so the back kept is the back replaced.
  with locked as (
    select c.id, c.back
    from public.cards as c
    where c.deleted_at is null and private.senses_block(c.back) is not null
    for update
  ),
  kept as (
    insert into private.senses_migration_backup (card_id, back)
    select locked.id, locked.back from locked
    on conflict (card_id) do nothing
  )
  update public.cards as c
  set back = jsonb_build_array(private.senses_block(locked.back))
  from locked
  where c.id = locked.id;
  get diagnostics converted = row_count;
  return converted;
end;
$$;

-- Restores each backed-up back on a live card still holding the block the migration wrote, and
-- returns how many it restored. A card edited since keeps its edit. Like the migration, it draws
-- new revisions and leaves `updated_at` as it was.
create function private.revert_senses_migration() returns integer
language plpgsql
set search_path = ''
as $$
declare
  restored integer;
begin
  update public.cards as c
  set back = b.back
  from private.senses_migration_backup as b
  where c.id = b.card_id
    and c.deleted_at is null
    and c.back = jsonb_build_array(private.senses_block(b.back));
  get diagnostics restored = row_count;
  return restored;
end;
$$;

revoke all on function private.sense_labels(), private.sense_forms(), private.sense_line(text),
  private.senses_block(jsonb), private.migrate_senses(), private.revert_senses_migration()
  from public, anon, authenticated;

select private.migrate_senses();
