-- The study day's start hour, held once on the server so its three study-day functions read it
-- from one place, and web/src/features/study/__tests__/rules.test.ts compares it with queue.ts's
-- studyDayStartHour (issue #220). Additive: it creates one function, replaces three with the same
-- results at 04:00, and changes no row.

-- The hour a study day starts at, local time, as web/src/features/study/queue.ts and
-- app/lib/study/src/queue.dart declare studyDayStartHour.
create function public.study_day_start_hour() returns integer
language sql
immutable
security invoker
set search_path = ''
as $$
  select 4
$$;

revoke all on function public.study_day_start_hour() from public, anon;
grant execute on function public.study_day_start_hour() to authenticated;

-- study_streak_before as 20261017090000_study_streak.sql defined it, with each study day starting
-- at study_day_start_hour() in place of the literal 04:00.
create or replace function public.study_streak_before(time_zone text, before timestamptz)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive days (day_start, streak) as (
    select (date_trunc('day', (study_streak_before.before at time zone study_streak_before.time_zone)
        - make_interval(hours => public.study_day_start_hour()))
        + make_interval(hours => public.study_day_start_hour()) - interval '1 day')
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

-- study_days_before as 20261018090000_study_days.sql defined it, with each study day starting at
-- study_day_start_hour() in place of the literal 04:00.
create or replace function public.study_days_before(
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
          - make_interval(hours => public.study_day_start_hour()))
          + make_interval(hours => public.study_day_start_hour()))
            at time zone study_days_before.time_zone
      from public.reviews as r
      where r.user_id = (select auth.uid()) and r.deleted_at is null
        and r.reviewed_at < study_days_before.before
    )
    union all
    select w.step + 1, (
      select (date_trunc('day', (max(r.reviewed_at) at time zone study_days_before.time_zone)
          - make_interval(hours => public.study_day_start_hour()))
          + make_interval(hours => public.study_day_start_hour()))
            at time zone study_days_before.time_zone
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
        - make_interval(hours => public.study_day_start_hour()))
        + make_interval(hours => public.study_day_start_hour()))
          at time zone study_days_before.time_zone
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

-- study_record_days as 20261018090001_study_record.sql defined it, with each study day starting at
-- study_day_start_hour() in place of the literal 04:00.
create or replace function public.study_record_days(time_zone text, before timestamptz)
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
        - make_interval(hours => public.study_day_start_hour()))
        + make_interval(hours => public.study_day_start_hour()))
          at time zone study_record_days.time_zone
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
