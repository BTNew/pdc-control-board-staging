-- r738 (F344) / sort 457. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 06:49: "THE WEBSITE IS SLOW AND NEEDS TO REFRESH ALL THE TIME"; 06:53: "i cant move items from elec to
-- fitting etc" (canceling statement due to lock timeout).
-- Cause: the Service as a Whole import (40 parts, preview + apply each) writes a row to
-- pdc_pilbara_service_import_batches per part, and the QC lines cache invalidator treated that table as global: every
-- batch row wiped the lines cache for all 617 cars (145 wipes in 35 minutes). Each board or station load then recomputed
-- every car (the sublet PO board took 115 s, API limit 30 s) while the import held the planner lock.
-- A batch row only changes lines for operations whose history points at it (service_catalogue_hours_20260917 joins
-- history to the apply batch and, by source hash, to its preview batch). This file invalidates exactly those cars.
-- The per-row triggers on operations, history and import rows already cover everything else the import writes.
-- Rollback: supabase/rollbacks/20261030070500_r738_import_batch_row_invalidates_its_vehicles.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $r738$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_old text := $o$  IF TG_OP = 'TRUNCATE' OR TG_TABLE_NAME IN ('ai_routing_20261019', 'import_rules_139_20261018', 'import_rules_20261017', 'navision_backend_records', 'pdc_pilbara_service_import_batches', 'workshop_stage_aliases', 'workshop_stages') THEN$o$;
  c_new text := $n$  IF TG_OP = 'TRUNCATE' OR TG_TABLE_NAME IN ('ai_routing_20261019', 'import_rules_139_20261018', 'import_rules_20261017', 'navision_backend_records', 'workshop_stage_aliases', 'workshop_stages') THEN$n$;
  c_old2 text := $o$  IF TG_TABLE_NAME = 'vehicles' THEN
    IF TG_OP = 'INSERT' THEN$o$;
  c_new2 text := $n$  IF TG_TABLE_NAME = 'pdc_pilbara_service_import_batches' THEN
    -- r738 (F344): a batch row changes lines only for operations whose history points at it (the apply batch, or the
    -- preview batch that shares its source hash). Never the whole cache: the Service as a Whole import writes 80 of
    -- these rows per run and each wipe cost every board load a full recompute.
    PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(
      ARRAY(
        SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operation_history hist
        JOIN public.pdc_pilbara_service_operations o ON o.operation_id = hist.operation_id
        WHERE hist.batch_id IN (SELECT b.batch_id FROM public.pdc_pilbara_service_import_batches b
                                WHERE b.batch_id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.batch_id END, CASE WHEN TG_OP <> 'DELETE' THEN NEW.batch_id END)
                                   OR b.source_hash IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.source_hash END, CASE WHEN TG_OP <> 'DELETE' THEN NEW.source_hash END))
      ), false);
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache c
    WHERE c.vehicle_id IN (
        SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operation_history hist
        JOIN public.pdc_pilbara_service_operations o ON o.operation_id = hist.operation_id
        WHERE hist.batch_id IN (SELECT b.batch_id FROM public.pdc_pilbara_service_import_batches b
                                WHERE b.batch_id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.batch_id END, CASE WHEN TG_OP <> 'DELETE' THEN NEW.batch_id END)
                                   OR b.source_hash IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.source_hash END, CASE WHEN TG_OP <> 'DELETE' THEN NEW.source_hash END)));
    RETURN NULL;
  END IF;
  IF TG_TABLE_NAME = 'vehicles' THEN
    IF TG_OP = 'INSERT' THEN$n$;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r738: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r738: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r738: an import job is running'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 457 OR fault_id = 'F344' OR added_in = 'r738' OR check_name = 'import_batch_row_invalidates_its_vehicles_738') THEN RAISE EXCEPTION 'r738: sort 457 or F344 is taken'; END IF;
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r738: anchor 1 not found once'; END IF;
  IF (length(v_old) - length(replace(v_old, c_old2, ''))) / length(c_old2) <> 1 THEN RAISE EXCEPTION 'r738: anchor 2 not found once'; END IF;
  v_new := replace(replace(v_old, c_old, c_new), c_old2, c_new2);
  v_def := regexp_replace(pg_get_functiondef('pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure) <> v_new THEN RAISE EXCEPTION 'r738: readback differs'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r738: pin row not moved (%)', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('import_batch_row_invalidates_its_vehicles_738', 'F344',
    'A service import batch row invalidates the QC lines cache only for the cars whose operation history points at that batch, never the whole cache (an import run wrote 80 batch rows and each one wiped all 617 cars).',
    $chk$
SELECT strpos(src, 'IF TG_TABLE_NAME = ''pdc_pilbara_service_import_batches'' THEN') > 0
   AND strpos(src, 'TG_TABLE_NAME IN (''ai_routing_20261019'', ''import_rules_139_20261018'', ''import_rules_20261017'', ''navision_backend_records'', ''workshop_stage_aliases'', ''workshop_stages'')') > 0 AS ok,
 'batch rows invalidate their own cars' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('pdc_work_categories_private.invalidate_qc_operation_lines_cache()')) s
$chk$, true, 457, 'r738');
END $r738$;

DO $post738$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('import_batch_row_invalidates_its_vehicles_738','protected_function_md5s','regression_checks_self_test') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r738: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
END $post738$;
