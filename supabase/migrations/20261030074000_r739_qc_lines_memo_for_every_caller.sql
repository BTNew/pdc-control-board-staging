-- r739 (F345) / sort 458. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 07:25: "Fitters are having problems starting and stopping". Resume on key 448 (Hoist 02) ran past the
-- 30 s API limit: the resume re-times the booking (the booking trigger drops that car's QC lines cache row) and pushes
-- the later jobs in the bay (each push drops its car's row); every validation step after that recomputed those cars'
-- lines uncached, hundreds of times in one transaction. r732 solved the same shape for the planner cascade with a
-- transaction memo that only p_apply fills. This release gives EVERY caller the memo: on a cache miss the reader keeps
-- the computed lines in a transaction-local setting (a STABLE function may not write a table), stamped with the
-- per-car and global cache generations, so a later invalidation in the same transaction still forces a recompute.
-- Applied 30 Oct 07:47 AWST; the first body used a setting name starting with a digit (pdc.qcl.<hex>), which Postgres
-- rejects, so every cache miss failed for about 90 s until the key got a 'v' prefix at 07:49. This file holds the fixed body.
-- Rollback: supabase/rollbacks/20261030074000_r739_qc_lines_memo_for_every_caller.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $pre739$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r739: staging only'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.pdc_qc_operation_lines_379(uuid)'::regprocedure) IS DISTINCT FROM 'b67e9ee98000a647d14c6cbf0506ee48'
    THEN RAISE EXCEPTION 'r739: reader body is not the r735 body'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 458 OR fault_id = 'F345' OR added_in = 'r739' OR check_name = 'qc_lines_memo_every_caller_739') THEN RAISE EXCEPTION 'r739: sort 458 or F345 is taken'; END IF;
END $pre739$;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v jsonb; vgen bigint; ggen bigint; memo jsonb; key text;
BEGIN
 vgen := coalesce((SELECT e.gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e WHERE e.vehicle_id = p_vehicle_id), 0);
 ggen := coalesce((SELECT e.gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e WHERE e.vehicle_id = '00000000-0000-0000-0000-000000000000'::uuid), 0);
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
 -- r739 (F345): every caller gets a transaction memo. A STABLE function may not write a table, so the memo lives in a
 -- transaction-local setting, stamped with both generations; an invalidation later in the transaction misses it.
 key := 'pdc.qcl.v' || replace(p_vehicle_id::text, '-', '');
 memo := nullif(current_setting(key, true), '')::jsonb;
 IF memo IS NOT NULL AND (memo->>'v')::bigint = vgen AND (memo->>'g')::bigint = ggen THEN RETURN memo->'l'; END IF;
 v := public.pdc_qc_operation_lines_379_uncached(p_vehicle_id);
 PERFORM set_config(key, jsonb_build_object('v', vgen, 'g', ggen, 'l', v)::text, true);
 RETURN v;
END $function$;

DO $r739$
DECLARE v_new text; v_n integer; c_old text := 'b67e9ee98000a647d14c6cbf0506ee48';
BEGIN
  SELECT md5(prosrc) INTO v_new FROM pg_proc WHERE oid = 'public.pdc_qc_operation_lines_379(uuid)'::regprocedure;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_new WHERE prosrc_md5 = c_old;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r739: pin row not moved (%)', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, c_old, v_new) WHERE strpos(check_sql, c_old) > 0;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 3 THEN RAISE EXCEPTION 'r739: expected 3 checks to follow the reader md5, got %', v_n; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('qc_lines_memo_every_caller_739', 'F345',
    'On a QC lines cache miss the reader keeps the computed lines for the rest of the transaction (transaction-local setting stamped with both cache generations), so a resume, push or cascade never recomputes one car hundreds of times.',
    $chk$
SELECT strpos(src, 'key := ''pdc.qcl.v'' || replace(p_vehicle_id::text, ''-'', '''');') > 0
   AND strpos(src, '(memo->>''v'')::bigint = vgen AND (memo->>''g'')::bigint = ggen THEN RETURN memo->''l''') > 0
   AND strpos(src, 'PERFORM set_config(key, jsonb_build_object(''v'', vgen, ''g'', ggen, ''l'', v)::text, true);') > 0 AS ok,
 'reader memoises a cache miss for the transaction' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) s
$chk$, true, 458, 'r739');
END $r739$;

DO $post739$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('qc_lines_memo_every_caller_739','qc_lines_memo_732','protected_function_md5s','regression_checks_self_test','station_icon_completion_578','board_qc_nesting_587','qc_signoff_override_590') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r739: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
END $post739$;
