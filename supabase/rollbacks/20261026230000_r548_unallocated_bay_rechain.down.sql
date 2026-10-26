-- r548 (F162) undo. Staging cdsmnqxtyyoeoznmbidd only. Does not change booking rows.
-- Restores the r417 overlap exemption (queued and bay_id null only) and drops the rechain.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r548 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r548 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r548 undo: pin count is not 241'; END IF;
END $g$;

DROP TRIGGER IF EXISTS zz_pdc_rechain_unallocated_ins_548 ON public.workshop_bookings;
DROP TRIGGER IF EXISTS zz_pdc_rechain_unallocated_548 ON public.workshop_bookings;
DROP FUNCTION IF EXISTS pdc_bay_seq_private.rechain_unallocated_548();
DROP FUNCTION IF EXISTS pdc_bay_seq_private.place_unallocated_after_548(uuid, uuid);

DO $restore$
DECLARE
 v_src text;
 v_sql text;
 v_args text := 'p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean';
BEGIN
 SELECT p.prosrc INTO v_src
 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'workshop_validate_booking'
   AND pg_get_function_identity_arguments(p.oid) = v_args;
 IF v_src IS NULL THEN RAISE EXCEPTION 'r548 undo: validate body missing'; END IF;
 IF position('and b.bay_id IS NOT NULL' IN v_src) = 0 THEN RAISE EXCEPTION 'r548 undo: r548 exemption missing'; END IF;
 IF (length(v_src) - length(replace(v_src, 'b.bay_id IS NOT NULL', ''))) / length('b.bay_id IS NOT NULL') <> 1 THEN RAISE EXCEPTION 'r548 undo: exemption is not unique'; END IF;
 v_src := replace(v_src, 'b.bay_id IS NOT NULL', 'NOT (b.status=''queued'' AND b.bay_id IS NULL)');
 v_sql := 'CREATE OR REPLACE FUNCTION public.workshop_validate_booking(' || v_args || ') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'', ''extensions'' AS $r548undo$' || v_src || '$r548undo$';
 EXECUTE v_sql;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'workshop_validate_booking'
       AND pg_get_function_identity_arguments(p.oid) = v_args) IS DISTINCT FROM '9efb08f2415c28ac57a14b401cf9f605' THEN
  RAISE EXCEPTION 'r548 undo: restored body is not the r417 body';
 END IF;
END $restore$;

DO $dur$
DECLARE v_md5 text; v_n integer;
BEGIN
 SELECT pin.prosrc_md5 INTO v_md5
 FROM pdc_ops.expected_function_md5 pin
 WHERE pin.signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'
   AND pin.release = 'r548';
 IF v_md5 IS NULL THEN RAISE EXCEPTION 'r548 undo: r548 validate md5 missing'; END IF;
 UPDATE pdc_ops.regression_checks
 SET check_sql = replace(check_sql, v_md5, '9efb08f2415c28ac57a14b401cf9f605')
 WHERE check_name IN ('planner_duration_cache_531', 'planner_duration_after_insert_537')
   AND position(v_md5 IN check_sql) > 0;
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n <> 2 THEN RAISE EXCEPTION 'r548 undo: duration checks were not restored'; END IF;
END $dur$;

DO $pin$
DECLARE v_n integer;
BEGIN
 UPDATE pdc_ops.expected_function_md5
 SET prosrc_md5 = '9efb08f2415c28ac57a14b401cf9f605', release = 'r417', note = 'r417 restored by r548 undo', updated_at = clock_timestamp()
 WHERE signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'
   AND release = 'r548';
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n <> 1 THEN RAISE EXCEPTION 'r548 undo: validate pin was not restored'; END IF;
END $pin$;

DELETE FROM pdc_ops.regression_checks WHERE check_name = 'unallocated_bay_rechain_548' AND fault_id = 'F162' AND added_in = 'r548';

DO $done$ BEGIN
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)') IS DISTINCT FROM 'r417' THEN RAISE EXCEPTION 'r548 undo: pin release is not r417'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r548 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'unallocated_bay_rechain_548' OR fault_id = 'F162' OR sort_order = 324) THEN RAISE EXCEPTION 'r548 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('pg_temp.r548_absent') IS NOT NULL THEN RAISE EXCEPTION 'r548 undo: unexpected'; END IF;
END $done$;
