-- The reads the web's 기록 page computes ADR 0037's metrics from, in one request each (ADR 0047).
-- Additive: it creates two functions and changes no row.

-- One row per study day before `before` that holds one of the caller's live answers, oldest first,
-- each from 04:00 to 04:00 in time_zone, as web/src/features/study/queue.ts counts them: its
-- start, the distinct cards answered in it, its scheduled reviews and those answered "good". A
-- review is scheduled when it is a card's first answer of its study day and the card has an answer
-- on an earlier one, so a card's first answer ever and a re-show the same day are not (ADR 0037).
-- Every live answer counts, whether or not its card is still in a deck. It reads the caller's
-- answers through reviews_live_user_id_reviewed_at. It runs as the caller, so row-level security
-- decides what it reads, and a zone Postgres does not know raises.
create function public.study_record_days(time_zone text, before timestamptz)
returns table (day_start timestamptz, cards integer, reviews integer, known integer)
language sql
stable
security invoker
set search_path = ''
as $$
  with answers as (
    select
      r.card_id,
      r.rating,
      r.reviewed_at,
      r.id,
      (date_trunc('day', (r.reviewed_at at time zone study_record_days.time_zone)
        - interval '4 hours') + interval '4 hours') at time zone study_record_days.time_zone
        as day_start
    from public.reviews as r
    where r.user_id = (select auth.uid()) and r.deleted_at is null
      and r.reviewed_at < study_record_days.before
  ),
  ranked as (
    select
      a.*,
      row_number() over (partition by a.card_id, a.day_start order by a.reviewed_at, a.id)
        as nth,
      min(a.day_start) over (partition by a.card_id) as first_day
    from answers as a
  )
  select
    k.day_start,
    (count(distinct k.card_id))::integer,
    (count(*) filter (where k.nth = 1 and k.first_day < k.day_start))::integer,
    (count(*) filter (where k.nth = 1 and k.first_day < k.day_start and k.rating = 'good'))::integer
  from ranked as k
  group by k.day_start
  order by k.day_start
$$;

revoke all on function public.study_record_days(text, timestamptz) from public, anon;
grant execute on function public.study_record_days(text, timestamptz) to authenticated;

-- One row per live card of the caller, in a live deck, with at least one live answer: its stored
-- state, null without a live one, and its live answers' ratings, times and fuzz factors in the
-- order they were given, which the engine folds into the card's states over time (ADR 0037).
-- Answers are read through reviews_user_id_card_id per card; the cards are the whole library, as
-- the library read scans them. It runs as the caller, so row-level security decides what it reads.
create function public.study_record_cards()
returns table (
  card_id uuid,
  stability double precision,
  difficulty double precision,
  last_review timestamptz,
  due timestamptz,
  ratings text[],
  reviewed_at timestamptz[],
  fuzz_factors double precision[]
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    c.id,
    s.stability,
    s.difficulty,
    s.last_review,
    s.due,
    array_agg(r.rating order by r.reviewed_at, r.id),
    array_agg(r.reviewed_at order by r.reviewed_at, r.id),
    array_agg(r.fuzz_factor order by r.reviewed_at, r.id)
  from public.cards as c
  join public.decks as d
    on d.user_id = c.user_id and d.id = c.deck_id and d.deleted_at is null
  join public.reviews as r
    on r.user_id = c.user_id and r.card_id = c.id and r.deleted_at is null
  left join public.card_states as s
    on s.user_id = c.user_id and s.card_id = c.id and s.deleted_at is null
  where c.user_id = (select auth.uid()) and c.deleted_at is null
  group by c.id, s.stability, s.difficulty, s.last_review, s.due
  order by c.id
$$;

revoke all on function public.study_record_cards() from public, anon;
grant execute on function public.study_record_cards() to authenticated;
