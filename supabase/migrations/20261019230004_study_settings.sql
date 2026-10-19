-- The daily study minutes each user sets, which new cards fill (#271, ADR 0085), synced between
-- the phone and the web. Additive: it creates one table and one function, and changes no row; a
-- user without a row studies the default, 20 minutes.

-- A user's study settings: the daily minutes and when they were last set, on whichever client.
create table public.study_settings (
  user_id uuid primary key references auth.users on delete cascade,
  daily_minutes integer not null check (daily_minutes between 5 and 180),
  updated_at timestamptz not null
);

alter table public.study_settings enable row level security;

-- A user reads its own row; writes go through save_study_settings alone, which keeps the later.
revoke all on public.study_settings from anon, authenticated;
grant select on public.study_settings to authenticated;
create policy study_settings_select on public.study_settings for select to authenticated
  using ((select auth.uid()) = user_id);

-- Stores the caller's [daily_minutes], set at [updated_at], where the stored row is older or
-- absent, and answers whether it did: the later edit wins, as a review's rating does.
create function public.save_study_settings(daily_minutes integer, updated_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  written integer;
begin
  if (select auth.uid()) is null then
    raise exception 'a signed-in user is required' using errcode = '42501';
  end if;
  insert into public.study_settings as s (user_id, daily_minutes, updated_at)
    values ((select auth.uid()), save_study_settings.daily_minutes, save_study_settings.updated_at)
    on conflict (user_id) do update
      set daily_minutes = excluded.daily_minutes, updated_at = excluded.updated_at
      where s.updated_at < excluded.updated_at;
  get diagnostics written = row_count;
  return written > 0;
end;
$$;

revoke all on function public.save_study_settings(integer, timestamptz) from public, anon;
grant execute on function public.save_study_settings(integer, timestamptz) to authenticated;
