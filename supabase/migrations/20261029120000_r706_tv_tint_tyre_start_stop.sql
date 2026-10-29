-- r706 (F316) / sort 456. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 11:00: on the Workshop TV, Tint and Tyres sit side by side at the bottom with each job's full key and a
-- Start and a Stop button (they have one line, no iPad). Every other station stays view-only.
-- The TV read now carries each job's booking id and version, the station's work key, and can_act (this login may
-- start/complete work: operator or administrator, the same rule as the planner). Start and Stop call the existing
-- start_workshop_work / complete_workshop_work, so cascade, ticks (r682) and history behave as on the planner.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $r706$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text; ok boolean; detail text;
  a1 text := 'SELECT k.bay_id, k.status::text AS status,';
  a2 text := '''status'', j.status, ''start'',';
  a3 text := '''version'', ''r605'', ''now'', c.now_at,';
  a4 text := 'jsonb_build_object(''code'', s.code, ''name'', s.display_name,';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r706: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r706: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r706: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 456 OR fault_id = 'F316' OR added_in = 'r706' OR check_name = 'tv_tint_tyre_start_stop_706') THEN RAISE EXCEPTION 'r706: sort 456 or F316 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r706: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.get_pdc_workshop_tv_605()'::regprocedure;
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE prosrc_md5 = md5(v_old)) THEN RAISE EXCEPTION 'r706: TV read is pinned'; END IF;
  IF (length(v_old)-length(replace(v_old,a1,'')))/length(a1) <> 1 OR (length(v_old)-length(replace(v_old,a2,'')))/length(a2) <> 1
     OR (length(v_old)-length(replace(v_old,a3,'')))/length(a3) <> 1 OR (length(v_old)-length(replace(v_old,a4,'')))/length(a4) <> 1 THEN
    RAISE EXCEPTION 'r706: anchors not found once';
  END IF;
  v_new := replace(v_old, a1, 'SELECT k.bay_id, k.id AS booking_id, k.version AS booking_version, k.status::text AS status,');
  v_new := replace(v_new, a2, '''id'', j.booking_id, ''booking_version'', j.booking_version, ''status'', j.status, ''start'',');
  v_new := replace(v_new, a3, '''version'', ''r605'', ''can_act'', coalesce(public.workshop_is_planner_operator(), false), ''now'', c.now_at,');
  v_new := replace(v_new, a4, 'jsonb_build_object(''code'', s.code, ''work_key'', s.work_key, ''name'', s.display_name,');
  v_def := regexp_replace(pg_get_functiondef('public.get_pdc_workshop_tv_605()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('tv_tint_tyre_start_stop_706', 'F316',
    'The Workshop TV read gives each job its booking id and version and says whether this login may start/complete (operator or administrator).',
    $chk$
SELECT strpos(s, '''id'', j.booking_id') > 0 AND strpos(s, '''can_act'', coalesce(public.workshop_is_planner_operator(), false)') > 0
   AND strpos(s, '''work_key'', s.work_key') > 0 AND NOT has_function_privilege('anon', 'public.get_pdc_workshop_tv_605()', 'execute')
 AS ok, 'TV read carries Start/Stop data' AS detail
FROM (SELECT prosrc s FROM pg_proc WHERE oid = to_regprocedure('public.get_pdc_workshop_tv_605()')) x
$chk$, true, 456, 'r706');
  FOR detail IN SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name IN ('workshop_tv_605', 'tv_tint_tyre_start_stop_706') LOOP
    EXECUTE detail INTO ok, v_old;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r706: check red: %', v_old; END IF;
  END LOOP;
END $r706$;
