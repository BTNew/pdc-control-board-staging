-- r721 rollback: restore the finished-booking block and the work item rule, move the pin back, drop the check.
DO $d$ DECLARE v text; m text; d text; s text := 'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'; BEGIN
  SELECT prosrc, md5(prosrc) INTO v, m FROM pg_proc WHERE oid = s::regprocedure;
  v := replace(v, $b$   OR (b.status='completed' AND s.code IN(src_stage,target) AND b.work_category_scope ? p_line_identity) -- r721 (F331): only a finished job that did this line$b$,
    $a$   OR (b.status='completed' AND s.code IN(src_stage,target) AND (b.work_category IS NULL OR b.work_category_scope ? p_line_identity OR (b.work_category='BUS_WHOLE_JOB' AND b.work_category_scope ? p_line_identity)))$a$);
  v := replace(v, $b$ ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,completed=false,completed_by=NULL,completed_at=NULL,updated_at=clock_timestamp() WHERE public.vehicle_work_items.vehicle_id=excluded.vehicle_id; -- r721 (F331): an open line moved in reopens the station$b$,
    $a$ ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true WHERE NOT public.vehicle_work_items.completed;$a$);
  d := regexp_replace(pg_get_functiondef(s::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE d || v || substring(d from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = s::regprocedure) WHERE prosrc_md5 = m;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, m, (SELECT md5(prosrc) FROM pg_proc WHERE oid = s::regprocedure)) WHERE strpos(check_sql, m) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'move_into_finished_station_721';
END $d$;
