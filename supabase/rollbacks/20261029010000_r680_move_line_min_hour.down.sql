-- r680 rollback: remove the two r680 lines from set_vehicle_work_category, move the pin back, drop the check.
DO $d$ DECLARE v_old text; v_new text; v_def text; v_m text; c_sig text := 'set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'; BEGIN
  SELECT prosrc, md5(prosrc) INTO v_old, v_m FROM pg_proc WHERE oid = c_sig::regprocedure;
  v_new := replace(v_old, E'     IF mins<60 THEN mins:=60; END IF; -- r680 (F290): bookings are never under 60 minutes (r372 guard)\n', '');
  v_new := replace(v_new, E'     -- r680 (F290): a start that has passed cannot be resized (planner past_start); keep its length.\n     IF rec.scheduled_start_at >= clock_timestamp() AND (mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at) THEN',
    E'     IF mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at THEN');
  v_def := regexp_replace(pg_get_functiondef(c_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = c_sig::regprocedure) WHERE prosrc_md5 = v_m;
END $d$;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'move_line_min_hour_680';
