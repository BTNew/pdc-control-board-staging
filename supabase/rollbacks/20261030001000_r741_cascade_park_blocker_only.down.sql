-- r741 rollback: the park select goes back to "latest current start" (p_apply md5 back to e3f4ba5e929543b36c8e6a536e239fcf),
-- the r424 pin follows, the check is removed. Staging cdsmnqxtyyoeoznmbidd only.
DO $down741$
DECLARE v_oid oid; v_src text; v_new text; v_old_sel text; v_new_sel text; v_n integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r741 down: staging only'; END IF;
  v_oid := to_regprocedure('pdc_bay_seq_private.p_apply(jsonb,text)');
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF strpos(v_src, 'r741 (F346)') = 0 THEN RAISE NOTICE 'r741 down: not applied'; RETURN; END IF;
  v_old_sel := '   SELECT p.* INTO r FROM pg_temp.r424_p p WHERE p.pending AND p.cur_start IS NOT NULL AND p.cur_bay IS NOT NULL ORDER BY p.cur_start DESC,p.id LIMIT 1;';
  v_new_sel := E'   -- r741 (F346): park a job whose current slot blocks another pending job, never one already parked out of the way.\n'
    || E'   SELECT p.* INTO r FROM pg_temp.r424_p p WHERE p.pending AND p.cur_start IS NOT NULL AND p.cur_bay IS NOT NULL\n'
    || E'    AND EXISTS(SELECT 1 FROM pg_temp.r424_p o WHERE o.pending AND o.id<>p.id AND (p.cur_bay=o.bay_id OR p.vehicle_id=o.vehicle_id) AND p.cur_start<o.new_end AND o.new_start<p.cur_end)\n'
    || E'    ORDER BY p.cur_start DESC,p.id LIMIT 1;';
  v_new := replace(v_src, v_new_sel, v_old_sel);
  IF v_new = v_src THEN RAISE EXCEPTION 'r741 down: r741 select not found'; END IF;
  IF md5(v_new) <> 'e3f4ba5e929543b36c8e6a536e239fcf' THEN RAISE EXCEPTION 'r741 down: body would not match the r732 md5'; END IF;
  EXECUTE replace(pg_get_functiondef(v_oid), v_src, v_new);
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = 'e3f4ba5e929543b36c8e6a536e239fcf', note = coalesce(note,'') || '; r741 rolled back', updated_at = clock_timestamp()
  WHERE signature = 'pdc_bay_seq_private.p_apply(jsonb,text)' AND release = 'r424';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r741 down: pin not moved'; END IF;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'cascade_park_blocker_only_741';
END $down741$;
