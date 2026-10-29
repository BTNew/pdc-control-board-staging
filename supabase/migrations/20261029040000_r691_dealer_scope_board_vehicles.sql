-- r691 (F301) / sort 445. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 08:20: 62+ vehicles on the PMG board (Pilbara Service job cards, Navision dealer 001234 or 002345,
-- or no Navision record) could not have hours saved by anyone: save_vehicle_workshop_line_hours_batch_768 asked the
-- dealer check for the vehicle's own dealer, which is empty for these, so it returned dealer_scope_denied.
-- The save now asks for the vehicle's dealer, else the actor's board dealer, and the dealer check (pinned) lets a
-- 14450 board actor through for an active vehicle that is on the board through Pilbara Service operations and has no
-- single 14450/37047 Navision record. Writes still need the operator role (save checks it). Pins move to r691.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

CREATE TEMP TABLE r691_green ON COMMIT DROP AS SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE false;
DO $pre691$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE enabled AND check_sql ~* 'hours_batch_768|actor_vehicle_allowed' LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; END;
    IF ok IS TRUE THEN INSERT INTO r691_green VALUES (r.check_name, r.check_sql); END IF;
  END LOOP;
END $pre691$;

DO $r691$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_save text := 'save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)';
  c_allow text := 'pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)';
  c_s1 text := 'pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,v_vehicle_dealer)';
  c_a1 text := E'  v_vehicle_dealer:=public.pdc_auditor_vehicle_dealer(p_vehicle_id);\n';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r691: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r691: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r691: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 445 OR fault_id = 'F301' OR added_in = 'r691' OR check_name = 'dealer_scope_board_vehicles_691') THEN RAISE EXCEPTION 'r691: sort 445 or F301 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r691: an import job is running'; END IF;

  -- 1. the save asks for the vehicle's dealer, else the actor's board dealer
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = ('public.' || c_save)::regprocedure;
  IF md5(v_old) <> '8255bcf5461babcc01714481fcd8cbe0' THEN RAISE EXCEPTION 'r691: hours save is not the pinned text'; END IF;
  IF (length(v_old) - length(replace(v_old, c_s1, ''))) / length(c_s1) <> 1 THEN RAISE EXCEPTION 'r691: save anchor not found once'; END IF;
  v_new := replace(v_old, c_s1, 'pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,coalesce(v_vehicle_dealer,v_scope->>''dealer_code'')) /* r691 */');
  v_def := regexp_replace(pg_get_functiondef(('public.' || c_save)::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid = ('public.' || c_save)::regprocedure;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_md5, release = 'r691' WHERE prosrc_md5 = '8255bcf5461babcc01714481fcd8cbe0';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r691: save pin not moved (%)', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, '8255bcf5461babcc01714481fcd8cbe0', v_md5) WHERE strpos(check_sql, '8255bcf5461babcc01714481fcd8cbe0') > 0;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'batch.release = ''r573''', 'batch.release = ''r691''') WHERE check_name = 'hours_description_fits_573';

  -- 2. the dealer check lets the 14450 board actor through for PMG-board vehicles with no single 14450/37047 record
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = ('public.' || c_allow)::regprocedure;
  IF md5(v_old) <> '47c743a8c0a8eebf176a3b5485b0bf98' THEN RAISE EXCEPTION 'r691: dealer check is not the pinned text'; END IF;
  IF (length(v_old) - length(replace(v_old, c_a1, ''))) / length(c_a1) <> 1 THEN RAISE EXCEPTION 'r691: dealer anchor not found once'; END IF;
  v_new := replace(v_old, c_a1,
       E'  -- r691 (F301): a vehicle on the PMG board through Pilbara Service job cards with no single 14450/37047 Navision\n'
    || E'  -- record (dealer 001234/002345 or none) belongs to the 14450 board.\n'
    || E'  IF p_scope->>''dealer_code''=''14450'' AND v_requested_dealer=''14450'' AND public.pdc_auditor_vehicle_dealer(p_vehicle_id) IS NULL\n'
    || E'     AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN public.vehicles v ON v.id=o.vehicle_id\n'
    || E'                WHERE o.vehicle_id=p_vehicle_id AND v.lifecycle_state=''active'' AND v.deleted_at IS NULL) THEN RETURN true; END IF;\n'
    || c_a1);
  v_def := regexp_replace(pg_get_functiondef(('public.' || c_allow)::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid = ('public.' || c_allow)::regprocedure;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_md5, release = 'r691' WHERE prosrc_md5 = '47c743a8c0a8eebf176a3b5485b0bf98';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r691: dealer pin not moved (%)', v_n; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r691: pin count changed'; END IF;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('dealer_scope_board_vehicles_691', 'F301',
    'Hours can be saved for PMG-board vehicles whose Navision dealer is 001234/002345 or missing.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)')), 'coalesce(v_vehicle_dealer,v_scope->>''dealer_code'')') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)')), 'r691 (F301)') > 0
 AS ok, 'board vehicles without a 14450/37047 record can save hours' AS detail
$chk$, true, 445, 'r691');
END $r691$;

DO $post691$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT g.check_name, c.check_sql FROM r691_green g JOIN pdc_ops.regression_checks c USING (check_name)
           UNION ALL SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name = 'dealer_scope_board_vehicles_691' LOOP
    EXECUTE r.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r691: check % red: %', r.check_name, detail; END IF;
  END LOOP;
END $post691$;
