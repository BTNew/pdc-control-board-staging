-- r677 (F287) / sort 425. Staging cdsmnqxtyyoeoznmbidd only.
-- Follows r675 (F284). PostgREST retries SQLSTATE 40001/40P01 inside the request, so a business conflict raised
-- with those codes ("changed elsewhere, refresh") can loop for hours. Every staff-facing function that raises them
-- for a conflict now raises PT409 (HTTP 409, never retried). Messages are unchanged.
-- Excluded: karratha schemas, Kajel's import apply, workshop_clock_tick (cron, not PostgREST),
-- start_workshop_work_pre_116, and any function whose md5 a regression check names.
-- set_pdc_pit_line_tick_401 and set_pdc_sublet_line_tick_439 are pinned: their pin rows move to the new md5 (r677).
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '120s';

DO $r677$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  r record; v_new text; v_def text; v_md5 text; v_done integer := 0; v_pins integer := 0; v_n integer;
  c_pat text := '(errcode\s*=\s*)''(40001|40P01|serialization_failure|deadlock_detected)''';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r677: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r677: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r677: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 425 OR fault_id = 'F287' OR added_in = 'r677' OR check_name = 'conflicts_not_retryable_677') THEN RAISE EXCEPTION 'r677: sort 425 or F287 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r677: an import job is running'; END IF;
  FOR r IN
    SELECT p.oid, p.proname, p.oid::regprocedure::text sig, p.prosrc, md5(p.prosrc) m,
           EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 e WHERE e.prosrc_md5 = md5(p.prosrc)) pinned
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prosrc ~* c_pat AND n.nspname NOT LIKE 'karratha%'
      AND p.proname NOT IN ('pdc_pilbara_service_apply_v1', 'workshop_clock_tick', 'start_workshop_work_pre_116')
      AND NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks c WHERE strpos(c.check_sql, md5(p.prosrc)) > 0)
    ORDER BY 2
  LOOP
    IF r.pinned AND r.proname NOT IN ('set_pdc_pit_line_tick_401', 'set_pdc_sublet_line_tick_439') THEN CONTINUE; END IF;
    v_new := regexp_replace(r.prosrc, c_pat, '\1''PT409''', 'gi');
    v_def := regexp_replace(pg_get_functiondef(r.oid), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
    v_done := v_done + 1;
    IF r.pinned THEN
      SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid = r.oid;
      UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_md5, release = 'r677' WHERE prosrc_md5 = r.m;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n <> 1 THEN RAISE EXCEPTION 'r677: pin row for % not moved (%)', r.sig, v_n; END IF;
      v_pins := v_pins + 1;
    END IF;
  END LOOP;
  IF v_done < 45 OR v_pins <> 2 THEN RAISE EXCEPTION 'r677: changed % functions, % pins (expected about 50 and 2)', v_done, v_pins; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r677: pin count changed'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('conflicts_not_retryable_677', 'F287',
    'No staff-facing function raises 40001/40P01 for a business conflict (PostgREST would retry it in a loop).',
    $chk$
SELECT count(*) = 0 AS ok, coalesce(string_agg(p.proname, ', '), 'none') AS detail
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prosrc ~* '(errcode\s*=\s*)''(40001|40P01|serialization_failure|deadlock_detected)'''
  AND n.nspname NOT LIKE 'karratha%'
  AND p.proname NOT IN ('pdc_pilbara_service_apply_v1', 'workshop_clock_tick', 'start_workshop_work_pre_116', 'reconcile_running_growth_20261026')
$chk$, true, 425, 'r677');
  RAISE NOTICE 'r677: % functions now raise PT409; % pins moved', v_done, v_pins;
END $r677$;

DO $post677$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE enabled AND (check_sql ~* 'pit_line_tick|sublet_line_tick|qc_operation|conflicts_not_retryable') LOOP
    EXECUTE r.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r677: check % red: %', r.check_name, detail; END IF;
  END LOOP;
END $post677$;
