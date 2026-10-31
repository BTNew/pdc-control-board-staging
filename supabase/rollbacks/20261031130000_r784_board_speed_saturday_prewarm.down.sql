-- Rollback r784 (F392): prewarm back to Monday to Friday; compute_554 back to the r780 body; pins moved back.
DO $d$
DECLARE v_src text; v_def text; v_cur text; v_job bigint; sig regprocedure := 'pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure;
BEGIN
  SELECT jobid INTO v_job FROM cron.job WHERE jobname = 'staging-vehicle-board-prewarm-729';
  PERFORM cron.alter_job(v_job, command := (SELECT replace(command, $q$AT TIME ZONE 'Australia/Perth') < 7$q$, $q$AT TIME ZONE 'Australia/Perth') < 6$q$) FROM cron.job WHERE jobid = v_job));
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, $q$AT TIME ZONE 'Australia/Perth') < 7$q$, $q$AT TIME ZONE 'Australia/Perth') < 6$q$) WHERE check_name = 'board_prewarm_729';
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_ops.vehicle_location_snapshot_compute_554()@r784pre';
  SELECT md5(prosrc) INTO v_cur FROM pg_proc WHERE oid = sig;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_cur, md5(v_src)) WHERE position(v_cur IN check_sql) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'board_speed_784';
END $d$;
