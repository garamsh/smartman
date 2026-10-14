-- A review's fuzz factor (ADR 0012), synced with it: the draw in [0, 1) that placed its
-- interval in the fuzz range, null for a review scheduled without fuzz. Clients insert it
-- through the table's insert grant; the column update grant stays rating and updated_at,
-- so no client changes it afterwards.
alter table public.reviews
  add column fuzz_factor double precision check (fuzz_factor >= 0 and fuzz_factor < 1);
