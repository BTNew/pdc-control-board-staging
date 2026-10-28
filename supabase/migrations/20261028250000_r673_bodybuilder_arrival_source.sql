-- r673 (F282) / sort 421. Staging cdsmnqxtyyoeoznmbidd only.
-- capture_557 writes source 'bodybuilder' for a body-builder delivery reaching PMB (r574/r593), but the
-- pdc_pmb_arrival_557 check only allowed location/key/backfill. Every such move raised 23514, so the
-- body-builder New to PMB hold never opened and import part 40 (job 2a856256) was refused. Allow 'bodybuilder'.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard673$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r673: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r673: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r673: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 421 OR fault_id = 'F282' OR added_in = 'r673' OR check_name = 'bodybuilder_arrival_source_673') THEN RAISE EXCEPTION 'r673: sort 421 or F282 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r673: an import job is running'; END IF;
  IF pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname = 'pdc_pmb_arrival_557_source_check' AND conrelid = 'public.pdc_pmb_arrival_557'::regclass))
     <> 'CHECK ((source = ANY (ARRAY[''location''::text, ''key''::text, ''backfill''::text])))' THEN RAISE EXCEPTION 'r673: check is not the r557 text'; END IF;
END $guard673$;

ALTER TABLE public.pdc_pmb_arrival_557 DROP CONSTRAINT pdc_pmb_arrival_557_source_check;
ALTER TABLE public.pdc_pmb_arrival_557 ADD CONSTRAINT pdc_pmb_arrival_557_source_check
  CHECK (source = ANY (ARRAY['location'::text, 'key'::text, 'backfill'::text, 'bodybuilder'::text]));

DO $check673$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('bodybuilder_arrival_source_673', 'F282',
    'Every source capture_557 can write (location, key, bodybuilder) is allowed by the pdc_pmb_arrival_557 source check.',
    $chk673$
SELECT strpos(pg_get_constraintdef(c.oid), '''bodybuilder''') > 0 AND strpos(pg_get_constraintdef(c.oid), '''location''') > 0
  AND strpos(pg_get_constraintdef(c.oid), '''key''') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_pmb_ack_private.capture_557()')), 'THEN ''bodybuilder''') > 0
 AS ok, 'PMB arrival check allows bodybuilder' AS detail
FROM pg_constraint c WHERE c.conname = 'pdc_pmb_arrival_557_source_check' AND c.conrelid = 'public.pdc_pmb_arrival_557'::regclass
$chk673$, true, 421, 'r673');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'bodybuilder_arrival_source_673') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r673: check red: %', detail; END IF;
END $check673$;
