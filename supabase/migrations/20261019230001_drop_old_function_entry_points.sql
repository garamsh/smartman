-- The extraction count's entry points that only an extract-cards function deployed before the
-- prompt store or before plans called (ADR 0078, issue #250). The function deployed with this
-- change calls begin_extraction alone, and no older build is kept working before the first store
-- release. Additive in effect: it drops two functions and changes no row.

drop function public.consume_extraction(uuid, integer);
drop function public.start_extraction(uuid);
