-- Whether an extraction's last reply was cut off at the output cap (#519, ADR 0135), so that only the
-- cards its JSON completed were read. Additive: one nullable column, every existing row keeping null,
-- and finish_extraction replaced by one taking it as a last argument that defaults to null, so a
-- function deployed before this change still records its outcomes.

alter table private.extraction_calls
  add column truncated boolean,
  -- A cut reply ends as cards kept from it, or as invalid output when it completed none.
  add constraint extraction_calls_truncated check (
    truncated is null
    or (outcome is not null and (not truncated or outcome in ('ok', 'invalid_output')))
  );

drop function public.finish_extraction(bigint, text, integer, integer, integer, integer, text[]);

-- Records how the extraction begun as [usage_id] ended, once, with whether its last reply was cut
-- off at the output cap. Raises P0002 when that call has no record or already has an outcome, and
-- 23514 when the outcome's parts disagree.
create function public.finish_extraction(
  usage_id bigint,
  outcome text,
  attempts integer,
  latency_ms integer,
  cards_returned integer,
  cards_dropped integer,
  failures text[],
  truncated boolean default null
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
    failures = finish_extraction.failures,
    truncated = finish_extraction.truncated
  where c.usage_id = finish_extraction.usage_id and c.outcome is null;
  if not found then
    raise exception 'no unfinished extraction call %', finish_extraction.usage_id
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.finish_extraction(bigint, text, integer, integer, integer, integer, text[], boolean)
  from public, anon, authenticated;
grant execute on function public.finish_extraction(bigint, text, integer, integer, integer, integer, text[], boolean)
  to service_role;
