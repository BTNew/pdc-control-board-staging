-- r754 rollback: the overdue planned job goes back to the 15 minute floor (r752 state).
DO $down754$
DECLARE v_old text; v_new text; v_def text; v_md5 text;
  c_new text := E'\n         -- r754 (F359): an overdue planned job follows the clock within 5 minutes; a live overrun keeps the 15 minute step.\n         OR (status=''planned'' AND actual_start_at IS NULL AND original_start<p_now AND abs(extract(epoch FROM ((movement->>''to'')::timestamptz-original_start)))>=300));';
BEGIN
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
  IF (length(v_old) - length(replace(v_old, c_new, ''))) / length(c_new) <> 1 THEN RAISE EXCEPTION 'r754 down: anchor not found once'; END IF;
  v_new := replace(v_old, c_new, ');');
  v_def := regexp_replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF md5(v_new) <> '593971a38ed792793513985f49156ac6' THEN RAISE EXCEPTION 'r754 down: body is not the r737 body'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(replace(check_sql,
      $a$(before_data->>'scheduled_start_at')::timestamptz)))<300$a$, $a$(before_data->>'scheduled_start_at')::timestamptz)))<900$a$),
      $a$(before_data->>'scheduled_end_at')::timestamptz)))<300$a$, $a$(before_data->>'scheduled_end_at')::timestamptz)))<900$a$)
    WHERE check_name = 'clock_tick_resaves_per_tick';
END $down754$;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'overdue_job_follows_clock_754';
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261030111500';
