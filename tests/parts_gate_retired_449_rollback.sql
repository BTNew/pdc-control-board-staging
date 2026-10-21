-- r449 (F62) rolled-back test: apply -> check -> undo -> re-apply, then everything is rolled back (R449_RB_RESULT).
-- No booking, vehicle or line is read as a fixture or written; the only writes are the release rows, all rolled back.
-- Rolled-back release test window (F15, r405). Paste at the very top of every rolled-back test
-- that calls board write functions, and replace R449 with the release tag (e.g. R405).
--
-- Why: board write functions take the top-level change lock
-- (pg_advisory_xact_lock('pdc:workshop:top-level-mutation')) and keep it until the test's
-- ROLLBACK. The live clock tick runs every minute at :00 and waits only 3 s for that lock
-- (lock_timeout), so a test that holds it across a minute boundary makes the real tick fail
-- (21:25, 21:28 and 21:30 AWST on 20 Oct 2026, r404 tests).
--
-- Rule: 1) wait until this minute's tick has finished, 2) start between :02 and :15,
-- 3) never wait long for a live lock (lock_timeout 2 s), 4) stop and roll back before :50
-- (each statement's statement_timeout is cut to the time left; call pg_temp.deadline() before
-- each step). Locks are only taken after step 1, so waiting holds nothing.

-- 1+2. Wait for the tick (holds no locks; reads cron history only).
DO $window_wait$
DECLARE i integer := 0;
BEGIN
  LOOP
    EXIT WHEN extract(second FROM clock_timestamp()) BETWEEN 2 AND 15
      AND EXISTS (SELECT 1 FROM cron.job_run_details d JOIN cron.job j USING (jobid)
                  WHERE j.jobname = 'staging-workshop-clock-cascade'
                    AND d.start_time >= date_trunc('minute', clock_timestamp())
                    AND d.end_time IS NOT NULL);
    i := i + 1;
    IF i > 75 THEN RAISE EXCEPTION 'R449_WINDOW: clock tick not seen; test not started'; END IF;
    PERFORM pg_sleep(1);
  END LOOP;
END $window_wait$;

BEGIN;
-- 3. Never queue behind live work.
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '40s';
CREATE TEMP TABLE t_window ON COMMIT DROP AS
  SELECT clock_timestamp() AS started, date_trunc('minute', clock_timestamp()) + interval '50 seconds' AS deadline;
-- 4. Call before each step: stops the test (rolled back) if it would reach the next tick.
CREATE FUNCTION pg_temp.deadline() RETURNS void LANGUAGE plpgsql AS $window_fn$
DECLARE left_ms integer;
BEGIN
  left_ms := floor(extract(epoch FROM (SELECT deadline FROM t_window) - clock_timestamp()) * 1000);
  IF left_ms < 1000 THEN
    RAISE EXCEPTION 'R449_DEADLINE: stopped before the next clock tick; everything rolled back';
  END IF;
  PERFORM set_config('statement_timeout', least(left_ms, 40000)::text || 'ms', true);
END $window_fn$;
CREATE FUNCTION pg_temp.window_report() RETURNS jsonb LANGUAGE sql AS $window_fn$
  SELECT jsonb_build_object(
    'started_awst', to_char(started AT TIME ZONE 'Australia/Perth', 'HH24:MI:SS.MS'),
    'now_awst', to_char(clock_timestamp() AT TIME ZONE 'Australia/Perth', 'HH24:MI:SS.MS'),
    'same_minute', date_trunc('minute', started) = date_trunc('minute', clock_timestamp()),
    'seconds', round(extract(epoch FROM clock_timestamp() - started)::numeric, 2))
  FROM t_window $window_fn$;
