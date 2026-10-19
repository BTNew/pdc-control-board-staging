-- Local proof that the two new indexes replace the sequential scans.
-- The tables here have only the columns the migration guards. They are not
-- the staging tables.

CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard()
RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;

CREATE TABLE public.pdc_tune_operation_change_reviews (
  change_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  status text NOT NULL,
  change_kind text NOT NULL
);
CREATE TABLE public.pdc_authenticated_email_operation_lines (
  operation_line_id uuid PRIMARY KEY,
  vehicle_id uuid
);

INSERT INTO public.pdc_tune_operation_change_reviews
SELECT gen_random_uuid(), CASE WHEN g < 200 THEN '11111111-1111-4111-8111-111111111111'::uuid ELSE gen_random_uuid() END,
       CASE WHEN g % 2 = 0 THEN 'approved' ELSE 'pending' END,
       CASE WHEN g % 3 = 0 THEN 'added' ELSE 'changed' END
FROM generate_series(1, 241) g;
INSERT INTO public.pdc_authenticated_email_operation_lines
SELECT gen_random_uuid(), CASE WHEN g < 20 THEN '22222222-2222-4222-8222-222222222222'::uuid ELSE gen_random_uuid() END
FROM generate_series(1, 400) g;
ANALYZE public.pdc_tune_operation_change_reviews;
ANALYZE public.pdc_authenticated_email_operation_lines;

CREATE FUNCTION public.capture_plan(p_sql text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE line text; plan text := '';
BEGIN
  FOR line IN EXECUTE 'EXPLAIN ' || p_sql LOOP
    plan := plan || line || E'\n';
  END LOOP;
  RETURN plan;
END $$;

SET enable_seqscan = off;

DO $$
DECLARE plan text;
BEGIN
  plan := public.capture_plan($q$SELECT 1 FROM public.pdc_tune_operation_change_reviews q
    WHERE q.vehicle_id = '11111111-1111-4111-8111-111111111111'::uuid
      AND q.status = 'approved' AND q.change_kind = 'added'$q$);
  IF plan NOT LIKE '%Seq Scan%' THEN
    RAISE EXCEPTION 'tune reviews were not a sequential scan before the index: %', plan;
  END IF;
  plan := public.capture_plan($q$SELECT 1 FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id = '22222222-2222-4222-8222-222222222222'::uuid$q$);
  IF plan NOT LIKE '%Seq Scan%' THEN
    RAISE EXCEPTION 'email lines were not a sequential scan before the index: %', plan;
  END IF;
END $$;
