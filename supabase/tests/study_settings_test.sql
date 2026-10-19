-- The daily study minutes (ADR 0085): each user reads its own row only, writes it only through
-- save_study_settings, which keeps the later edit and the bounds, and the row deletes with the user.
begin;
select plan(13);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'b@example.com');

-- Signs in as the user whose id ends in [who], or as anon for null.
create function pg_temp.sign_in(who text) returns void language plpgsql as $$
begin
  if who is null then
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  else
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims',
      format('{"sub":"00000000-0000-4000-8000-00000000000%s","role":"authenticated"}', who), true);
  end if;
end;
$$;

select pg_temp.sign_in('a');
select ok(public.save_study_settings(30, '2026-10-19 10:00+00'), 'a user saves its daily minutes');
select results_eq($$select daily_minutes, updated_at from public.study_settings$$,
  $$values (30, '2026-10-19 10:00+00'::timestamptz)$$, 'and reads its own row back');
select is(public.save_study_settings(45, '2026-10-19 09:00+00'), false,
  'an older edit, from a device that set it earlier, changes nothing');
select is(public.save_study_settings(45, '2026-10-19 10:00+00'), false, 'and nor does an equal one');
select ok(public.save_study_settings(15, '2026-10-19 11:00+00'), 'a later edit replaces it');
select results_eq($$select daily_minutes from public.study_settings$$, $$values (15)$$,
  'with its minutes');
select throws_ok($$select public.save_study_settings(4, '2026-10-19 12:00+00')$$, '23514', null,
  'fewer than 5 minutes are refused');
select throws_ok($$select public.save_study_settings(181, '2026-10-19 12:00+00')$$, '23514', null,
  'and more than 180');
select throws_ok(
  $$insert into public.study_settings (user_id, daily_minutes, updated_at)
    values ('00000000-0000-4000-8000-00000000000a', 60, now())$$,
  '42501', null, 'a user cannot write the table itself, past the later-wins rule');
reset role;

select pg_temp.sign_in('b');
select is_empty($$select * from public.study_settings$$, 'another user reads no one else''s row');
reset role;
select pg_temp.sign_in(null);
select throws_ok($$select public.save_study_settings(20, now())$$, '42501', null,
  'anon saves nothing');
reset role;

select results_eq($$select daily_minutes from public.study_settings$$, $$values (15)$$,
  'control: the row is there, unchanged by the refused writes');
delete from auth.users where id = '00000000-0000-4000-8000-00000000000a';
select is_empty($$select * from public.study_settings$$, 'the row deletes with its user');

select * from finish();
rollback;