CREATE TEMP TABLE r449_t ON COMMIT DROP AS SELECT (SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5) pins0, (SELECT md5(string_agg(check_name||':'||md5(check_sql)||':'||enabled::text||':'||sort_order,',' ORDER BY check_name)) FROM pdc_ops.regression_checks) checks0, '{}'::jsonb res;
SELECT pg_temp.deadline();
-- r449 (F62, Bhavesh 21 Oct 18:19 "Retired parts check: some leftover parts-readiness messages still appear" - "suggest what can be
-- done for flexibility", approved by Craig): parts readiness stopped gating bookings and starts in r415
-- (public.workshop_parts_ready is "select true"). The leftover messages were all in the page (planner, fitter screen); this
-- release removes them there. No database function returns a retired parts code any more, so nothing in the database changes:
-- this migration only adds check parts_gate_retired_449 (sort 248) so a parts gate cannot quietly come back on the booking and
-- start paths. Old archived functions (*_pre_NNN) and the snapshot's parts_readiness data are left alone. No pins move.
-- Not touched: workshop_clock_tick, any booking, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r449: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r449: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r449: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r449: fault_regression_check changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449' OR added_in='r449') THEN RAISE EXCEPTION 'r449: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=248) THEN RAISE EXCEPTION 'r449: sort_order 248 taken'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r448') THEN RAISE EXCEPTION 'r449: r448 is not applied'; END IF;
END $g$;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('parts_gate_retired_449','F62','Parts readiness stays retired (r415, r449): workshop_parts_ready is always true and none of the 8 booking/start paths returns a retired parts code (bus_stage_parts_required, stage_parts_not_ready, parts_incomplete_entry)',
  $chk$WITH want(sig) AS (VALUES
  ('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'),
  ('public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'),
  ('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'),
  ('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'),
  ('public.book_all_vehicle_stations(uuid,integer)'),
  ('public.start_workshop_work(uuid,integer,timestamptz,jsonb)'),
  ('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'),
  ('pdc_bus_private.booking_rule(uuid,uuid,uuid)')),
f AS (SELECT w.sig,p.prosrc FROM want w LEFT JOIN pg_proc p ON p.oid=to_regprocedure(w.sig)),
pr AS (SELECT btrim(prosrc) src FROM pg_proc WHERE oid=to_regprocedure('public.workshop_parts_ready(uuid)'))
SELECT count(*) FILTER (WHERE prosrc IS NULL)=0
  AND count(*) FILTER (WHERE prosrc ~ '(bus_stage_parts_required|stage_parts_not_ready|parts_incomplete_entry)')=0
  AND (SELECT src FROM pr)='select true' AS ok,
 'Parts readiness retired (r415, r449): workshop_parts_ready '||coalesce(CASE WHEN (SELECT src FROM pr)='select true' THEN 'always true' ELSE 'GATES AGAIN: '||left((SELECT src FROM pr),40) END,'MISSING')
 ||'; booking/start paths checked: '||count(*) FILTER (WHERE prosrc IS NOT NULL)||'/8'
 ||coalesce('; MISSING '||string_agg(sig,', ') FILTER (WHERE prosrc IS NULL),'')
 ||'; returning a retired parts code: '||coalesce(string_agg(sig,', ') FILTER (WHERE prosrc ~ '(bus_stage_parts_required|stage_parts_not_ready|parts_incomplete_entry)'),'none') AS detail
FROM f$chk$,true,248,'r449');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449' AND added_in='r449')<>'c23f4b2abb9071d1b2c347652f3c38a1' THEN RAISE EXCEPTION 'r449: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r449: check parts_gate_retired_449 not OK: %',x.detail; END IF;
END $g$;
SELECT pg_temp.deadline();
DO $a$ DECLARE x record; BEGIN
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 UPDATE r449_t SET res=jsonb_build_object('check_ok',x.ok,'check',x.detail,'pins_unchanged',(SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5)=pins0,'checks1',(SELECT md5(string_agg(check_name||':'||md5(check_sql)||':'||enabled::text||':'||sort_order,',' ORDER BY check_name)) FROM pdc_ops.regression_checks)) WHERE true;
END $a$;
SELECT pg_temp.deadline();
-- r449 undo (F62): removes check parts_gate_retired_449. Nothing else in the database changed. Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r449 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r449 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r449 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r449 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449' AND added_in='r449') IS DISTINCT FROM 'c23f4b2abb9071d1b2c347652f3c38a1' THEN RAISE EXCEPTION 'r449 undo: check is not the r449 version; nothing removed'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449' AND added_in='r449';

DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r449' OR sort_order=248) THEN RAISE EXCEPTION 'r449 undo: check not removed'; END IF;
END $g$;
SELECT pg_temp.deadline();
UPDATE r449_t SET res=res||jsonb_build_object('undone_checks_equal_before',(SELECT md5(string_agg(check_name||':'||md5(check_sql)||':'||enabled::text||':'||sort_order,',' ORDER BY check_name)) FROM pdc_ops.regression_checks)=checks0,'undone_pins_unchanged',(SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5)=pins0) WHERE true;
-- r449 (F62, Bhavesh 21 Oct 18:19 "Retired parts check: some leftover parts-readiness messages still appear" - "suggest what can be
-- done for flexibility", approved by Craig): parts readiness stopped gating bookings and starts in r415
-- (public.workshop_parts_ready is "select true"). The leftover messages were all in the page (planner, fitter screen); this
-- release removes them there. No database function returns a retired parts code any more, so nothing in the database changes:
-- this migration only adds check parts_gate_retired_449 (sort 248) so a parts gate cannot quietly come back on the booking and
-- start paths. Old archived functions (*_pre_NNN) and the snapshot's parts_readiness data are left alone. No pins move.
-- Not touched: workshop_clock_tick, any booking, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r449: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r449: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r449: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r449: fault_regression_check changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449' OR added_in='r449') THEN RAISE EXCEPTION 'r449: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=248) THEN RAISE EXCEPTION 'r449: sort_order 248 taken'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r448') THEN RAISE EXCEPTION 'r449: r448 is not applied'; END IF;
END $g$;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('parts_gate_retired_449','F62','Parts readiness stays retired (r415, r449): workshop_parts_ready is always true and none of the 8 booking/start paths returns a retired parts code (bus_stage_parts_required, stage_parts_not_ready, parts_incomplete_entry)',
  $chk$WITH want(sig) AS (VALUES
  ('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'),
  ('public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'),
  ('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'),
  ('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'),
  ('public.book_all_vehicle_stations(uuid,integer)'),
  ('public.start_workshop_work(uuid,integer,timestamptz,jsonb)'),
  ('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'),
  ('pdc_bus_private.booking_rule(uuid,uuid,uuid)')),
f AS (SELECT w.sig,p.prosrc FROM want w LEFT JOIN pg_proc p ON p.oid=to_regprocedure(w.sig)),
pr AS (SELECT btrim(prosrc) src FROM pg_proc WHERE oid=to_regprocedure('public.workshop_parts_ready(uuid)'))
SELECT count(*) FILTER (WHERE prosrc IS NULL)=0
  AND count(*) FILTER (WHERE prosrc ~ '(bus_stage_parts_required|stage_parts_not_ready|parts_incomplete_entry)')=0
  AND (SELECT src FROM pr)='select true' AS ok,
 'Parts readiness retired (r415, r449): workshop_parts_ready '||coalesce(CASE WHEN (SELECT src FROM pr)='select true' THEN 'always true' ELSE 'GATES AGAIN: '||left((SELECT src FROM pr),40) END,'MISSING')
 ||'; booking/start paths checked: '||count(*) FILTER (WHERE prosrc IS NOT NULL)||'/8'
 ||coalesce('; MISSING '||string_agg(sig,', ') FILTER (WHERE prosrc IS NULL),'')
 ||'; returning a retired parts code: '||coalesce(string_agg(sig,', ') FILTER (WHERE prosrc ~ '(bus_stage_parts_required|stage_parts_not_ready|parts_incomplete_entry)'),'none') AS detail
FROM f$chk$,true,248,'r449');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449' AND added_in='r449')<>'c23f4b2abb9071d1b2c347652f3c38a1' THEN RAISE EXCEPTION 'r449: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_gate_retired_449') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r449: check parts_gate_retired_449 not OK: %',x.detail; END IF;
END $g$;
SELECT pg_temp.deadline();
DO $c$ DECLARE r jsonb; BEGIN
 SELECT res||jsonb_build_object('reapplied_checks_equal_first',(SELECT md5(string_agg(check_name||':'||md5(check_sql)||':'||enabled::text||':'||sort_order,',' ORDER BY check_name)) FROM pdc_ops.regression_checks)=(res->>'checks1'),'window',pg_temp.window_report()) INTO r FROM r449_t;
 RAISE EXCEPTION 'R449_RB_RESULT %',r;
END $c$;
ROLLBACK;
