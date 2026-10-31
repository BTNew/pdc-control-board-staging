-- Rollback r780 (F384): restore compute_554 from the backup and move the four md5 pins back.
DO $d$
DECLARE v_src text; v_def text; v_cur text; sig regprocedure := 'pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_ops.vehicle_location_snapshot_compute_554()@r780pre';
  IF md5(v_src) <> 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'backup missing'; END IF;
  SELECT md5(prosrc) INTO v_cur FROM pg_proc WHERE oid = sig;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_cur, 'e7f77fad301b8a87ef548472a8f790a6')
  WHERE check_name IN ('board_identity_open_454','snapshot_outer_single_eval','read_once_snapshots_554','snapshot_segments_collapsed');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'snapshot_follows_line_moves_780';
END $d$;
