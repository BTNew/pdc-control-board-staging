-- r574 (F188) / sort 345. Go-live of #556.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- The preview claimed r566 / F180 / sort 340, then r570 / F184 / sort 341.
-- r566 / F180 was the Electrical bay hide, applied and rolled back.
-- r569 / F183 / sort 340 is the live bay pause.
-- r570 / F184 / sort 341 is service_whole_archive_570 (#544) and is not reused.
-- r573 / F187 / sort 344 is hours_description_fits_573 (#560) and is required first.
-- This check is pmb_dept_ack_book_574 / F188 / sort 345.
--
-- Craig, 27 Oct 2026 09:46 AWST: after a department ticks New to PMB, that
-- department can book the vehicle into one of its bays, then the vehicle
-- leaves that department's list. Other departments that have not ticked still
-- see it. Who ticked, and when, stay on the arrival.
--
-- This file does not replace a booking function and does not write a booking.
-- The board calls the existing planner pair: Best slot is
-- workshopScheduleVehicleNextAvailable, and a chosen bay is
-- workshopFirstAvailableStartSlot plus scheduleWorkshopVehicle (the Schedule
-- window). Those call the existing overlap RPCs.
-- The acknowledgement tables, the key gate, and current_location are not
-- rewritten. Pin count stays 241. Department 135 is not a station.
-- Undo: supabase/rollbacks/20261027200000_r566_pmb_dept_ack_book.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r574: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r574: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r574: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_562' AND fault_id='F176' AND sort_order=335 AND added_in='r562') THEN RAISE EXCEPTION 'r574: r562 / F176 sort 335 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563') THEN RAISE EXCEPTION 'r574: r563 / F177 sort 336 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_557' AND fault_id='F171' AND sort_order=332 AND added_in='r557') THEN RAISE EXCEPTION 'r574: r557 / F171 sort 332 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_job_pause_569' AND fault_id='F183' AND sort_order=340 AND added_in='r569') THEN RAISE EXCEPTION 'r574: r569 / F183 sort 340 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='hours_description_fits_573' AND fault_id='F187' AND sort_order=344 AND added_in='r573') THEN RAISE EXCEPTION 'r574: r573 / F187 sort 344 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=345 OR fault_id='F188' OR check_name='pmb_dept_ack_book_574' OR added_in='r574') THEN RAISE EXCEPTION 'r574: sort 345 or F188 is taken'; END IF;
 IF pg_catalog.to_regclass('public.pdc_pmb_arrival_dept_ack_557') IS NULL
    OR pg_catalog.to_regclass('public.pdc_vehicle_key_assigned_562') IS NULL THEN RAISE EXCEPTION 'r574: acknowledgement or key table is missing'; END IF;
 PERFORM set_config('pdc.r574_pins', (SELECT count(*)::text FROM pdc_ops.expected_function_md5), true);
 PERFORM set_config('pdc.r574_pmb', (SELECT count(*)::text FROM public.vehicles WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, '')))='PMB'), true);
 PERFORM set_config('pdc.r574_ack', (SELECT count(*)::text FROM public.pdc_pmb_arrival_dept_ack_557), true);
 PERFORM set_config('pdc.r574_open', (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL), true);
