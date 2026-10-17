-- The study days a day's new cards are read from, in one request (ADR 0043). Additive: it creates
-- one function and changes no row.

-- The caller's latest `days` study days before `before`, oldest first, each from 04:00 to 04:00 in
-- time_zone, as web/src/features/study/queue.ts counts them, with the time and number of the
-- answers that were not their card's first live answer and of those that were, each answer counted
-- up to cap_ms. It walks back one study day at a time, each step one backward probe of
-- reviews_live_user_id_reviewed_at, then reads the window's answers through the same index; whether
-- an answer is its card's first is one probe of reviews_user_id_card_id. A day without an answer is
-- no study day, so it is neither returned nor counted. It runs as the caller, so row-level security
-- decides what it reads, and a zone Postgres does not know raises.
create function public.study_days_before(
  time_zone text, before timestamptz, days integer, cap_ms integer
) returns table (
  day_start timestamptz, review_ms bigint, reviews integer, first_ms bigint, first_answers integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive walk (step, day_start) as (
    select 1, (
      select (date_trunc('day', (max(r.reviewed_at) at time zone study_days_before.time_zone)
          - interval '4 hours') + interval '4 hours') at time zone study_days_before.time_zone
      from public.reviews as r
      where r.user_id = (select auth.uid()) and r.deleted_at is null
        and r.reviewed_at < study_days_before.before
    )
    union all
    select w.step + 1, (
      select (date_trunc('day', (max(r.reviewed_at) at time zone study_days_before.time_zone)
          - interval '4 hours') + interval '4 hours') at time zone study_days_before.time_zone
      from public.reviews as r
      where r.user_id = (select auth.uid()) and r.deleted_at is null
        and r.reviewed_at < w.day_start
    )
    from walk as w
    where w.step < study_days_before.days and w.day_start is not null
  ),
  answers as (
    select
      (date_trunc('day', (r.reviewed_at at time zone study_days_before.time_zone)
        - interval '4 hours') + interval '4 hours') at time zone study_days_before.time_zone
        as day_start,
      least(r.duration_ms, study_days_before.cap_ms) as ms,
      not exists (
        select 1 from public.reviews as e
        where e.user_id = r.user_id and e.card_id = r.card_id and e.deleted_at is null
          and e.reviewed_at < r.reviewed_at
      ) as first
    from public.reviews as r
    where r.user_id = (select auth.uid()) and r.deleted_at is null
      and r.reviewed_at >= (select min(w.day_start) from walk as w)
      and r.reviewed_at < study_days_before.before
  )
  select
    a.day_start,
    coalesce(sum(a.ms) filter (where not a.first), 0)::bigint,
    (count(*) filter (where not a.first))::integer,
    coalesce(sum(a.ms) filter (where a.first), 0)::bigint,
    (count(*) filter (where a.first))::integer
  from answers as a
  group by a.day_start
  order by a.day_start
$$;

revoke all on function public.study_days_before(text, timestamptz, integer, integer)
  from public, anon;
grant execute on function public.study_days_before(text, timestamptz, integer, integer)
  to authenticated;
