-- The daily extraction count behind the extract-cards function's rate limit: one row per
-- extraction the function let through to the model. Users read their own rows; only the
-- function, as service_role, writes them, through public.consume_extraction.

create table public.extraction_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now()
);

-- The count per user and day reads this index.
create index extraction_usage_user_id_created_at on public.extraction_usage (user_id, created_at);

-- Records one extraction for the user and returns true, or returns false and records nothing
-- when the user already has daily_limit rows since the start of the current UTC day. The
-- lock, held until commit, makes one user's count and insert atomic against a concurrent
-- request. Its key is seeded with 1, so it is never the revision trigger's lock on the same user.
create function public.consume_extraction(user_id uuid, daily_limit integer) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(consume_extraction.user_id::text, 1));
  if (
    select count(*) from public.extraction_usage as u
    where u.user_id = consume_extraction.user_id
      and u.created_at >= date_trunc('day', now(), 'UTC')
  ) >= daily_limit then
    return false;
  end if;
  insert into public.extraction_usage (user_id) values (consume_extraction.user_id);
  return true;
end;
$$;

-- Privileges are granted here rather than left to the project's default privileges: anon gets
-- nothing, authenticated may only read, and only service_role may record an extraction.
revoke all on public.extraction_usage from anon, authenticated, service_role;
grant select on public.extraction_usage to authenticated;
grant select on public.extraction_usage to service_role;
revoke all on function public.consume_extraction(uuid, integer) from public, anon, authenticated;
grant execute on function public.consume_extraction(uuid, integer) to service_role;

alter table public.extraction_usage enable row level security;

create policy extraction_usage_select on public.extraction_usage for select to authenticated
  using ((select auth.uid()) = user_id);
