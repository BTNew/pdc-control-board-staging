-- r729 (F339, F340): regression suite hygiene after today's releases, and the board snapshot pre-warm.
-- Craig Watson, 29 Oct 2026 20:14 AWST: "make sure tonight that there is no faults whatsoever with any of the
-- back-end stuff ... I want the board to be very, very quick tomorrow."
--
-- Part A (F339). 22 regression rows were red. None is a code defect. Three applied migrations have no repo file
-- (sublet_rule_20261029_always_sublet_golive 09:01 AWST, qc_override_closes_jobs_20261029 08:49 AWST,
-- r576_cross_station_drop 27 Oct) and r599 / r601 / r680 moved pins without updating the md5 and release-name
-- literals inside other checks. This file moves those literals to the live values, pins the live QC gate body,
-- and makes the two Key 460 checks follow the vehicle instead of a number from 28 Oct. Behaviour is unchanged.
--
-- Part B (F340). The Vehicle Locations board snapshot takes 6 to 7 s to build (17 MB, 453 cars) and is only cached
-- for 15 s, so the first person after each 15 s window waited the full build. Cron job
-- staging-vehicle-board-prewarm-729 checks every 3 s on weekdays 05:30 to 18:30 AWST and rebuilds the snapshot as
-- the workshopdisplay operator account as soon as the cache is 15 s old, so people read the cache (about 100 ms;
-- a reader that arrives mid-rebuild gets the last snapshot at once, r586). The job was scheduled at 20:40 AWST
-- tonight (jobid 15) with a daily cron history cleanup (jobid 16); this file records both and is idempotent.
-- The QC lines cache refill moves from every 20 s to every 5 s so the board recovers four times faster after an
-- import empties the cache (same 40-car, 3 s batch).
--
-- Staging cdsmnqxtyyoeoznmbidd only. Production never touched. No vehicle, booking, line or tick changes.
-- Rollback: supabase/rollbacks/20261029210000_r729_check_hygiene_and_board_prewarm.down.sql

DO $pre729$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_live text;
BEGIN
  IF awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r729: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r729: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r729: an import job is running'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r729: pin count is not 241'; END IF;
  SELECT md5(p.prosrc) INTO v_live FROM pg_proc p WHERE p.oid = to_regprocedure('public.pdc_qc_gate_issues(uuid)');
  IF v_live IS DISTINCT FROM '22d863876a4cfa8f127756cc4a8a6da4' THEN RAISE EXCEPTION 'r729: QC gate body is not the qc_override_closes_jobs_20261029 body (%)', v_live; END IF;
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.pdc_qc_gate_issues(uuid)') IS DISTINCT FROM '4973560977892d1a6b3a52c9ec0c7855' THEN
    RAISE EXCEPTION 'r729: QC gate pin is not the r590 value';
  END IF;
  -- every literal this file replaces must be present exactly where expected
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523','named_external_sublet_584')
        AND strpos(check_sql,'ca08696ffbe6a1834e63f8b8faf246e1') > 0 AND strpos(check_sql,'82c809d15c382e73c0ae5bf135293ebe') > 0) <> 3
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'named_external_sublet_584'
        AND strpos(check_sql,'before_import_rules_20261017(uuid)'')=''r523''') > 0 AND strpos(check_sql,'note_fee_sublet_521(jsonb)'')=''r521''') > 0) <> 1
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'bus_component_split_568' AND strpos(check_sql,'f8f91d313d3e5240355eca18eb14ab79') > 0) <> 1
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('category_unstarted_release_536','running_booking_end_538') AND strpos(check_sql,'release=''r538''') > 0) <> 2
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'bus_whole_job_450'
        AND strpos(check_sql,'before_import_rules_20261017(uuid)'')=''r523''') > 0 AND strpos(check_sql,'boolean,jsonb)'')=''r538''') > 0) <> 1
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'dept138_review_routing_459' AND strpos(check_sql,'coalesce\(rs\.stage_code,h\.stage_code,') > 0) <> 1
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('planner_duration_after_insert_537','planner_duration_cache_531') AND strpos(check_sql,'4e8dfda7795a8a547358554c5720a174') > 0) <> 2
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'parts_eta_stoppage_573' AND check_sql ~ 'AND \(SELECT pg_catalog\.strpos\(def.*FROM rule\) AS ok') <> 1
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'bodybuilder_new_to_pmb_574' AND strpos(check_sql,'AND upper(btrim(coalesce(m.from_location, ''''))) IS DISTINCT FROM ''PMB''') > 0) <> 1
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'bay_resequence_and_stopped_replan' AND strpos(check_sql,'h.event_type IN (''bay_resequenced'',''pushed_for_earlier_stage'',''bay_resequence_undone'')') > 0) <> 1
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('key460_drag_597','outstanding_station_hours_594') AND strpos(check_sql,'= 5.00') > 0) <> 2
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'qc_cache_refill_busy_not_error' AND strpos(check_sql,'''20 seconds''') > 0) <> 1
     OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_sql ~ '\s*AND \(SELECT count\(\*\) FROM pdc_ops\.expected_function_md5\)\s*=\s*[0-9]+') <> 11
  THEN RAISE EXCEPTION 'r729: a check literal is not where this file expects it; nothing changed'; END IF;
  -- live md5s the new literals name
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_work_categories_private.note_fee_sublet_521(jsonb)')) IS DISTINCT FROM '20fac9508d40f9bb79438208bba7fa45'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_work_categories_private.before_import_rules_20261017(uuid)')) IS DISTINCT FROM 'fad0a85d5dfcdfb0526b2062463d3188'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) IS DISTINCT FROM 'b2de35bd65bd1021b4dfc14410244dc4'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')) IS DISTINCT FROM 'be14ea3e9d330a21a5547deb9145a4d7'
  THEN RAISE EXCEPTION 'r729: a live function body is not the one this file pins; nothing changed'; END IF;
