-- r695 (F305) / sort 446. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 09:19: the Later buttons on the fitter iPad do nothing. set_line_later_627 checked the fitter login's
-- own user id against the bay's mechanic (pdc_fitter_private.assigned takes a technician id). The iPads use one shared
-- fitter login, so every Later and "Complete & leave for later" returned assignment_changed; none ever saved.
-- Now a fitter passes when the booking has an active assigned (or bay default) mechanic, the same as the iPad's job reads.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $r695$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text;
  c_old text := 'NOT pdc_fitter_private.assigned(p_booking_id, v_uid)';
  c_new text := 'NOT EXISTS (SELECT 1 FROM public.workshop_technicians t WHERE t.active AND pdc_fitter_private.assigned(p_booking_id, t.id))';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r695: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r695: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r695: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 446 OR fault_id = 'F305' OR added_in = 'r695' OR check_name = 'fitter_later_shared_login_695') THEN RAISE EXCEPTION 'r695: sort 446 or F305 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r695: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.set_line_later_627(uuid,text,text,text)'::regprocedure;
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE prosrc_md5 = md5(v_old)) THEN RAISE EXCEPTION 'r695: function is pinned'; END IF;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r695: anchor not found once'; END IF;
  v_new := replace(v_old, c_old, c_new);
  v_def := regexp_replace(pg_get_functiondef('public.set_line_later_627(uuid,text,text,text)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('fitter_later_shared_login_695', 'F305',
    'Later on the fitter iPad works with the shared fitter login (assignment is checked by mechanic, not by login).',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.set_line_later_627(uuid,text,text,text)')), 'pdc_fitter_private.assigned(p_booking_id, v_uid)') = 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.set_line_later_627(uuid,text,text,text)')), 'pdc_fitter_private.assigned(p_booking_id, t.id)') > 0
 AS ok, 'fitter Later checks the mechanic' AS detail
$chk$, true, 446, 'r695');
END $r695$;

DO $post695$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name IN ('fitter_later_627', 'fitter_later_shared_login_695') LOOP
    EXECUTE r.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r695: check % red: %', r.check_name, detail; END IF;
  END LOOP;
END $post695$;
