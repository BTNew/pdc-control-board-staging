-- r673 rollback: restore the r557 check (fails if any bodybuilder row exists) and drop the check row.
ALTER TABLE public.pdc_pmb_arrival_557 DROP CONSTRAINT pdc_pmb_arrival_557_source_check;
ALTER TABLE public.pdc_pmb_arrival_557 ADD CONSTRAINT pdc_pmb_arrival_557_source_check CHECK (source = ANY (ARRAY['location'::text, 'key'::text, 'backfill'::text]));
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'bodybuilder_arrival_source_673';
