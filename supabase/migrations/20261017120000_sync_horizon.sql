-- The revision horizon and the pull watermark a sync run reads first (ADR 0034 §3, ADR 0041).
-- Additive: it creates one table holding a horizon of 0 and one function, and changes no row.

-- The revision at or below which tombstones may have been purged. One row; 0 until a purge
-- stores the mark it purged below.
create table private.sync_horizon (
  id boolean primary key default true check (id),
  revision bigint not null check (revision >= 0)
);

insert into private.sync_horizon (revision) values (0);

-- The horizon, and a watermark: the sequence's last value, read under the caller's revision
-- lock. The lock waits for the caller's writing transactions, each of which draws its revision
-- while holding it, so every revision of the caller's rows at or below the watermark is committed
-- when it is read, and every later one is above it. A pull that starts after this call and
-- completes has therefore returned every row of the caller's at or below the watermark.
create function public.sync_horizon() returns table (horizon bigint, watermark bigint)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended((select auth.uid())::text, 0));
  return query
    select h.revision,
      (select case when s.is_called then s.last_value else 0 end from private.revision as s)
    from private.sync_horizon as h;
end;
$$;

revoke all on function public.sync_horizon() from public, anon;
grant execute on function public.sync_horizon() to authenticated;