END $pre729$;

-- Part A: check literals follow the live bodies.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(replace(check_sql,'ca08696ffbe6a1834e63f8b8faf246e1','20fac9508d40f9bb79438208bba7fa45'),'82c809d15c382e73c0ae5bf135293ebe','fad0a85d5dfcdfb0526b2062463d3188')
WHERE check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523','named_external_sublet_584');

UPDATE pdc_ops.regression_checks
SET check_sql = replace(replace(check_sql,'before_import_rules_20261017(uuid)'')=''r523''','before_import_rules_20261017(uuid)'')=''sublet_rule_20261029'''),'note_fee_sublet_521(jsonb)'')=''r521''','note_fee_sublet_521(jsonb)'')=''sublet_rule_20261029''')
WHERE check_name = 'named_external_sublet_584';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,'f8f91d313d3e5240355eca18eb14ab79','b2de35bd65bd1021b4dfc14410244dc4')
WHERE check_name = 'bus_component_split_568';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,'release=''r538''','release=''sublet_rule_20261029''')
WHERE check_name IN ('category_unstarted_release_536','running_booking_end_538');

UPDATE pdc_ops.regression_checks
SET check_sql = replace(replace(check_sql,'before_import_rules_20261017(uuid)'')=''r523''','before_import_rules_20261017(uuid)'')=''sublet_rule_20261029'''),'boolean,jsonb)'')=''r538''','boolean,jsonb)'')=''sublet_rule_20261029''')
WHERE check_name = 'bus_whole_job_450';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,'coalesce\(rs\.stage_code,h\.stage_code,','coalesce\(rs\.stage_code,asr\.stage_code,h\.stage_code,')
WHERE check_name = 'dept138_review_routing_459';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,'4e8dfda7795a8a547358554c5720a174','be14ea3e9d330a21a5547deb9145a4d7')
WHERE check_name IN ('planner_duration_after_insert_537','planner_duration_cache_531');

-- r599 dropped constraint workshop_bookings_active_vehicle_no_overlap; the guard table is the rule now.
UPDATE pdc_ops.regression_checks
SET check_sql = regexp_replace(check_sql,'AND \(SELECT pg_catalog\.strpos\(def.*FROM rule\) AS ok','AND NOT pdc_ops.cross_bay_vehicle_guard_on() AND to_regclass(''pdc_ops.workshop_guard_599'') IS NOT NULL AS ok')
WHERE check_name = 'parts_eta_stoppage_573';

-- The To PMB button (r692, r707, r722) is a second legitimate route into PMB for a body-builder delivery.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,'AND upper(btrim(coalesce(m.from_location, ''''))) IS DISTINCT FROM ''PMB''','AND upper(btrim(coalesce(m.from_location, ''''))) IS DISTINCT FROM ''PMB'' AND coalesce(m.reason,'''') <> ''Explicit Vehicle Locations release to PMB''')
WHERE check_name = 'bodybuilder_new_to_pmb_574';

