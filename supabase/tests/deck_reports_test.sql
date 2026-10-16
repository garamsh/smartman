-- Reports: insert-only by their reporter, once per deck, and the third distinct reporter hides
-- the deck.
begin;
select plan(10);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com'),
  ('00000000-0000-4000-8000-00000000000c', 'c@example.com'),
  ('00000000-0000-4000-8000-00000000000d', 'd@example.com');
insert into public.decks
  (id, user_id, name, visibility, published_at, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000007a', '00000000-0000-4000-8000-00000000000a', 'French', 'public', now(), now(), now()),
  ('d0000000-0000-4000-8000-00000000008a', '00000000-0000-4000-8000-00000000000a', 'Diary', 'private', null, now(), now());

-- Files a report on A's public deck as the user whose id ends in [who].
create function pg_temp.report_as(who text, reason text) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    format('{"sub":"00000000-0000-4000-8000-00000000000%s","role":"authenticated"}', who), true);
  insert into public.deck_reports (deck_id, reason) values ('d0000000-0000-4000-8000-00000000007a', reason);
  perform set_config('role', 'none', true);
end;
$$;

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';

select lives_ok(
  $$insert into public.deck_reports (deck_id, reason) values ('d0000000-0000-4000-8000-00000000007a', 'spam')$$,
  'B reports A''s public deck');
select throws_ok(
  $$insert into public.deck_reports (deck_id, reason) values ('d0000000-0000-4000-8000-00000000007a', 'other')$$,
  '23505', null, 'B cannot report the same deck twice');
select throws_ok(
  $$insert into public.deck_reports (deck_id, reporter_id, reason)
    values ('d0000000-0000-4000-8000-00000000007a', '00000000-0000-4000-8000-00000000000c', 'spam')$$,
  '42501', null, 'B cannot report in C''s name');
select throws_ok(
  $$insert into public.deck_reports (deck_id, reason) values ('d0000000-0000-4000-8000-00000000008a', 'spam')$$,
  '42501', null, 'B cannot report a deck it cannot read');
select throws_ok(
  $$insert into public.deck_reports (deck_id, reason) values ('d0000000-0000-4000-8000-00000000007a', 'boring')$$,
  '23514', null, 'a reason outside the four is refused');
select throws_ok(
  $$select * from public.deck_reports$$,
  '42501', null, 'B cannot read reports back');

reset role;
select pg_temp.report_as('c', 'inappropriate');
reset role;
select results_eq(
  $$select hidden, (select count(*) from public.deck_reports) from public.decks where id = 'd0000000-0000-4000-8000-00000000007a'$$,
  $$values (false, 2::bigint)$$,
  'two distinct reports leave the deck visible');

select pg_temp.report_as('d', 'copyright');
reset role;
select results_eq(
  $$select hidden, (select count(*) from public.deck_reports) from public.decks where id = 'd0000000-0000-4000-8000-00000000007a'$$,
  $$values (true, 3::bigint)$$,
  'the third distinct report hides the deck');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select is_empty(
  $$select 1 from public.decks where id = 'd0000000-0000-4000-8000-00000000007a'$$,
  'the hidden deck is no longer readable by another user');

reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';
select results_eq(
  $$select id, hidden from public.decks where id = 'd0000000-0000-4000-8000-00000000007a'$$,
  $$values ('d0000000-0000-4000-8000-00000000007a'::uuid, true)$$,
  'the owner still reads its hidden deck, and sees that it is hidden');

select * from finish();
rollback;
