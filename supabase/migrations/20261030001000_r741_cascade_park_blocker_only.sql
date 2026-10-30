-- r741 (F346): the cascade apply no longer thrashes when it has to park a job.
-- When no pending job can be placed, p_apply parks one far in the future to break the deadlock. It chose the pending
-- job with the latest current start, which after the first park is the job it just parked, so it re-parked that same
-- job a day later on every pass (103 parks in Craig's Bay 4 swap) until the statement timed out. It now parks a job
-- whose current slot is actually blocking another pending job; a parked job blocks nothing, so each park makes progress
-- (same swap: 33 passes, 7 parks, 5.5s, no overlaps). The rest of the body is byte-identical; the r424 pin follows.
-- Staging cdsmnqxtyyoeoznmbidd only. Production never touched.
-- Rollback: supabase/rollbacks/20261030001000_r741_cascade_park_blocker_only.down.sql
DO $r741$
DECLARE v_oid oid; v_src text; v_new text; v_def text; v_old_sel text; v_new_sel text; v_n integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r741: staging only'; END IF;
  v_oid := to_regprocedure('pdc_bay_seq_private.p_apply(jsonb,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'r741: p_apply missing'; END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF strpos(v_src, 'r741 (F346)') > 0 THEN RAISE NOTICE 'r741: already applied'; RETURN; END IF;
  v_old_sel := '   SELECT p.* INTO r FROM pg_temp.r424_p p WHERE p.pending AND p.cur_start IS NOT NULL AND p.cur_bay IS NOT NULL ORDER BY p.cur_start DESC,p.id LIMIT 1;';
  IF (length(v_src) - length(replace(v_src, v_old_sel, ''))) / length(v_old_sel) <> 1 THEN
    RAISE EXCEPTION 'r741: park select not found exactly once';
  END IF;
  v_new_sel := E'   -- r741 (F346): park a job whose current slot blocks another pending job, never one already parked out of the way.\n'
    || E'   SELECT p.* INTO r FROM pg_temp.r424_p p WHERE p.pending AND p.cur_start IS NOT NULL AND p.cur_bay IS NOT NULL\n'
    || E'    AND EXISTS(SELECT 1 FROM pg_temp.r424_p o WHERE o.pending AND o.id<>p.id AND (p.cur_bay=o.bay_id OR p.vehicle_id=o.vehicle_id) AND p.cur_start<o.new_end AND o.new_start<p.cur_end)\n'
    || E'    ORDER BY p.cur_start DESC,p.id LIMIT 1;';
  v_new := replace(v_src, v_old_sel, v_new_sel);
  IF v_new = v_src THEN RAISE EXCEPTION 'r741: body unchanged'; END IF;
  v_def := replace(pg_get_functiondef(v_oid), v_src, v_new);
  IF v_def = pg_get_functiondef(v_oid) THEN RAISE EXCEPTION 'r741: definition unchanged'; END IF;
  EXECUTE v_def;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF v_src <> v_new THEN RAISE EXCEPTION 'r741: readback differs'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new), note = coalesce(note,'') || '; r741 (F346): park a blocker only; was e3f4ba5e929543b36c8e6a536e239fcf', updated_at = clock_timestamp()
  WHERE signature = 'pdc_bay_seq_private.p_apply(jsonb,text)' AND release = 'r424';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r741: p_apply pin not moved'; END IF;
END $r741$;

INSERT INTO pdc_ops.regression_checks(check_name, sort_order, fault_id, added_in, enabled, description, check_sql)
VALUES ('cascade_park_blocker_only_741', 459, 'F346', 'r741', true,
  'When the cascade apply has to park a job to break a deadlock it parks one whose current slot blocks another pending job, never a job already parked, so a bay swap or push-back finishes in a handful of passes instead of re-parking the same job until the statement times out; the body matches its pin.',
  $chk$
SELECT strpos(src, 'r741 (F346)') > 0
   AND strpos(src, 'AND EXISTS(SELECT 1 FROM pg_temp.r424_p o WHERE o.pending AND o.id<>p.id AND (p.cur_bay=o.bay_id OR p.vehicle_id=o.vehicle_id) AND p.cur_start<o.new_end AND o.new_start<p.cur_end)') > 0
   AND strpos(src, 'p.cur_bay IS NOT NULL ORDER BY p.cur_start DESC,p.id LIMIT 1;') = 0
   AND pg_catalog.md5(src) = (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature = 'pdc_bay_seq_private.p_apply(jsonb,text)' AND e.release = 'r424') AS ok,
 'cascade parks a blocker only (r741)' AS detail
FROM (SELECT prosrc src FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_bay_seq_private.p_apply(jsonb,text)')) s
$chk$)
ON CONFLICT (check_name) DO NOTHING;

DO $post741$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('cascade_park_blocker_only_741','qc_lines_memo_732','category_move_full_bay_730','protected_function_md5s','regression_checks_self_test') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r741: % red after apply: %', r.check_name, left(r.detail, 160); END IF;
  END LOOP;
END $post741$;