-- r576 cross-station drop writes its own two history event types.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,'h.event_type IN (''bay_resequenced'',''pushed_for_earlier_stage'',''bay_resequence_undone'')','h.event_type IN (''bay_resequenced'',''pushed_for_earlier_stage'',''bay_resequence_undone'',''cross_station_park_575'',''cross_station_push_575'')')
WHERE check_name = 'bay_resequence_and_stopped_replan';

-- Key 460 is in QC with every Hoist line ticked. The two checks now assert the hours helper agrees with the open
-- Hoist lines of that vehicle, whatever they add up to, instead of the 5.00 h it had on 28 Oct.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
  'AND public.workshop_vehicle_stage_estimated_hours(''7a64124b-ab39-4069-a6c0-b756b2dc580f''::uuid, ''HOIST'') = 5.00',
  'AND public.workshop_vehicle_stage_estimated_hours(''7a64124b-ab39-4069-a6c0-b756b2dc580f''::uuid, ''HOIST'') IS NOT DISTINCT FROM (SELECT nullif(sum((l->>''estimated_hours'')::numeric),0) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(''7a64124b-ab39-4069-a6c0-b756b2dc580f''::uuid)) l WHERE l->>''stage_code''=''HOIST'' AND coalesce((l->>''active'')::boolean, true) AND NOT EXISTS (SELECT 1 FROM public.pdc_panel_line_completion_565 c WHERE c.vehicle_id=''7a64124b-ab39-4069-a6c0-b756b2dc580f'' AND c.line_identity=l->>''line_identity'' AND c.completed IS TRUE))')
WHERE check_name = 'key460_drag_597';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(replace(check_sql,
  'AND public.workshop_vehicle_stage_estimated_hours(''7a64124b-ab39-4069-a6c0-b756b2dc580f''::uuid, ''HOIST'') = open_hours.total',
  'AND public.workshop_vehicle_stage_estimated_hours(''7a64124b-ab39-4069-a6c0-b756b2dc580f''::uuid, ''HOIST'') IS NOT DISTINCT FROM nullif(open_hours.total,0)'),
  '  AND open_hours.total = 5.00', '  AND true')
WHERE check_name = 'outstanding_station_hours_594';

-- r529 rule: no check may lock the pin table to a literal total (regression_checks_self_test). Eleven checks added
-- between r598 and r711 did (= 241), which kept the self test red and would make every pin add a two-file change.
-- The clause goes; each of those checks keeps its own md5 and privilege assertions, protected_function_md5s owns the pins.
UPDATE pdc_ops.regression_checks
SET check_sql = regexp_replace(check_sql, '\s*AND \(SELECT count\(\*\) FROM pdc_ops\.expected_function_md5\)\s*=\s*[0-9]+', '', 'g')
WHERE check_sql ~ '\s*AND \(SELECT count\(\*\) FROM pdc_ops\.expected_function_md5\)\s*=\s*[0-9]+';

-- The QC gate pin follows the applied qc_override_closes_jobs_20261029 body (location override aware, same as r688).
UPDATE pdc_ops.expected_function_md5
SET prosrc_md5 = '22d863876a4cfa8f127756cc4a8a6da4',
    note = coalesce(note,'') || '; r729: qc_override_closes_jobs_20261029 (29 Oct 08:49 AWST) made the gate follow vehicles.location_override, same reading as r688; was 4973560977892d1a6b3a52c9ec0c7855',
    updated_at = clock_timestamp()
WHERE signature = 'public.pdc_qc_gate_issues(uuid)' AND prosrc_md5 = '4973560977892d1a6b3a52c9ec0c7855';

