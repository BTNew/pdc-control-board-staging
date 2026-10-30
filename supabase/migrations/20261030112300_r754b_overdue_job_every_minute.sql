-- r754b (F359). Staging cdsmnqxtyyoeoznmbidd only. Craig 30 Oct 11:21: "Tyres not cascading?" (key 635 at 11:16 with
-- the clock at 11:21: the r754 5 minute lag). An overdue planned job now follows the clock every minute, as before
-- r431; board refreshes are cheap since r676 (delta payloads), which was the reason r431 stepped to 30 minutes.
-- Applied by hand 30 Oct 11:23 AWST (same anchored replace as below); this file records it and is idempotent.
-- Rollback: the r754 down file restores the r737 body from either state.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';
DO $r754b$
DECLARE v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_old text := E'original_start<p_now AND abs(extract(epoch FROM ((movement->>''to'')::timestamptz-original_start)))>=300));';
  c_new text := E'original_start<p_now AND abs(extract(epoch FROM ((movement->>''to'')::timestamptz-original_start)))>=60));';
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r754b: staging only'; END IF;
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
  IF v_md5 = '555a44a37a1b7e0f86b179e86e38ef52' THEN RETURN; END IF; -- already applied
  IF v_md5 <> 'd2f62c3539e8c6dcf318b62d5b34e0f5' THEN RAISE EXCEPTION 'r754b: tick is not the r754 body'; END IF;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r754b: anchor not found once'; END IF;
  v_new := replace(v_old, c_old, c_new);
  v_def := regexp_replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r754b: pin (%)', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n < 6 THEN RAISE EXCEPTION 'r754b: literals (%)', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'original_start)))>=300', 'original_start)))>=60'),
    description = 'Clock (r754b): an overdue planned job follows the clock every minute. The tick carries the r754 line and no planned job in an active bay is more than 3 minutes overdue while the clock runs.'
    WHERE check_name = 'overdue_job_follows_clock_754';
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, $a$b.scheduled_start_at < now() - interval '7 minutes'$a$, $a$b.scheduled_start_at < now() - interval '3 minutes'$a$) WHERE check_name = 'overdue_job_follows_clock_754';
  UPDATE pdc_ops.regression_checks SET check_sql = replace(replace(check_sql, $a$(before_data->>'scheduled_start_at')::timestamptz)))<300$a$, $a$(before_data->>'scheduled_start_at')::timestamptz)))<60$a$), $a$(before_data->>'scheduled_end_at')::timestamptz)))<300$a$, $a$(before_data->>'scheduled_end_at')::timestamptz)))<60$a$) WHERE check_name = 'clock_tick_resaves_per_tick';
END $r754b$;