END $g$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('pmb_dept_ack_book_574', 'F188',
 'New to PMB keeps one acknowledgement per station, with who and when. Booking functions are not replaced by r574. The pin count stays 241. Department 135 is not a station. The check uses search_path pg_catalog, schema-qualified types, and no regprocedure cast.',
 $chk566$
SELECT
  pins.n = 241
  AND added.n = 0
  AND dept.relrowsecurity
  AND uniq.present
  AND cols.who_when
  AND guard.present
  AND ack.present
  AND ack.auth_exec
  AND ack.anon_blocked
  AND ack.keeps_audit
  AND when_at.when_default
  AND ack.no_vehicle_write
  AND ack.no_user_metadata
  AND lst.present
  AND gate.present
  AND book.present
  AND book.not_this_release
  AND stations.fitting
  AND stations.no_dept_135
  AS ok,
  ('pins ' || pins.n::pg_catalog.text || ' | stations ' || coalesce(stations.def, ''::pg_catalog.text)) AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r574') added
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_pmb_arrival_dept_ack_557'
) dept
CROSS JOIN (
  SELECT count(*) > 0 AS present
  FROM pg_catalog.pg_constraint c
  JOIN pg_catalog.pg_class rel ON rel.oid = c.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = rel.relnamespace
  WHERE n.nspname = 'public' AND rel.relname = 'pdc_pmb_arrival_dept_ack_557' AND c.contype = 'u'
    AND pg_catalog.strpos(pg_catalog.pg_get_constraintdef(c.oid), 'arrival_id') > 0
    AND pg_catalog.strpos(pg_catalog.pg_get_constraintdef(c.oid), 'station_code') > 0
) uniq
CROSS JOIN (
  SELECT count(*) = 4 AS who_when
  FROM pg_catalog.pg_attribute a
  JOIN pg_catalog.pg_class rel ON rel.oid = a.attrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = rel.relnamespace
  WHERE n.nspname = 'public' AND rel.relname = 'pdc_pmb_arrival_dept_ack_557'
    AND a.attname IN ('acknowledged_at', 'acknowledged_by', 'acknowledged_by_email', 'acknowledged_by_name')
    AND a.attnotnull AND NOT a.attisdropped
) cols
CROSS JOIN (
  SELECT count(*) > 0 AS present
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_pmb_arrival_dept_ack_557'
    AND t.tgname = 'pdc_pmb_arrival_dept_ack_557_guard' AND NOT t.tgisinternal
) guard
CROSS JOIN (
  SELECT count(*) > 0 AS present,
    coalesce(bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE')), false) AS auth_exec,
    coalesce(bool_and(NOT has_function_privilege('anon', p.oid, 'EXECUTE')), false) AS anon_blocked,
    coalesce(bool_and(
      pg_catalog.strpos(p.prosrc, 'acknowledged_by') > 0
      AND pg_catalog.strpos(p.prosrc, 'acknowledged_by_email') > 0
      AND pg_catalog.strpos(p.prosrc, 'acknowledged_by_name') > 0
    ), false) AS keeps_audit,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_write,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'user_metadata') = 0), false) AS no_user_metadata
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'acknowledge_pmb_arrival_557'
) ack
CROSS JOIN (
  SELECT count(*) > 0 AS present
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'list_pmb_arrival_ack_557'
) lst
CROSS JOIN (
  SELECT count(*) > 0 AS present
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'push_new_to_pmb_562'
) gate
CROSS JOIN (
  SELECT count(DISTINCT p.proname) = 3 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'r574') = 0), false) AS not_this_release
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('workshop_create_booking', 'schedule_vehicle_work', 'administrator_schedule_workshop_vehicle')
) book
CROSS JOIN (
  SELECT coalesce(bool_or(pg_catalog.strpos(pg_catalog.pg_get_constraintdef(c.oid), 'FITTING') > 0), false) AS fitting,
    coalesce(bool_and(pg_catalog.strpos(pg_catalog.pg_get_constraintdef(c.oid), '135') = 0), false) AS no_dept_135,
    coalesce(pg_catalog.left(pg_catalog.string_agg(pg_catalog.pg_get_constraintdef(c.oid), ' | '), 180), ''::pg_catalog.text) AS def
  FROM pg_catalog.pg_constraint c
  JOIN pg_catalog.pg_class rel ON rel.oid = c.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = rel.relnamespace
  WHERE n.nspname = 'public' AND rel.relname = 'pdc_pmb_arrival_dept_ack_557' AND c.contype = 'c'
) stations
CROSS JOIN (
  SELECT count(*) = 1 AS when_default
  FROM pg_catalog.pg_attrdef d
  JOIN pg_catalog.pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
  JOIN pg_catalog.pg_class rel ON rel.oid = a.attrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = rel.relnamespace
  WHERE n.nspname = 'public' AND rel.relname = 'pdc_pmb_arrival_dept_ack_557'
    AND a.attname = 'acknowledged_at'
    AND pg_catalog.strpos(pg_catalog.pg_get_expr(d.adbin, d.adrelid), 'clock_timestamp') > 0
) when_at
$chk566$, true, 345, 'r574');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r574: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r574') THEN RAISE EXCEPTION 'r574: a pin was inserted'; END IF;
 IF current_setting('pdc.r574_pmb', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.vehicles WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, '')))='PMB') THEN RAISE EXCEPTION 'r574: PMB vehicle count changed'; END IF;
 IF current_setting('pdc.r574_ack', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.pdc_pmb_arrival_dept_ack_557) THEN RAISE EXCEPTION 'r574: acknowledgement rows changed'; END IF;
 IF current_setting('pdc.r574_open', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL) THEN RAISE EXCEPTION 'r574: open New to PMB count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='pmb_dept_ack_book_574' AND fault_id='F188' AND sort_order=345 AND added_in='r574' AND enabled)<>1 THEN RAISE EXCEPTION 'r574: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog', true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='pmb_dept_ack_book_574' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r574: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
