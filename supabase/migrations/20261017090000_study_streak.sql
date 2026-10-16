-- The streak in one request (ADR 0034 §4, step 7 of §9). Additive: it creates one function and
-- changes no row.

-- How many study days in a row before the one holding before hold one of the caller's answers,
-- with days from 04:00 to 04:00 in time_zone, as web/src/features/study/queue.ts counts them. It
-- walks back one day at a time, local 04:00 to local 04:00 so that a day across a change of offset
-- keeps both ends, and each day's latest answer is one backward probe of
-- reviews_live_user_id_reviewed_at; it stops at the first day without one. It runs as the caller,
-- so row-level security decides what it reads, and a zone Postgres does not know raises.
create function public.study_streak_before(time_zone text, before timestamptz) returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive days (day_start, streak) as (
    select (date_trunc('day', (study_streak_before.before at time zone study_streak_before.time_zone)
        - interval '4 hours') + interval '4 hours' - interval '1 day')
        at time zone study_streak_before.time_zone,
      0
    union all
    select ((d.day_start at time zone study_streak_before.time_zone) - interval '1 day')
        at time zone study_streak_before.time_zone,
      d.streak + 1
    from days as d
    where (
      select max(r.reviewed_at) from public.reviews as r
      where r.user_id = (select auth.uid()) and r.deleted_at is null
        and r.reviewed_at < ((d.day_start at time zone study_streak_before.time_zone) + interval '1 day')
          at time zone study_streak_before.time_zone
    ) >= d.day_start
  )
  select max(streak) from days
$$;

revoke all on function public.study_streak_before(text, timestamptz) from public, anon;
grant execute on function public.study_streak_before(text, timestamptz) to authenticated;
