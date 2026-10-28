-- Undo r602 (F216) / sort 373. Staging cdsmnqxtyyoeoznmbidd only.
-- Drops the read-only board snapshot and its check. Does not change Kajel's functions or the pin table.
SET LOCAL lock_timeout = '8s';
DO $g$
DECLARE
  awst time;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r602 undo: quiet window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r602 undo: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r602 undo: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r602 undo: pin count is not 241'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='revolution_board_602' AND fault_id='F216' AND sort_order=373 AND added_in='r602')<>1 THEN RAISE EXCEPTION 'r602 undo: check is not the r602 check'; END IF;
  IF pg_catalog.strpos((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.pdc_revolution_board_602(text)')), 'r602 board snapshot') = 0 THEN RAISE EXCEPTION 'r602 undo: board snapshot is not the r602 body'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r602 undo: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r602 undo: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r602 undo: department 135 changed'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='revolution_board_602' AND fault_id='F216' AND sort_order=373 AND added_in='r602';

DROP FUNCTION IF EXISTS public.pdc_revolution_board_602(text);

DO $p$
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='revolution_board_602' OR fault_id='F216' OR sort_order=373 OR added_in='r602') THEN RAISE EXCEPTION 'r602 undo: check remains'; END IF;
  IF to_regprocedure('public.pdc_revolution_board_602(text)') IS NOT NULL THEN RAISE EXCEPTION 'r602 undo: board snapshot remains'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r602 undo: pin count changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r602 undo: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r602 undo: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r602 undo: department 135 changed'; END IF;
END $p$;
