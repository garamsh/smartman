-- Reading a photo to the end of its page (#535, ADR 0138): extract-cards reads a cut reply on, and a
-- client goes on in a later request with a cursor, the photo counted once. Additive: two nullable
-- counts on the call record, a photo's cards allowed up to 500, a table of the cursors not yet taken,
-- finish_extraction replaced by one taking the continuing calls and the cursor as last arguments that
-- default to null, so a function deployed before this change still records, and two new functions.
-- The record still holds no image, card or prompt text.

alter table private.extraction_calls
  -- The calls that read on after a cut reply, over every request, and the requests that went on with
  -- a cursor; null on rows recorded before this change or by a function that does not send them.
  add column continuations integer check (continuations >= 0),
  add column resumes integer check (resumes >= 0),
  drop constraint extraction_calls_cards_returned_check,
  add constraint extraction_calls_cards_returned_check check (cards_returned between 0 and 500);

-- A cursor not yet taken: the one later request that may go on reading the photo of [usage_id], until
-- [expires_at]. Taking it deletes it, so it cannot be taken twice, and a new one replaces it.
create table private.extraction_cursors (
  token uuid primary key,
  usage_id bigint not null unique references private.extraction_calls on delete cascade,
  expires_at timestamptz not null
);

alter table private.extraction_cursors enable row level security;
revoke all on private.extraction_cursors from public, anon, authenticated, service_role;

drop function public.finish_extraction(bigint, text, integer, integer, integer, integer, text[], boolean);

-- Records how the extraction begun as [usage_id] ended, once, with whether its page was left unread
-- past the cards answered, its continuing calls, and the [cursor] a later request may go on with for
-- ten minutes. Raises P0002 when that call has no record or already has an outcome, and 23514 when
-- the outcome's parts disagree.
create function public.finish_extraction(
  usage_id bigint,
  outcome text,
  attempts integer,
  latency_ms integer,
  cards_returned integer,
  cards_dropped integer,
  failures text[],
  truncated boolean default null,
  continuations integer default null,
  cursor uuid default null
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
    truncated = finish_extraction.truncated,
    continuations = finish_extraction.continuations
  where c.usage_id = finish_extraction.usage_id and c.outcome is null;
  if not found then
    raise exception 'no unfinished extraction call %', finish_extraction.usage_id
      using errcode = 'P0002';
  end if;
  if finish_extraction.cursor is not null then
    insert into private.extraction_cursors (token, usage_id, expires_at)
      values (finish_extraction.cursor, finish_extraction.usage_id, now() + interval '10 minutes')
      on conflict on constraint extraction_cursors_usage_id_key do update set token = excluded.token, expires_at = excluded.expires_at;
  end if;
end;
$$;

revoke all on function public.finish_extraction(bigint, text, integer, integer, integer, integer, text[], boolean, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.finish_extraction(bigint, text, integer, integer, integer, integer, text[], boolean, integer, uuid)
  to service_role;

-- Takes [cursor] for [user_id]: deletes it and returns the photo it goes on with, its usage row, the
-- plan, model, prompt version and prompt text of its first read, and the cards and continuing calls
-- it has had. No row when the cursor is unknown, already taken, expired or another user's.
create function public.resume_extraction(user_id uuid, cursor uuid)
returns table (
  usage_id bigint, plan text, model text, prompt_version_id bigint, prompt text,
  cards_read integer, continuations integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  taken bigint;
begin
  delete from private.extraction_cursors as k
  using public.extraction_usage as u
  where k.token = resume_extraction.cursor and k.expires_at > now()
    and u.id = k.usage_id and u.user_id = resume_extraction.user_id
  returning k.usage_id into taken;
  if taken is null then
    return;
  end if;
  return query
  select c.usage_id, c.plan, c.model, c.prompt_version_id, v.text, c.cards_returned,
    coalesce(c.continuations, 0)
  from private.extraction_calls as c
  join private.prompt_versions as v on v.id = c.prompt_version_id
  where c.usage_id = taken;
end;
$$;

revoke all on function public.resume_extraction(uuid, uuid) from public, anon, authenticated;
grant execute on function public.resume_extraction(uuid, uuid) to service_role;

-- Adds a request that went on with a cursor to the record of [usage_id]: its continuing calls and
-- cards, whether the page is still unread past them, and the next [cursor], if any, for ten minutes.
-- Raises P0002 when that call has no outcome yet, and 23514 when the photo passes 500 cards.
create function public.record_resumed_extraction(
  usage_id bigint,
  continuations integer,
  cards_returned integer,
  truncated boolean,
  cursor uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.extraction_calls as c
  set continuations = coalesce(c.continuations, 0) + record_resumed_extraction.continuations,
    resumes = coalesce(c.resumes, 0) + 1,
    cards_returned = c.cards_returned + record_resumed_extraction.cards_returned,
    truncated = record_resumed_extraction.truncated
  where c.usage_id = record_resumed_extraction.usage_id and c.outcome is not null;
  if not found then
    raise exception 'no finished extraction call %', record_resumed_extraction.usage_id
      using errcode = 'P0002';
  end if;
  if record_resumed_extraction.cursor is not null then
    insert into private.extraction_cursors (token, usage_id, expires_at)
      values (record_resumed_extraction.cursor, record_resumed_extraction.usage_id,
        now() + interval '10 minutes')
      on conflict on constraint extraction_cursors_usage_id_key do update set token = excluded.token, expires_at = excluded.expires_at;
  end if;
end;
$$;

revoke all on function public.record_resumed_extraction(bigint, integer, integer, boolean, uuid)
  from public, anon, authenticated;
grant execute on function public.record_resumed_extraction(bigint, integer, integer, boolean, uuid)
  to service_role;
