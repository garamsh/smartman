-- Each extraction's outcome on its call record (#508, ADR 0130): how the request ended, its model
-- calls and how each failed, its latency and the cards answered and dropped, with no image, card or
-- prompt text. begin_extraction also returns the usage row it recorded, so extract-cards names it
-- to finish_extraction; two admin reads list the recent calls and each day's failures by prompt
-- version. Additive: six nullable columns, every existing row keeping null in each, begin_extraction
-- replaced with its body unchanged and one column more, and three new functions.

alter table private.extraction_calls
  add column outcome text
    check (outcome in ('ok', 'no_cards', 'invalid_output', 'model_error')),
  add column attempts smallint check (attempts in (1, 2)),
  add column latency_ms integer check (latency_ms >= 0),
  add column cards_returned integer check (cards_returned between 0 and 100),
  add column cards_dropped integer check (cards_dropped >= 0),
  -- The failure of each model call that failed, in order: one per attempt when the outcome is a
  -- failure, one fewer when the last attempt answered.
  add column failures text[]
    check (failures <@ array['invalid_output', 'model_error', 'timeout']::text[]),
  add constraint extraction_calls_outcome_whole check (
    (outcome is null and attempts is null and latency_ms is null and cards_returned is null
      and cards_dropped is null and failures is null)
    or (outcome is not null and attempts is not null and latency_ms is not null
      and cards_returned is not null and cards_dropped is not null and failures is not null
      and array_position(failures, null) is null
      and cardinality(failures) = attempts - (outcome in ('ok', 'no_cards'))::integer
      and (cards_returned > 0) = (outcome = 'ok')
      and (outcome <> 'no_cards' or cards_dropped = 0))
  );

-- Resolves [user_id]'s plan, its version and prompt, and, under the version's quota for its
-- period, records the photo with what serves it, under the extraction lock, returning the usage
-- row recorded, or null when the photo is refused. An admin is served the 'test' version when one
-- is set, everyone else the 'active' one. No row while the plan has no version or the active prompt
-- is missing.
drop function public.begin_extraction(uuid);
create function public.begin_extraction(user_id uuid)
returns table (
  plan text, model text, photo_limit integer, period text, allowed boolean,
  prompt_version_id bigint, prompt text, usage_id bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  entitled record;
  version private.prompt_versions;
  used bigint;
  usage bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(begin_extraction.user_id::text, 1));
  select * into entitled from private.entitlement_of(begin_extraction.user_id);
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
    where u.user_id = begin_extraction.user_id and u.created_at >= entitled.period_start;
  if used < entitled.amount then
    insert into public.extraction_usage (user_id) values (begin_extraction.user_id)
      returning id into usage;
    insert into private.extraction_calls (usage_id, plan, model, prompt_version_id)
      values (usage, entitled.plan, entitled.model, version.id);
  end if;
  return query select entitled.plan, entitled.model, entitled.amount,
    private.quota_period(entitled.quota), used < entitled.amount, version.id, version.text, usage;
end;
$$;

revoke all on function public.begin_extraction(uuid) from public, anon, authenticated;
grant execute on function public.begin_extraction(uuid) to service_role;

-- Records how the extraction begun as [usage_id] ended, once. Raises P0002 when that call has no
-- record or already has an outcome, and 23514 when the outcome's parts disagree.
create function public.finish_extraction(
  usage_id bigint,
  outcome text,
  attempts integer,
  latency_ms integer,
  cards_returned integer,
  cards_dropped integer,
  failures text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.extraction_calls as c
  set outcome = finish_extraction.outcome,
    attempts = finish_extraction.attempts,
    latency_ms = finish_extraction.latency_ms,
    cards_returned = finish_extraction.cards_returned,
    cards_dropped = finish_extraction.cards_dropped,
    failures = finish_extraction.failures
  where c.usage_id = finish_extraction.usage_id and c.outcome is null;
  if not found then
    raise exception 'no unfinished extraction call %', finish_extraction.usage_id
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.finish_extraction(bigint, text, integer, integer, integer, integer, text[])
  from public, anon, authenticated;
grant execute on function public.finish_extraction(bigint, text, integer, integer, integer, integer, text[])
  to service_role;

-- The recorded extraction calls, newest first, a page of [page_size] (1 to 500) before the usage id
-- [before]. A call without an outcome was counted before outcomes were recorded, or its request
-- ended unexpectedly.
create function public.admin_extraction_calls(before bigint default null, page_size integer default 100)
returns table (
  usage_id bigint,
  created_at timestamptz,
  user_id uuid,
  plan text,
  model text,
  prompt_version_id bigint,
  outcome text,
  attempts smallint,
  latency_ms integer,
  cards_returned integer,
  cards_dropped integer,
  failures text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select c.usage_id, u.created_at, u.user_id, c.plan, c.model, c.prompt_version_id, c.outcome,
    c.attempts, c.latency_ms, c.cards_returned, c.cards_dropped, c.failures
  from private.extraction_calls as c
  join public.extraction_usage as u on u.id = c.usage_id
  where admin_extraction_calls.before is null or c.usage_id < admin_extraction_calls.before
  order by c.usage_id desc
  limit least(greatest(admin_extraction_calls.page_size, 1), 500);
end;
$$;

revoke all on function public.admin_extraction_calls(bigint, integer) from public, anon;
grant execute on function public.admin_extraction_calls(bigint, integer) to authenticated;

-- Each UTC day's recorded calls over the last [days] days (1 to 90), today's included, by prompt
-- version: the calls with an outcome, each outcome's count, the calls retried and those a retry
-- answered, the share that failed, and the calls without an outcome beside them.
create function public.admin_extraction_failures(days integer default 30)
returns table (
  day date,
  prompt_version_id bigint,
  calls bigint,
  ok bigint,
  no_cards bigint,
  invalid_output bigint,
  model_error bigint,
  retried bigint,
  recovered bigint,
  failure_rate numeric,
  unrecorded bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select (u.created_at at time zone 'UTC')::date, c.prompt_version_id,
    count(c.outcome),
    count(*) filter (where c.outcome = 'ok'),
    count(*) filter (where c.outcome = 'no_cards'),
    count(*) filter (where c.outcome = 'invalid_output'),
    count(*) filter (where c.outcome = 'model_error'),
    count(*) filter (where c.attempts = 2),
    count(*) filter (where c.attempts = 2 and c.outcome in ('ok', 'no_cards')),
    round(count(*) filter (where c.outcome in ('invalid_output', 'model_error'))::numeric
      / nullif(count(c.outcome), 0), 4),
    count(*) filter (where c.outcome is null)
  from private.extraction_calls as c
  join public.extraction_usage as u on u.id = c.usage_id
  where u.created_at >= date_trunc('day', now(), 'UTC')
    - make_interval(days => least(greatest(admin_extraction_failures.days, 1), 90) - 1)
  group by 1, 2
  order by 1, 2;
end;
$$;

revoke all on function public.admin_extraction_failures(integer) from public, anon;
grant execute on function public.admin_extraction_failures(integer) to authenticated;
