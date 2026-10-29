-- r699 rollback: put the old plan filter back, move the pin back, drop the check.
DO $d$ DECLARE v_old text; v_md5 text; v_def text; BEGIN
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
  v_def := regexp_replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(v_old, ' AND NOT (b.status=''queued'' AND b.bay_id IS NULL); -- r699 (F309): Unallocated work is never a cascade obstacle', ' AND NOT (b.status=''queued'' AND b.bay_id IS NULL AND b.actual_start_at IS NULL);') || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) WHERE prosrc_md5 = v_md5;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)) WHERE strpos(check_sql, v_md5) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name IN ('cascade_ignores_unbayed_queue_699', 'cascade_not_stuck_699');
END $d$;
