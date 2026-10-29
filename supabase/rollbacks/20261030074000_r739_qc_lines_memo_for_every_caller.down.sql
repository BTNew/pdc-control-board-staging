-- r739 rollback: the reader goes back to the r735 body (memo only for the cascade), the pin and the three md5 checks
-- follow, the check is removed. Staging cdsmnqxtyyoeoznmbidd only.
DO $pre$
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE prosrc_md5 = 'b67e9ee98000a647d14c6cbf0506ee48') THEN RAISE EXCEPTION 'r739 down: reader already at the r735 body'; END IF;
END $pre$;
CREATE TEMP TABLE r739_down_old ON COMMIT DROP AS SELECT md5(prosrc) AS m FROM pg_proc WHERE oid = 'public.pdc_qc_operation_lines_379(uuid)'::regprocedure;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v jsonb;
BEGIN
 -- r732 (F342): a cascade transaction keeps a memo of the lines it recomputed; it is valid only while the cache
 -- epoch generations it was stamped with are unchanged.
 IF EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = to_regclass('pg_temp.pdc_qc_lines_memo_732') AND c.relpersistence = 't'
            AND c.relowner = (SELECT proowner FROM pg_proc WHERE oid = 'pdc_work_categories_private.qc_lines_memo_fill_732(uuid)'::regprocedure)) THEN
  SELECT m.lines INTO v FROM pg_temp.pdc_qc_lines_memo_732 m
   WHERE m.vehicle_id = p_vehicle_id
     AND m.vgen = coalesce((SELECT e.gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e WHERE e.vehicle_id = p_vehicle_id), 0)
     AND m.ggen = coalesce((SELECT e.gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e WHERE e.vehicle_id = '00000000-0000-0000-0000-000000000000'::uuid), 0);
  IF v IS NOT NULL THEN RETURN v; END IF;
 END IF;
 SELECT c.lines INTO v FROM pdc_work_categories_private.qc_operation_lines_cache c WHERE c.vehicle_id = p_vehicle_id;
 IF v IS NOT NULL THEN RETURN v; END IF;
 RETURN public.pdc_qc_operation_lines_379_uncached(p_vehicle_id);
END $function$;

DO $down739$
DECLARE v_old text; v_new text;
BEGIN
  SELECT m INTO v_old FROM r739_down_old;
  SELECT md5(prosrc) INTO v_new FROM pg_proc WHERE oid = 'public.pdc_qc_operation_lines_379(uuid)'::regprocedure;
  IF v_new <> 'b67e9ee98000a647d14c6cbf0506ee48' THEN RAISE EXCEPTION 'r739 down: restored body is not the r735 body'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_new WHERE prosrc_md5 = v_old;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_old, v_new) WHERE strpos(check_sql, v_old) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'qc_lines_memo_every_caller_739';
END $down739$;
