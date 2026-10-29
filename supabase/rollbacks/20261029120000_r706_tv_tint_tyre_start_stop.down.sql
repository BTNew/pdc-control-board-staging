-- r706 rollback: take the Start/Stop fields back out of the TV read and drop the check.
DO $d$ DECLARE v text; d text; BEGIN
  SELECT prosrc INTO v FROM pg_proc WHERE oid = 'public.get_pdc_workshop_tv_605()'::regprocedure;
  v := replace(v, 'SELECT k.bay_id, k.id AS booking_id, k.version AS booking_version, k.status::text AS status,', 'SELECT k.bay_id, k.status::text AS status,');
  v := replace(v, '''id'', j.booking_id, ''booking_version'', j.booking_version, ''status'', j.status, ''start'',', '''status'', j.status, ''start'',');
  v := replace(v, '''version'', ''r605'', ''can_act'', coalesce(public.workshop_is_planner_operator(), false), ''now'', c.now_at,', '''version'', ''r605'', ''now'', c.now_at,');
  v := replace(v, 'jsonb_build_object(''code'', s.code, ''work_key'', s.work_key, ''name'', s.display_name,', 'jsonb_build_object(''code'', s.code, ''name'', s.display_name,');
  d := regexp_replace(pg_get_functiondef('public.get_pdc_workshop_tv_605()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE d || v || substring(d from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'tv_tint_tyre_start_stop_706';
END $d$;
