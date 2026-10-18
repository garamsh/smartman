-- The daily tombstone purge past a 90-day revision horizon (ADR 0034 §3, step 6 of §9; ADR 0053).
-- It enables pg_cron when it is not on yet, and refuses, changing nothing, unless pg_cron is
-- available and preloaded, the horizon still holds its one row at 0 and no purge job exists. It
-- deletes nothing itself: the job's first purge comes 90 days after its first mark.

-- Raises, naming what failed, unless the purge can start: pg_cron available and preloaded, the
-- horizon's one row at 0, so no purge has run, and no job named purge-tombstones.
create function private.check_purge_start() returns void
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select from pg_catalog.pg_available_extensions where name = 'pg_cron')
    or not 'pg_cron' = any (pg_catalog.string_to_array(
      pg_catalog.replace(pg_catalog.current_setting('shared_preload_libraries'), ' ', ''), ','))
  then
    raise exception 'the tombstone purge needs pg_cron, which this database does not offer: '
      'it is not in pg_available_extensions or not in shared_preload_libraries; nothing was changed';
  end if;
  if (select count(*) from private.sync_horizon where revision = 0) <> 1
    or exists (select from private.sync_horizon where revision <> 0)
  then
    raise exception 'the tombstone purge needs private.sync_horizon to hold its one row at 0, '
      'so that no purge has run; it holds %; nothing was changed',
      (select coalesce(pg_catalog.string_agg(revision::text, ', '), 'no row')
        from private.sync_horizon);
  end if;
  -- Planned only once cron.job exists, so a database without pg_cron reaches no missing table.
  if pg_catalog.to_regclass('cron.job') is not null then
    if exists (select from cron.job where jobname = 'purge-tombstones') then
      raise exception 'a cron job named purge-tombstones already exists; nothing was changed';
    end if;
  end if;
end;
$$;

revoke all on function private.check_purge_start() from public, anon, authenticated;

select private.check_purge_start();

-- Supabase Cron is pg_cron, created in pg_catalog as Supabase's Cron quickstart does; a no-op
-- where the project's owner enabled it first.
create extension if not exists pg_cron with schema pg_catalog;

-- The revision sequence's last value, taken once a day by the purge. A mark taken 90 days or more
-- before a run decides what that run purges.
create table private.revision_marks (
  taken_at timestamptz primary key,
  revision bigint not null check (revision >= 0)
);

-- Takes today's mark, trims cron.job_run_details past 30 days, and purges below the latest mark
-- taken 90 days or more ago, storing it as the horizon: card state tombstones are deleted; card
-- tombstones no review references are deleted, and the rest stripped of their content; deck
-- tombstones no card references are deleted, and the rest stripped and made private. A stripped
-- row takes a new revision, so devices pull the strip. Marks older than the horizon's go.
create function private.purge_tombstones() returns void
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

  delete from public.card_states
    where deleted_at is not null and revision <= mark.revision;
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

revoke all on function private.purge_tombstones() from public, anon, authenticated;

-- 18:00 UTC, 03:00 in Korea; pg_cron reads the schedule in GMT.
select cron.schedule('purge-tombstones', '0 18 * * *', 'select private.purge_tombstones()');
