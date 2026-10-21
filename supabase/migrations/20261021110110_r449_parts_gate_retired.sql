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
