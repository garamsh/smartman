-- Checks and policies (ADR 0034 §5 and §7, step 3 of §9): five row checks, and one select policy per
-- table in place of each owner and public pair, the owner's condition first. It changes no row.

-- Every existing row must already pass the checks, so the migration raises, changing nothing, while
-- any row fails one, naming each check and how many rows fail it.
do $$
declare
  failing text;
begin
  select string_agg(format('%s (%s)', name, n), ', ') into failing
  from (
    select 'decks_name_check' as name, count(*) as n from public.decks
      where not (deleted_at is not null or name <> '')
    union all select 'cards_card_key_check', count(*) from public.cards
      where not (deleted_at is not null or card_key <> '')
    union all select 'card_states_stability_check', count(*) from public.card_states
      where not (stability >= 0.001)
    union all select 'card_states_difficulty_check', count(*) from public.card_states
      where not (difficulty between 1 and 10)
    union all select 'cards_origin_deck_id_check', count(*) from public.cards
      where not ((source = 'shared') = (origin_deck_id is not null))
  ) as counts
  where n > 0;
  if failing is not null then
    raise exception 'rows fail the checks: %', failing using errcode = '23514';
  end if;
end;
$$;

-- A tombstone may lose its name or card key, as the purge strips it (ADR 0034 §3). The stability and
-- difficulty bounds are the engine's clamps.
alter table public.decks add constraint decks_name_check
  check (deleted_at is not null or name <> '') not valid;
alter table public.cards add constraint cards_card_key_check
  check (deleted_at is not null or card_key <> '') not valid;
alter table public.card_states add constraint card_states_stability_check
  check (stability >= 0.001) not valid;
alter table public.card_states add constraint card_states_difficulty_check
  check (difficulty between 1 and 10) not valid;
alter table public.cards add constraint cards_origin_deck_id_check
  check ((source = 'shared') = (origin_deck_id is not null)) not valid;

-- Within this one transaction the lock the additions took is held to commit, so validating here does
-- not spare it; a table large enough for that to matter is validated in a later migration.
alter table public.decks validate constraint decks_name_check;
alter table public.cards validate constraint cards_card_key_check;
alter table public.card_states validate constraint card_states_stability_check;
alter table public.card_states validate constraint card_states_difficulty_check;
alter table public.cards validate constraint cards_origin_deck_id_check;

-- One select policy per table. Policies of one command already combined with or, so no row changes
-- visibility. The owner's condition comes first, so a read of one's own rows skips the public rule's
-- subquery.
drop policy decks_select on public.decks;
drop policy decks_select_public on public.decks;
create policy decks_select on public.decks for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (visibility = 'public' and not hidden and deleted_at is null)
  );

drop policy cards_select on public.cards;
drop policy cards_select_public on public.cards;
create policy cards_select on public.cards for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (
      deleted_at is null
      and exists (
        select 1 from public.decks as d
        where d.user_id = cards.user_id and d.id = cards.deck_id
          and d.visibility = 'public' and not d.hidden and d.deleted_at is null
      )
    )
  );

drop policy profiles_select on public.profiles;
drop policy profiles_select_public on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1 from public.decks as d
      where d.user_id = profiles.user_id
        and d.visibility = 'public' and not d.hidden and d.deleted_at is null
    )
  );
