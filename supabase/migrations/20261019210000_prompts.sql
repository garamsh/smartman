-- The prompt store (#234, ADR 0073): the model's instructions as append-only versions an admin
-- saves in the admin area, the version every user is served ('active') and the one admins are
-- served instead when one is set ('test'), and each extraction's record of the plan, model and
-- version that served it. The output contract, its schema and its parser, stays in the function.
-- Additive: it creates three tables in `private`, their indexes, a trigger and the functions, and
-- changes no existing row or object. The seed is the prompt the function served before it.

-- Every saved prompt: its text, a note, who saved it and when. Rows are never changed or removed.
create table private.prompt_versions (
  id bigint generated always as identity primary key,
  text text not null check (char_length(text) <= 20000 and text ~ '\S'),
  note text not null default '' check (char_length(note) <= 200),
  created_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

create index prompt_versions_created_by on private.prompt_versions (created_by);

-- Refuses any change to a version but its author's removal, which deleting that account sets.
create function private.keep_prompt_version() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.id = old.id and new.text = old.text and new.note = old.note
    and new.created_at = old.created_at and new.created_by is null
  then
    return new;
  end if;
  raise exception 'prompt versions are append-only' using errcode = '55000';
end;
$$;

create trigger prompt_versions_append_only before update or delete on private.prompt_versions
  for each row execute function private.keep_prompt_version();

-- Which version each label names: 'active' for every user, and 'test', when set, for admins.
create table private.prompt_labels (
  label text primary key check (label in ('active', 'test')),
  version_id bigint not null references private.prompt_versions,
  set_by uuid references auth.users on delete set null,
  set_at timestamptz not null default now()
);

create index prompt_labels_version_id on private.prompt_labels (version_id);
create index prompt_labels_set_by on private.prompt_labels (set_by);

-- What served each extraction: the plan, its model and the prompt version, with no image, card or
-- prompt text. It deletes with its usage row, and so with its user.
create table private.extraction_calls (
  usage_id bigint primary key references public.extraction_usage on delete cascade,
  plan text not null,
  model text not null,
  prompt_version_id bigint not null references private.prompt_versions
);

create index extraction_calls_prompt_version_id on private.extraction_calls (prompt_version_id);

alter table private.prompt_versions enable row level security;
alter table private.prompt_labels enable row level security;
alter table private.extraction_calls enable row level security;
revoke all on private.prompt_versions, private.prompt_labels, private.extraction_calls
  from public, anon, authenticated, service_role;

-- The seed: the function's prompt v8, `SYSTEM_PROMPT` in
-- supabase/functions/extract-cards/prompt_v8.ts, as version 1, active, so the deploy serves what
-- was served before. prompt_seed_test.ts compares the two.
insert into private.prompt_versions (text, note) values ($prompt$You turn one photo of a study page into flashcards for memorising what the page teaches, each card small enough to recall and grade at once.

The photo shows a printed or handwritten page: a vocabulary list, glossary, bilingual table or dictionary page, or notes such as lecture notes, a textbook summary or a study sheet. It may be rotated, skewed, blurred, or unevenly lit.

Every card has these fields:
- "kind" is "vocabulary" for an entry of a vocabulary list, glossary, bilingual table or dictionary page, and "note" for a point of notes.
- "type" is what the card asks:
  - "concept": the front names a term, concept, rule or exception, and the answer states it. Every vocabulary card is "concept", and so is a judgment card.
  - "cloze": the front is a line or sentence of the page with each word to recall replaced by a blank written "___", and "cloze" holds what fills each blank.
  - "identify": the front is an example sentence the page prints, with the word to judge marked in single quotes, and the answer is its category and the reason.
  - "table": a whole table of the page on one card, in "table", with the cells to recall as blanks.
- "front" is what the card is about, as a short keyword: for vocabulary, the term being learned, exactly as written; for notes, the name of the concept, rule or exception the card states, such as "광합성", "ㄷ 불규칙 (듣다)" or "opportunity cost". Write "'저희': 3인칭 재귀칭", not "대명사 '저희'의 쓰임 - 3인칭 재귀칭". It is a name, never a question: not "광합성이란?". A cloze or identify card's front is its line or sentence instead, and a table card's front is the table's name, such as "인칭 대명사".
- "answer" is a note's answer: the theory itself, the definition, rule or exception in one or a few sentences in the page's language, such as "빛 에너지로 이산화탄소와 물에서 포도당을 만드는 과정". It is null for every vocabulary card, whose meanings go in "senses", and for every cloze and table card, whose answers go in "cloze" and "table".
- "topic" is the name of the page section the card comes from, at most 60 characters: the heading it sits under, without its numbering, such as "축약" for a section headed "3. 축약". Cards of one section share one topic, written the same way. A page without headings gives every card its title, or, without a title, a short name for what the page lists.
- "senses" are a vocabulary entry's meanings, in the page's order, one per part of speech or numbered meaning the page prints, each {"labels": [...], "meaning": "...", "examples": [...]}, such as [{"labels": [{"kind": "part_of_speech", "category": "verb", "text": "동"}], "meaning": "직면하다, 마주하다", "examples": []}, {"labels": [{"kind": "other", "category": null, "text": "사물"}], "meaning": "철도 위를 다니는 긴 차", "examples": []}]. An entry with one meaning has one sense. It is an empty list for every note.
  - "labels" are the labels the page prints for that meaning, in the page's order, each transcribed, never inferred. A part of speech is {"kind": "part_of_speech", "category": <name>, "text": <as printed>}, its category one of: "noun", "verb", "adjective", "adverb", "pronoun", "preposition" (a postposition too), "conjunction", "interjection", "determiner" (an article too), "numeral", "particle", "auxiliary", "classifier", "phrase" (an idiom or set phrase). Any other label is {"kind": "other", "category": null, "text": <as printed>}: a semantic class such as [사물], a register such as [구어], a field such as [의학], or a part of speech not on that list. "text" is the label as printed, its dots kept, without the brackets or parentheses around it: "동" for "[동]", "n." for "n.", "명사" for "「명사」".
  - "labels" is an empty list when the page prints no label for the meaning, even when its part of speech is plain: never add a label the page does not print.
  - A label is one the page prints with that meaning, on the meaning's own line. A part of speech printed anywhere else is not a label of any sense, such as one before each reading of a pronunciation like "명 ['kantent] / 형 [kan'tent]": it stays in "pronunciation" alone, and the meanings it seems to match keep the labels printed on their own lines, or none.
  - "meaning" is the translation or the definition, exactly as written, without its labels or its number.
  - "examples" are the example sentences the page prints under that meaning, each copied character for character, at most 5, and an empty list when it prints none.
- "extras" are anything else the page prints for a vocabulary entry as a whole, rather than for one meaning, each with the page's own label verbatim, such as {"label": "유의어", "text": "confront"} for a synonym, an antonym or a derived word. The entry's grammar beyond its parts of speech goes here too, verbatim under the page's label, such as {"label": "성", "text": "der"} for a gender, a measure word, a verb class, a plural or an irregular form. It is an empty list when the page prints none, and for every note.
- "pronunciation" is the pronunciation, phonetic transcription or reading the page prints for a vocabulary entry, verbatim, such as "[ɪɡˈzæmpəl]", or "명 [kántent] / 형 [kəntént]" when the page prints one per part of speech. It is null when the page prints none, and for every note.
- "examples" are the example sentences, phrases or worked examples the page itself prints for the card, each copied character for character, at most 5. For a vocabulary entry, an example the page prints under one of its meanings goes in that sense's "examples" instead. It is an empty list when the page prints none for the card.
- "table" is a table card's table, as the page prints it: "columns" its column headers, left to right, the top-left corner included; "rows" its rows, top to bottom, each the row's cells left to right, starting with the row's header, every row as many cells as there are columns; and "blanks" the cells to recall, each {"row": r, "column": c} counted from 0 within "rows", never a header and never an empty cell. A header or cell the page leaves empty is "". It is null for every other card.
- "cloze" is a cloze card's blanks: {"answers": [...]}, what fills each "___" of its front, in order, one answer for each blank. It is null for every other card.

Rules:
- Every fact in an answer comes from the page. You may name a concept and join or shorten the page's words, but never add a fact, a meaning, a label, an extra, a pronunciation or an example the page does not show, even when you know it. A field the page does not print is null or empty.
- Examples come only from the page: copy one only when the page prints it for that card's entry or rule, whole and as printed, and never shorten, complete, extend, translate or make up an example to illustrate a rule, even a well-known one. Leave out an example you cannot read with confidence rather than guessing any of its characters. When you cannot see the page print an example for the card, leave "examples" empty.
- For vocabulary, copy the text as it appears. Do not translate, correct or complete it.
- For notes, cards hold the theory and the exceptions, so that a learner who studies every card has memorised what the page teaches, in the order of the page:
  - One card per fact: each fact gets exactly one card, never a second card that asks it again in another form. An answer that would list more than 5 items is split into several cards.
  - Every definition and every rule, each on its own card.
  - List lines are cloze cards: a line that names a group and then lists its members, such as "비음화: ㄱ+ㄴ, ㄷ+ㄴ, ㅂ+ㄴ" or "3인칭 재귀칭: 자기, 자신, 저, 저희", is recalled in context. It becomes one "cloze" card whose front is the whole line with each member written "___", such as "3인칭 재귀칭: ___, ___, ___, ___", with the members as its answers in order, never a "concept" card whose front is the group's name and whose answer is the list. A line of more than 5 members becomes several cloze cards of at most 5 blanks each, each front keeping the group's name.
  - Cloze only where no concept card states it: a sentence the learner recalls in context, which has no concept card of its own, also becomes one cloze card with a blank for each word to recall, such as the front "3인칭 재귀칭: 높임 당신 · 예사 ___ · 낮춤 ___" with the answers "자기, 자신" and "저, 저희". A cloze never asks what a concept or table card already answers.
  - Sub-points: every line written under a point, such as a member, a case, a condition or a variant of its rule, is covered by a card of its own or a blank of a cloze card, and never dropped or left only as an example. Its card names the rule it belongs to, such as "비음화: ㄱ+ㄴ → ㅇ+ㄴ" rather than "ㄱ+ㄴ → ㅇ+ㄴ", so it is understood alone.
  - Table cards: a table whose cells are to be memorised, such as a classification grid, becomes one "table" card holding the whole table, its front the table's name, its headers kept and the cells to recall as its blanks, such as the rows "2인칭 | 당신, 그대 | 너, 너희" under the columns "구분 | 높임 | 낮춤", with both cells of each row as blanks. A table is never split into a card per cell or per row.
  - Judgment cards: a rule that tells A from B gets its own card, its front "A vs B", such as "이·그·저: 대명사 vs 관형사", and its answer the test, such as "뒤에 조사 O → 대명사 / 조사 X, 명사 수식 → 관형사".
  - Handwriting first: every tip, trap or note the writer added by hand, and each line the writer marked as important, such as with a star, a circle, an underline, "※" or "!", becomes its own card, its front starting with "★ ", so that none is dropped.
  - Each exception, on its own card, its answer stating what the exception does, as the page prints it, such as "수은은 상온에서 액체인 금속이다", never only that it is an exception, such as "금속의 예외".
- A worked example, such as "6 x 7 = 42" or "듣+어 -> 들어", is a problem worked through, not something to memorise. It is never a concept, cloze or table card of its own: it goes in the examples of the card whose rule it illustrates, exactly as the page prints it, and only when the page prints it. Never write an example of your own.
- Identify cards: where the page prints example sentences for a rule that sorts words into categories, make an "identify" card from such a printed sentence, in the topic of its rule, at most 3 for each rule, such as the front "'이는 책이다'의 '이'" with the answer "대명사 — 뒤에 조사". Make one only from a sentence the page prints, never from one of your own.
- Do not merge separate rules into one card, and do not leave a rule or exception out because it seems minor.
- Do not make a card of a heading alone, a date, or the course name.
- Leave out numbering, bullets and page numbers, and in notes, pronunciation guides, phonetic transcriptions and readings.
- When a vocabulary page pairs Korean with another language and no language hint says otherwise, the other language is the front and Korean is the meaning.
- Skip what you cannot read with confidence rather than guessing it.
- If the photo shows nothing to memorise, return an empty list.

Answer with JSON only, matching the given schema: at most 100 cards, so when a page holds more, keep its definitions, rules, judgment cards, handwritten tips and marked exceptions before its table and cloze cards, and those before its identify cards, in the page's order; "answer" at most 1000 characters, "topic" at most 60, at most 10 senses, 5 labels and 5 examples a sense, 10 extras and 10 cloze answers, a table at most 8 columns and 20 rows, and every other text field at most 500.$prompt$, 'prompt v8');
insert into private.prompt_labels (label, version_id) values ('active', 1);

-- Resolves [user_id]'s plan and prompt, and, under the plan's daily limit, records the photo with
-- what serves it, under the extraction lock (`start_extraction`'s, which it replaces in the
-- function). An admin is served the 'test' version when one is set, everyone else the 'active'
-- one. No row when the plan's settings or the active version are missing.
create function public.begin_extraction(user_id uuid)
returns table (
  plan text, model text, daily_limit integer, allowed boolean, prompt_version_id bigint, prompt text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings private.plans;
  version private.prompt_versions;
  used bigint;
  usage bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(begin_extraction.user_id::text, 1));
  select * into settings from private.plans as p where p.id = private.plan_of(begin_extraction.user_id);
  if not found then
    return;
  end if;
  select v.* into version
  from private.prompt_labels as l
  join private.prompt_versions as v on v.id = l.version_id
  where l.label = 'active'
    or (l.label = 'test'
      and exists (select 1 from private.admins as a where a.user_id = begin_extraction.user_id))
  order by l.label = 'test' desc
  limit 1;
  if not found then
    return;
  end if;
  select count(*) into used from public.extraction_usage as u
    where u.user_id = begin_extraction.user_id
      and u.created_at >= date_trunc('day', now(), 'UTC');
  if used < settings.daily_limit then
    insert into public.extraction_usage (user_id) values (begin_extraction.user_id)
      returning id into usage;
    insert into private.extraction_calls (usage_id, plan, model, prompt_version_id)
      values (usage, settings.id, settings.model, version.id);
  end if;
  return query select settings.id, settings.model, settings.daily_limit,
    used < settings.daily_limit, version.id, version.text;
end;
$$;

revoke all on function public.begin_extraction(uuid) from public, anon, authenticated;
grant execute on function public.begin_extraction(uuid) to service_role;

-- [version_id]'s text and note, for the eval run by a version's id; no row for no version.
create function public.prompt_version(version_id bigint)
returns table (text text, note text)
language sql
stable
security definer
set search_path = ''
as $$
  select v.text, v.note from private.prompt_versions as v where v.id = prompt_version.version_id;
$$;

revoke all on function public.prompt_version(bigint) from public, anon, authenticated;
grant execute on function public.prompt_version(bigint) to service_role;

-- Every version, newest first, with its note, length, author, and the labels naming it.
create function public.admin_prompt_versions()
returns table (
  id bigint, note text, length integer, created_by_email text, created_at timestamptz,
  labels text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select v.id, v.note, char_length(v.text), u.email::text, v.created_at,
    coalesce((select array_agg(l.label order by l.label) from private.prompt_labels as l
      where l.version_id = v.id), '{}')
  from private.prompt_versions as v
  left join auth.users as u on u.id = v.created_by
  order by v.id desc;
end;
$$;

-- One version with its text and labels, and the active version's text beside it for the diff;
-- no row for no version.
create function public.admin_prompt_version(version_id bigint)
returns table (
  id bigint, text text, note text, created_by_email text, created_at timestamptz, labels text[],
  active_id bigint, active_text text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select v.id, v.text, v.note, u.email::text, v.created_at,
    coalesce((select array_agg(l.label order by l.label) from private.prompt_labels as l
      where l.version_id = v.id), '{}'),
    a.id, a.text
  from private.prompt_versions as v
  left join auth.users as u on u.id = v.created_by
  left join private.prompt_labels as al on al.label = 'active'
  left join private.prompt_versions as a on a.id = al.version_id
  where v.id = admin_prompt_version.version_id;
end;
$$;

-- Saves [text] with [note] as a new version and records it, returning its id. It labels nothing:
-- serving it is a separate action. The table's checks refuse an empty text, one over 20,000
-- characters and a note over 200.
create function public.admin_save_prompt(text text, note text) returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := private.require_admin();
  saved bigint;
begin
  insert into private.prompt_versions (text, note, created_by)
    values (admin_save_prompt.text, btrim(admin_save_prompt.note), caller)
    returning id into saved;
  perform private.audit('save_prompt', 'prompt', saved::text, jsonb_build_object(
    'note', btrim(admin_save_prompt.note), 'length', char_length(admin_save_prompt.text)));
  return saved;
end;
$$;

-- Points [label] at [version_id] and records it, returning true: 'active' serves the version to
-- every user, which is also how an earlier version is rolled back to, and 'test' serves it to
-- admins. Activating the test version clears the test label, so admins follow the active one.
-- False, recording nothing, when the label already names it; a version that does not exist is
-- refused by the reference.
create function public.admin_set_prompt_label(label text, version_id bigint) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := private.require_admin();
  previous bigint;
  cleared boolean := false;
begin
  if admin_set_prompt_label.label not in ('active', 'test') then
    raise exception 'no prompt label %', admin_set_prompt_label.label using errcode = '22023';
  end if;
  -- Label changes run one at a time under a lock seeded with 4, so two cannot read one previous.
  perform pg_advisory_xact_lock(hashtextextended('private.prompt_labels', 4));
  select l.version_id into previous from private.prompt_labels as l
    where l.label = admin_set_prompt_label.label;
  if previous is not distinct from admin_set_prompt_label.version_id then
    return false;
  end if;
  insert into private.prompt_labels (label, version_id, set_by)
    values (admin_set_prompt_label.label, admin_set_prompt_label.version_id, caller)
    on conflict on constraint prompt_labels_pkey do update
      set version_id = excluded.version_id, set_by = excluded.set_by, set_at = now();
  if admin_set_prompt_label.label = 'active' then
    delete from private.prompt_labels as l
      where l.label = 'test' and l.version_id = admin_set_prompt_label.version_id;
    cleared := found;
  end if;
  perform private.audit(
    case admin_set_prompt_label.label when 'active' then 'activate_prompt' else 'test_prompt' end,
    'prompt', admin_set_prompt_label.version_id::text,
    jsonb_build_object('previous', previous, 'test_cleared', cleared));
  return true;
end;
$$;

-- Clears the test label and records it, returning true, so admins are served the active version
-- again; false, recording nothing, when none is set.
create function public.admin_clear_test_prompt() returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  cleared bigint;
begin
  perform private.require_admin();
  perform pg_advisory_xact_lock(hashtextextended('private.prompt_labels', 4));
  delete from private.prompt_labels as l where l.label = 'test' returning l.version_id into cleared;
  if cleared is null then
    return false;
  end if;
  perform private.audit('clear_test_prompt', 'prompt', cleared::text, '{}'::jsonb);
  return true;
end;
$$;

revoke all on function public.admin_prompt_versions() from public, anon;
revoke all on function public.admin_prompt_version(bigint) from public, anon;
revoke all on function public.admin_save_prompt(text, text) from public, anon;
revoke all on function public.admin_set_prompt_label(text, bigint) from public, anon;
revoke all on function public.admin_clear_test_prompt() from public, anon;
grant execute on function public.admin_prompt_versions() to authenticated;
grant execute on function public.admin_prompt_version(bigint) to authenticated;
grant execute on function public.admin_save_prompt(text, text) to authenticated;
grant execute on function public.admin_set_prompt_label(text, bigint) to authenticated;
grant execute on function public.admin_clear_test_prompt() to authenticated;
