-- The overview's usage charts (#234, ADR 0074): the photos extract-cards counted per UTC day over
-- the last [days] days, today's included, by the plan, model and prompt version that served them.
-- A photo counted before the prompt store recorded calls has no plan, model or version. Additive:
-- one read-only function, checking the role as every admin read does.
create function public.admin_extraction_breakdown(days integer default 30)
returns table (day date, plan text, model text, prompt_version_id bigint, photos bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
  select (u.created_at at time zone 'UTC')::date, c.plan, c.model, c.prompt_version_id, count(*)
  from public.extraction_usage as u
  left join private.extraction_calls as c on c.usage_id = u.id
  where u.created_at >= date_trunc('day', now(), 'UTC')
    - make_interval(days => least(greatest(admin_extraction_breakdown.days, 1), 90) - 1)
  group by 1, 2, 3, 4
  order by 1, 2, 3, 4;
end;
$$;

revoke all on function public.admin_extraction_breakdown(integer) from public, anon;
grant execute on function public.admin_extraction_breakdown(integer) to authenticated;
