-- Reviews and card states lose their deleted_at tombstone, which nothing writes (ADR 0077,
-- issue #219), with the policy, the index and the purge step built for it. Additive in effect: the
-- columns are dropped only once require_no_tombstone finds every value null, so no row changes.

-- Raises, changing nothing, while a row of [t] has deleted_at set: the column is dropped only
-- where that loses nothing. It reads t's column by name, so it applies to any synced table.
create function private.require_no_tombstone(t regclass) returns void
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  found boolean;
begin
  execute format('select exists (select from %s where deleted_at is not null)', t) into found;
  if found then
    raise exception '% holds a tombstone, which dropping deleted_at would lose', t
      using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function private.require_no_tombstone(regclass) from public, anon, authenticated;

select private.require_no_tombstone('public.reviews');
select private.require_no_tombstone('public.card_states');

-- A client could never delete a review; the policy for it goes.
drop policy reviews_delete on public.reviews;

-- The purge's index on card state tombstones, and the partial index on live reviews, whose term
-- names the column; every review was live, so the whole index holds the same rows.
drop index public.card_states_tombstone_revision;
drop index public.reviews_live_user_id_reviewed_at;

alter table public.reviews drop column deleted_at;
alter table public.card_states drop column deleted_at;

-- A user's reviews by time: the pace, a study day's reviews and the streak.
create index reviews_user_id_reviewed_at on public.reviews (user_id, reviewed_at);

-- study_streak_before as 20261019180001_study_day_start.sql defined it, without its
-- deleted_at filter.
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
      where r.user_id = (select auth.uid())
        and r.reviewed_at < ((d.day_start at time zone study_streak_before.time_zone) + interval '1 day')
          at time zone study_streak_before.time_zone
    ) >= d.day_start
  )
  select max(streak) from days
$$;

-- study_days_before as 20261019180001_study_day_start.sql defined it, without its
-- deleted_at filter.
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
      where r.user_id = (select auth.uid())
        and r.reviewed_at < study_days_before.before
    )
    union all
    select w.step + 1, (
      select (date_trunc('day', (max(r.reviewed_at) at time zone study_days_before.time_zone)
          - make_interval(hours => public.study_day_start_hour()))
          + make_interval(hours => public.study_day_start_hour()))
            at time zone study_days_before.time_zone
      from public.reviews as r
      where r.user_id = (select auth.uid())
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
        where e.user_id = r.user_id and e.card_id = r.card_id
          and e.reviewed_at < r.reviewed_at
      ) as first
    from public.reviews as r
    where r.user_id = (select auth.uid())
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

-- study_record_days as 20261019180001_study_day_start.sql defined it, without its
-- deleted_at filter.
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
    where r.user_id = (select auth.uid())
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

-- study_record_cards as 20261018090001_study_record.sql defined it, without its
-- review and state deleted_at filters.
create or replace function public.study_record_cards()
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
    on r.user_id = c.user_id and r.card_id = c.id
  left join public.card_states as s
    on s.user_id = c.user_id and s.card_id = c.id
  where c.user_id = (select auth.uid()) and c.deleted_at is null
  group by c.id, s.stability, s.difficulty, s.last_review, s.due
  order by c.id
$$;

-- admin_overview as 20261019120000_admin.sql defined it, without its
-- review deleted_at filters.
create or replace function public.admin_overview(today_start timestamptz, week_start timestamptz)
returns table (
  users bigint,
  new_users_7d bigint,
  new_users_30d bigint,
  studied_today bigint,
  studied_7d bigint,
  extractions_today bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select
    (select count(*) from auth.users as u where not u.is_anonymous),
    (select count(*) from auth.users as u
      where not u.is_anonymous and u.created_at >= now() - interval '7 days'),
    (select count(*) from auth.users as u
      where not u.is_anonymous and u.created_at >= now() - interval '30 days'),
    (select count(distinct r.user_id) from public.reviews as r
      where r.reviewed_at >= admin_overview.today_start),
    (select count(distinct r.user_id) from public.reviews as r
      where r.reviewed_at >= admin_overview.week_start),
    (select count(*) from public.extraction_usage as e
      where e.created_at >= date_trunc('day', now(), 'UTC'));
end;
$$;

-- admin_user as 20261019120000_admin.sql defined it, without its
-- review deleted_at filter.
create or replace function public.admin_user(user_id uuid)
returns table (
  id uuid,
  email text,
  created_at timestamptz,
  last_answer_at timestamptz,
  decks bigint,
  cards bigint,
  extractions_today bigint,
  admin boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select u.id, u.email::text, u.created_at,
    (select max(r.reviewed_at) from public.reviews as r
      where r.user_id = u.id),
    (select count(*) from public.decks as d where d.user_id = u.id and d.deleted_at is null),
    (select count(*) from public.cards as c
      join public.decks as d on d.user_id = c.user_id and d.id = c.deck_id and d.deleted_at is null
      where c.user_id = u.id and c.deleted_at is null),
    (select count(*) from public.extraction_usage as e
      where e.user_id = u.id and e.created_at >= date_trunc('day', now(), 'UTC')),
    exists (select from private.admins as a where a.user_id = u.id)
  from auth.users as u
  where u.id = admin_user.user_id;
end;
$$;

-- private.purge_tombstones as 20261018090002_tombstone_purge.sql defined it, without its
-- deletion of card state tombstones.
create or replace function private.purge_tombstones() returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  ran_at timestamptz := pg_catalog.clock_timestamp();
  mark private.revision_marks;
begin
  insert into private.revision_marks (taken_at, revision)
    select ran_at, case when s.is_called then s.last_value else 0 end from private.revision as s;
  delete from cron.job_run_details where end_time < ran_at - interval '30 days';

  select * into mark from private.revision_marks
    where taken_at <= ran_at - interval '90 days'
    order by taken_at desc
    limit 1;
  if mark is null then
    return;
  end if;

  -- Held to commit, so no card or review written meanwhile comes to reference a tombstone this
  -- deletes, which the cascade would take with it.
  lock table public.cards, public.reviews in share row exclusive mode;

  delete from public.cards as c
    where c.deleted_at is not null and c.revision <= mark.revision
      and not exists (
        select from public.reviews as r where r.user_id = c.user_id and r.card_id = c.id);
  update public.cards set front = '[]', back = '[]', card_key = ''
    where deleted_at is not null and revision <= mark.revision
      and (front <> '[]' or back <> '[]' or card_key <> '');
  delete from public.decks as d
    where d.deleted_at is not null and d.revision <= mark.revision
      and not exists (select from public.cards as c where c.deck_id = d.id);
  update public.decks set name = '', description = null, visibility = 'private'
    where deleted_at is not null and revision <= mark.revision
      and (name <> '' or description is not null or visibility <> 'private');

  update private.sync_horizon set revision = mark.revision where revision < mark.revision;
  delete from private.revision_marks where taken_at < mark.taken_at;
end;
$$;
