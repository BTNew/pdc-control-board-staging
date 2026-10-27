-- r585 (F199) undo. Restores the station snapshot and sublet board calculations as the public functions.
-- Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Run between :02 and :45.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r585 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r585 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.station_workshop_snapshot_compute_585(text,date,date)')) IS DISTINCT FROM '98cc6aafa9cc7627c77eda8b46b389fa' THEN RAISE EXCEPTION 'r585 undo: station calculation is not the saved body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.sublet_po_board_compute_585()')) IS DISTINCT FROM '7dde7e19d31b269136a93ebecd12217a' THEN RAISE EXCEPTION 'r585 undo: sublet calculation is not the saved body'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r585 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r585 undo: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r585 undo: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r585 undo: Kajel apply changed'; END IF;
END $g$;

DO $back$
DECLARE def text; n int;
BEGIN
  SELECT pg_get_functiondef('pdc_ops.station_workshop_snapshot_compute_585(text,date,date)'::regprocedure) INTO def;
  n := (length(def)-length(replace(def,'pdc_ops.station_workshop_snapshot_compute_585(','')))/length('pdc_ops.station_workshop_snapshot_compute_585(');
  IF n<>1 THEN RAISE EXCEPTION 'r585 undo: station functiondef shape %', n; END IF;
  def := regexp_replace(def, 'pdc_ops\.station_workshop_snapshot_compute_585\(', 'public.get_station_workshop_snapshot(');
  EXECUTE def;
  SELECT pg_get_functiondef('pdc_ops.sublet_po_board_compute_585()'::regprocedure) INTO def;
  n := (length(def)-length(replace(def,'pdc_ops.sublet_po_board_compute_585(','')))/length('pdc_ops.sublet_po_board_compute_585(');
  IF n<>1 THEN RAISE EXCEPTION 'r585 undo: sublet functiondef shape %', n; END IF;
  def := regexp_replace(def, 'pdc_ops\.sublet_po_board_compute_585\(', 'public.get_pdc_sublet_po_board_439(');
  EXECUTE def;
END
$back$;

REVOKE ALL ON FUNCTION public.get_station_workshop_snapshot(text,date,date), public.get_pdc_sublet_po_board_439() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_station_workshop_snapshot(text,date,date), public.get_pdc_sublet_po_board_439() TO authenticated, service_role;

DROP FUNCTION IF EXISTS pdc_ops.cache_holds_snapshot_585(text,text,date,date,jsonb);
DROP TABLE pdc_ops.station_workshop_snapshot_cache_585;
DROP TABLE pdc_ops.sublet_po_board_cache_585;
DROP FUNCTION pdc_ops.station_workshop_snapshot_compute_585(text,date,date);
DROP FUNCTION pdc_ops.sublet_po_board_compute_585();

DELETE FROM pdc_ops.regression_checks
WHERE check_name='station_sublet_cache_585' AND fault_id='F199' AND sort_order=357 AND added_in='r585';

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5='7dde7e19d31b269136a93ebecd12217a',
    updated_at=now()
WHERE signature='public.get_pdc_sublet_po_board_439()'
  AND release='r439'
  AND prosrc_md5 IS DISTINCT FROM '7dde7e19d31b269136a93ebecd12217a';

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_station_workshop_snapshot(text,date,date)')) IS DISTINCT FROM '98cc6aafa9cc7627c77eda8b46b389fa' THEN RAISE EXCEPTION 'r585 undo: station body did not return'; END IF;
 IF (SELECT provolatile<>'s' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_station_workshop_snapshot(text,date,date)')) THEN RAISE EXCEPTION 'r585 undo: station is not a stable definer'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_sublet_po_board_439()')) IS DISTINCT FROM '7dde7e19d31b269136a93ebecd12217a' THEN RAISE EXCEPTION 'r585 undo: sublet body did not return'; END IF;
 IF (SELECT provolatile<>'s' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_sublet_po_board_439()')) THEN RAISE EXCEPTION 'r585 undo: sublet is not a stable definer'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_sublet_po_board_439()' AND release='r439') IS DISTINCT FROM '7dde7e19d31b269136a93ebecd12217a' THEN RAISE EXCEPTION 'r585 undo: sublet pin did not return'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r585 undo: pin count changed'; END IF;
 IF to_regprocedure('pdc_ops.station_workshop_snapshot_compute_585(text,date,date)') IS NOT NULL
    OR to_regprocedure('pdc_ops.sublet_po_board_compute_585()') IS NOT NULL
    OR to_regclass('pdc_ops.station_workshop_snapshot_cache_585') IS NOT NULL
    OR to_regclass('pdc_ops.sublet_po_board_cache_585') IS NOT NULL
    OR to_regprocedure('pdc_ops.cache_holds_snapshot_585(text,text,date,date,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r585 undo: cache objects remain'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='station_sublet_cache_585' OR fault_id='F199' OR sort_order=357 OR added_in='r585') THEN RAISE EXCEPTION 'r585 undo: check remains'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r585 undo: department 135 changed'; END IF;
END $p$;