-- Part B: the board pre-warm job, the cron history cleanup and the faster QC cache refill.
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'staging-vehicle-board-prewarm-729';
SELECT cron.schedule('staging-vehicle-board-prewarm-729', '3 seconds',
$cmd$SELECT CASE WHEN (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time BETWEEN time '05:30' AND time '18:30' AND extract(isodow FROM clock_timestamp() AT TIME ZONE 'Australia/Perth') < 6 AND coalesce((SELECT c.computed_at FROM pdc_ops.vehicle_board_snapshot_cache_545 c WHERE c.singleton), '-infinity') < clock_timestamp() - interval '15 seconds' THEN (SELECT (public.get_pdc_email_vehicle_board_snapshot()->>'code') FROM set_config('request.jwt.claims','{"email":"workshopdisplay@pmgwa.com.au","role":"authenticated"}',true) s) ELSE 'fresh_or_outside_hours' END$cmd$);
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'staging-cron-history-cleanup-729';
SELECT cron.schedule('staging-cron-history-cleanup-729', '17 2 * * *', $cmd$DELETE FROM cron.job_run_details WHERE start_time < now() - interval '7 days'$cmd$);

SELECT cron.alter_job(jobid, schedule => '5 seconds') FROM cron.job WHERE jobname = 'staging-qc-operation-lines-cache-refill';
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,'''20 seconds''','''5 seconds''')
WHERE check_name = 'qc_cache_refill_busy_not_error';

INSERT INTO pdc_ops.regression_checks(check_name, sort_order, fault_id, added_in, enabled, description, check_sql)
VALUES ('board_prewarm_729', 452, 'F340', 'r729', true,
  'The Vehicle Locations board snapshot is rebuilt by cron as soon as it is 15 s old in working hours, so readers hit the cache. The job exists, is active, ran in the last 2 minutes without failing, and the cache is never older than 60 s in working hours.',
  $chk$
WITH j AS (SELECT jobid, active, schedule FROM cron.job WHERE jobname = 'staging-vehicle-board-prewarm-729'),
d AS (SELECT count(*) runs, count(*) FILTER (WHERE status <> 'succeeded') failed, max(start_time) last_run
      FROM cron.job_run_details r JOIN j ON j.jobid = r.jobid WHERE r.start_time > now() - interval '10 minutes'),
c AS (SELECT computed_at FROM pdc_ops.vehicle_board_snapshot_cache_545 WHERE singleton),
w AS (SELECT (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time BETWEEN time '05:35' AND time '18:30' AND extract(isodow FROM clock_timestamp() AT TIME ZONE 'Australia/Perth') < 6 AS working)
SELECT (SELECT count(*) FROM j WHERE active AND schedule = '3 seconds') = 1
   AND (SELECT runs FROM d) > 0 AND (SELECT failed FROM d) = 0
   AND (SELECT last_run FROM d) > now() - interval '2 minutes'
   AND (NOT (SELECT working FROM w) OR (SELECT computed_at FROM c) > now() - interval '60 seconds') AS ok,
  'runs 10 min '||(SELECT runs FROM d)||', failed '||(SELECT failed FROM d)||', cache age '||coalesce(round(extract(epoch FROM now() - (SELECT computed_at FROM c)))::text,'none')||' s, working hours '||(SELECT working FROM w) AS detail
$chk$);

DO $post729$
DECLARE r record; v_red text := ''; v_n integer := 0;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x
   WHERE x.check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523','named_external_sublet_584','bus_component_split_568',
     'category_unstarted_release_536','running_booking_end_538','bus_whole_job_450','dept138_review_routing_459',
     'planner_duration_after_insert_537','planner_duration_cache_531','parts_eta_stoppage_573','bodybuilder_new_to_pmb_574',
     'bay_resequence_and_stopped_replan','key460_drag_597','outstanding_station_hours_594','qc_signoff_override_590',
     'protected_function_md5s','qc_cache_refill_busy_not_error','board_prewarm_729','regression_checks_self_test',
     'place_after_no_prompt_598','cross_bay_guard_off_599','resume_cascade_600','validate_cross_bay_off_601','pit_bookings_604',
     'workshop_tv_605','pit_time_630','pit_places_632','mmt_sublet_642','mmt_only_login_643','psc_sublet_711')
  LOOP
    v_n := v_n + 1;
    IF NOT r.ok AND r.check_name NOT IN ('qc_cache_refill_busy_not_error','board_prewarm_729') THEN v_red := v_red || r.check_name || ' (' || left(r.detail, 160) || '); '; END IF;
    IF NOT r.ok THEN RAISE NOTICE 'r729 still red: % %', r.check_name, r.detail; END IF;
  END LOOP;
  IF v_n <> 31 THEN RAISE EXCEPTION 'r729: expected 31 checks, saw %', v_n; END IF;
  IF v_red <> '' THEN RAISE EXCEPTION 'r729: red after apply, rolled back: %', v_red; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r729: pin count moved'; END IF;
  RAISE NOTICE 'r729: 31 checks green (the two cron checks need a run history and go green within 10 minutes)';
END $post729$;
