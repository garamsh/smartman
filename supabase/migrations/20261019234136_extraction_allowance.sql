-- What the caller may still extract today, so the app can say so before reading several photos
-- (issue #272). Additive: it creates one read-only function and changes no row.

-- The caller's plan's daily limit and the photos counted against it since the start of the UTC
-- day: the plan begin_extraction resolves, through private.plan_of, and the rows it counts, so the
-- two agree. No row when the plan's settings are missing. Only the caller's own; it takes no user.
create function public.extraction_allowance()
returns table (daily_limit integer, used integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p.daily_limit,
    (select count(*) from public.extraction_usage as u
      where u.user_id = (select auth.uid())
        and u.created_at >= date_trunc('day', now(), 'UTC'))::integer
  from private.plans as p
  where p.id = private.plan_of((select auth.uid())) and (select auth.uid()) is not null
$$;

revoke all on function public.extraction_allowance() from public, anon;
grant execute on function public.extraction_allowance() to authenticated;
