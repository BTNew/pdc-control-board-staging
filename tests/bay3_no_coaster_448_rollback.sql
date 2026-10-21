-- r448 (F61) rolled-back test: apply -> behaviour -> undo -> re-apply, then everything is rolled back (R448_RB_RESULT).
-- No booking, vehicle or line is written; the only writes are the release rows themselves, all rolled back.
-- Rolled-back release test window (F15, r405). Paste at the very top of every rolled-back test
-- that calls board write functions, and replace R448 with the release tag (e.g. R405).
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
    IF i > 75 THEN RAISE EXCEPTION 'R448_WINDOW: clock tick not seen; test not started'; END IF;
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
    RAISE EXCEPTION 'R448_DEADLINE: stopped before the next clock tick; everything rolled back';
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
CREATE TEMP TABLE r448_t ON COMMIT DROP AS SELECT (SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5) pins0, public.workshop_clock_tick(false,clock_timestamp()) tick0, '{}'::jsonb res;
SELECT pg_temp.deadline();
-- r448 (F61, change request: Bhavesh 21 Oct 18:19 AWST "RE: Bays - Dept 138 – Station & Bay Rules", approved by Craig): Bay 3
-- takes any vehicle except a Coaster ("Keep flexibility for any car except coaster in that bay"). A Coaster (model text with
-- "coaster" or the TOYCOA model code) stays warn-and-confirm with a logged override (r417, controllers/admins); Book all stations
-- skips Bay 3 for a Coaster (it only books where booking_rule is ok). A HiAce, a Hilux, any other model and a vehicle with no model
-- are now accepted with no warning. The warning text now says "Bay 3 has a height restriction and does not take a Coaster."
-- Changes pdc_bus_private.booking_rule and pdc_bay_rules_private.mismatches (pins move from r417 to r448). New check
-- bay3_no_coaster_448 (sort 247); bay3_hiace_only (r399) still holds (Coaster refused, HiAce accepted) and stays.
-- No booking, override or vehicle row is written. Not touched: workshop_clock_tick, workshop_validate_booking, bay guide (r447),
-- book_all_vehicle_stations, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r448: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r448: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r448: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'fc9b14ff691b36205c24977ccb07388e' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: booking_rule is not the r417 version; nothing changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0af8a12ddb42988b169d1fbf07a15d57' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: mismatches is not the r417 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE (signature='pdc_bus_private.booking_rule(uuid,uuid,uuid)' AND prosrc_md5='fc9b14ff691b36205c24977ccb07388e' AND release='r417')
      OR (signature='pdc_bay_rules_private.mismatches(uuid,text,uuid)' AND prosrc_md5='0af8a12ddb42988b169d1fbf07a15d57' AND release='r417'))<>2 THEN RAISE EXCEPTION 'r448: pins are not the expected r417 pins'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r448')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448' OR added_in='r448') THEN RAISE EXCEPTION 'r448: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=247) THEN RAISE EXCEPTION 'r448: sort_order 247 taken'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r447') THEN RAISE EXCEPTION 'r448: r447 is not applied'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule(p_vehicle_id uuid, p_bay_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE bay integer; code text; stage text; ready jsonb; model_name text;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT concat_ws(' ',v.model,v.vehicle_description) INTO model_name FROM public.vehicles v WHERE id=p_vehicle_id;
 -- r448 (F61, Bhavesh 21 Oct 18:19): Bay 3 has a height restriction and takes any vehicle except a Coaster (model text with
 -- "coaster" or the TOYCOA model code). A vehicle with no or an unknown model is allowed. A planner-confirmed, logged override
 -- (r417) still lets one Coaster booking use Bay 3; Book all stations skips Bay 3 for a Coaster.
 IF bay=3 AND (model_name~* 'coaster' OR upper(btrim(model_name))='TOYCOA')
  AND NOT pdc_bay_rules_private.override_active(p_booking_id,p_vehicle_id,p_bay_id,'bus_bay_vehicle_incompatible') THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'refused_model','Coaster'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id
  AND b.bay_id=p_bay_id AND b.deleted_at IS NULL AND b.status IN('planned','started','stoppage')) THEN RETURN jsonb_build_object('ok',true); END IF;
 RETURN jsonb_build_object('ok',true);
END $function$;

CREATE OR REPLACE FUNCTION pdc_bay_rules_private.mismatches(p_vehicle_id uuid, p_category text, p_bay_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
-- r417 (F32): which bay rules this vehicle/category would break in this bay. The rules themselves are unchanged
-- (pdc_work_categories_private.allowed_bay and pdc_bus_private.booking_rule); this only explains them.
DECLARE n integer; code text; out jsonb:='[]'::jsonb; rule jsonb; bay_for text;
BEGIN
 SELECT b.bay_number,s.code INTO n,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF n IS NULL OR code IS DISTINCT FROM 'BUS_4X4' THEN RETURN out; END IF;
 IF p_category IS NOT NULL AND NOT pdc_work_categories_private.allowed_bay(p_category,n) THEN
  SELECT string_agg(pdc_bay_rules_private.category_label(c),' and ' ORDER BY o) INTO bay_for
  FROM (VALUES('BUS_MECHANICAL',1),('BUS_ELECTRICAL',2),('BUS_ACCESSORIES',3),('BUS_QA',4)) x(c,o) WHERE pdc_work_categories_private.preferred_bay(c,n);
  out:=out||jsonb_build_array(jsonb_build_object('rule','category_bay_mismatch','bay_number',n,'work_category',p_category,
   'message',format('Bay %s is set up for %s work, and this booking is %s work.',n,coalesce(bay_for,'other'),pdc_bay_rules_private.category_label(p_category))));
 END IF;
 rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,NULL);
 IF rule->>'error'='bus_bay_vehicle_incompatible' THEN
  out:=out||jsonb_build_array(jsonb_build_object('rule','bus_bay_vehicle_incompatible','bay_number',n,
   -- r448 (F61): Bay 3 takes any vehicle except a Coaster.
   'message',format('Bay %s has a height restriction and does not take a Coaster.',n)));
 END IF;
 RETURN out;
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='72e436aa18baad933dbc38d50933eaa6',release='r448',note='r448: Bay 3 takes any vehicle except a Coaster (F61)',updated_at=clock_timestamp()
 WHERE signature='pdc_bus_private.booking_rule(uuid,uuid,uuid)' AND prosrc_md5='fc9b14ff691b36205c24977ccb07388e' AND release='r417';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0f21e96fe19b3736235088a133a8ad52',release='r448',note='r448: Bay 3 Coaster warning text (F61)',updated_at=clock_timestamp()
 WHERE signature='pdc_bay_rules_private.mismatches(uuid,text,uuid)' AND prosrc_md5='0af8a12ddb42988b169d1fbf07a15d57' AND release='r417';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('bay3_no_coaster_448','F61','Bus Bay 3 (r448) takes any vehicle except a Coaster: a Coaster by model text or TOYCOA code is refused (warn-and-confirm), a HiAce and another model are accepted, the warning names the Coaster, both functions pinned',
  $chk$WITH bay AS (SELECT b.id FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='BUS_4X4' AND b.bay_number=3),
v AS (SELECT v.id,concat_ws(' ',v.model,v.vehicle_description) m FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND pdc_bus_private.active_vehicle(v.id)),
pick AS (
 SELECT (SELECT id FROM v WHERE m~*'coaster' ORDER BY id LIMIT 1) coaster_text,
  (SELECT id FROM v WHERE upper(btrim(m))='TOYCOA' ORDER BY id LIMIT 1) coaster_code,
  (SELECT id FROM v WHERE (m~*'hi[[:space:]-]?ace' OR upper(btrim(m))='TOYHIA') AND m!~*'coaster' ORDER BY id LIMIT 1) hiace,
  (SELECT id FROM v WHERE m!~*'coaster' AND m!~*'hi[[:space:]-]?ace' AND upper(btrim(m)) NOT IN ('TOYHIA','TOYCOA') ORDER BY id LIMIT 1) other),
r AS (
 SELECT (SELECT pdc_bus_private.booking_rule(p.coaster_text,bay.id,NULL)->>'error' FROM bay) ct,
  (SELECT pdc_bus_private.booking_rule(p.coaster_code,bay.id,NULL)->>'error' FROM bay) cc,
  (SELECT pdc_bus_private.booking_rule(p.hiace,bay.id,NULL)->>'ok' FROM bay) hi,
  (SELECT pdc_bus_private.booking_rule(p.other,bay.id,NULL)->>'ok' FROM bay) ot,
  (SELECT pdc_bay_rules_private.mismatches(coalesce(p.coaster_text,p.coaster_code),NULL,bay.id)->0->>'message' FROM bay) msg,
  p.* FROM pick p),
pins AS (
 SELECT count(*) FILTER (WHERE md5(pr.prosrc)=e.prosrc_md5) n FROM pdc_ops.expected_function_md5 e
 JOIN pg_proc pr ON pr.oid=to_regprocedure(e.signature) WHERE e.release='r448')
SELECT (coaster_text IS NULL OR ct='bus_bay_vehicle_incompatible') AND (coaster_code IS NULL OR cc='bus_bay_vehicle_incompatible')
  AND (hiace IS NULL OR hi='true') AND (other IS NULL OR ot='true')
  AND (coalesce(coaster_text,coaster_code) IS NULL OR msg ~ 'does not take a Coaster')
  AND (SELECT n FROM pins)=2 AS ok,
 'Bay 3 (r448): Coaster by model text: '||coalesce(ct,CASE WHEN coaster_text IS NULL THEN 'no active one to test' ELSE 'ALLOWED' END)
 ||'; Coaster by TOYCOA code: '||coalesce(cc,CASE WHEN coaster_code IS NULL THEN 'no active one to test' ELSE 'ALLOWED' END)
 ||'; HiAce ok: '||coalesce(hi,'no active HiAce to test')||'; other vehicle ok: '||coalesce(ot,'no other active vehicle to test')
 ||'; warning: '||coalesce(msg,'-')||'; r448 pins matching: '||(SELECT n FROM pins)||'/2' AS detail
FROM r$chk$,true,247,'r448');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'72e436aa18baad933dbc38d50933eaa6' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: booking_rule did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0f21e96fe19b3736235088a133a8ad52' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: mismatches did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r448')<>2 THEN RAISE EXCEPTION 'r448: pins not moved'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448' AND added_in='r448')<>'bb01c45979e533e206ea8ad024877063' THEN RAISE EXCEPTION 'r448: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r448: check bay3_no_coaster_448 not OK: %',x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay3_hiace_only') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r448: check bay3_hiace_only not OK: %',x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448: clock tick changed'; END IF;
END $g$;
SELECT pg_temp.deadline();
DO $a$ DECLARE r jsonb:='{}'; x record; b3 uuid; co uuid; ot uuid; hi uuid; tick jsonb; BEGIN
 SELECT id INTO b3 FROM public.workshop_bays WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='BUS_4X4') AND bay_number=3;
 SELECT v.id INTO co FROM public.vehicles v WHERE v.deleted_at IS NULL AND (concat_ws(' ',v.model,v.vehicle_description)~*'coaster' OR upper(btrim(concat_ws(' ',v.model,v.vehicle_description)))='TOYCOA') AND pdc_bus_private.active_vehicle(v.id) ORDER BY v.id LIMIT 1;
 SELECT v.id INTO hi FROM public.vehicles v WHERE v.deleted_at IS NULL AND upper(btrim(concat_ws(' ',v.model,v.vehicle_description)))='TOYHIA' AND pdc_bus_private.active_vehicle(v.id) ORDER BY v.id LIMIT 1;
 SELECT v.id INTO ot FROM public.vehicles v WHERE v.deleted_at IS NULL AND upper(btrim(concat_ws(' ',v.model,v.vehicle_description))) IN ('TOYHIL','ISUDMA','TOYLAN','TOYPRA') AND pdc_bus_private.active_vehicle(v.id) ORDER BY v.id LIMIT 1;
 r:=r||jsonb_build_object('have',jsonb_build_object('coaster',co IS NOT NULL,'hiace',hi IS NOT NULL,'other',ot IS NOT NULL),
  'coaster_rule',pdc_bus_private.booking_rule(co,b3,NULL),'coaster_warn',pdc_bay_rules_private.mismatches(co,'BUS_MECHANICAL',b3),
  'hiace_rule',pdc_bus_private.booking_rule(hi,b3,NULL),'other_rule',pdc_bus_private.booking_rule(ot,b3,NULL),'other_warn',pdc_bay_rules_private.mismatches(ot,'BUS_MECHANICAL',b3),
  'warning_wrapped',pdc_bay_rules_private.warning(pdc_bay_rules_private.mismatches(co,'BUS_MECHANICAL',b3))->>'error');
 IF co IS NULL OR ot IS NULL THEN RAISE EXCEPTION 'R448 no active Coaster/other vehicle to read %',r; END IF;
 IF pdc_bus_private.booking_rule(co,b3,NULL)->>'error' IS DISTINCT FROM 'bus_bay_vehicle_incompatible'
  OR pdc_bus_private.booking_rule(ot,b3,NULL)->>'ok' IS DISTINCT FROM 'true'
  OR jsonb_array_length(pdc_bay_rules_private.mismatches(ot,'BUS_MECHANICAL',b3))<>0
  OR pdc_bay_rules_private.mismatches(co,'BUS_MECHANICAL',b3)->0->>'message' IS DISTINCT FROM 'Bay 3 has a height restriction and does not take a Coaster.'
 THEN RAISE EXCEPTION 'R448 behaviour wrong %',r; END IF;
 tick:=public.workshop_clock_tick(false,clock_timestamp());
 r:=r||jsonb_build_object('tick_dry_ok',tick->'ok','tick_dry_issues',tick->'issues','tick0_issues',(SELECT tick0->'issues' FROM r448_t));
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448') INTO x;
 r:=r||jsonb_build_object('check_ok',x.ok,'check',x.detail);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay_rule_mismatch_warns_and_logs') INTO x;
 r:=r||jsonb_build_object('mismatch_check_ok',x.ok);
 PERFORM set_config('search_path','public, extensions',true);
 r:=r||jsonb_build_object('pins1',(SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5),'npins',(SELECT count(*) FROM pdc_ops.expected_function_md5));
 UPDATE r448_t SET res=r WHERE true;
END $a$;
SELECT pg_temp.deadline();
-- r448 undo (F61): restores pdc_bus_private.booking_rule (md5 fc9b14ff691b36205c24977ccb07388e) and pdc_bay_rules_private.mismatches (md5 0af8a12ddb42988b169d1fbf07a15d57) byte for
-- byte (r417: Bay 3 HiAce only), puts their r417 pins back and drops bay3_no_coaster_448. Bookings placed in Bay 3 while r448 was
-- live that the HiAce-only rule would warn about (e.g. a Hilux) are kept where they are with an 'applied' override row tagged
-- 'r448_undo_kept', so the validator and the clock tick keep accepting them. Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r448 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r448 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r448 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'72e436aa18baad933dbc38d50933eaa6' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448 undo: booking_rule is not the r448 version; nothing changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0f21e96fe19b3736235088a133a8ad52' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448 undo: mismatches is not the r448 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r448')<>2 THEN RAISE EXCEPTION 'r448 undo: r448 pins not found'; END IF;
END $g$;

DROP TABLE IF EXISTS pg_temp.r448_new_ok;
CREATE TEMP TABLE r448_new_ok ON COMMIT DROP AS
SELECT b.id booking_id,b.vehicle_id,b.bay_id,bay.bay_number,b.work_category
FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id JOIN public.workshop_stages s ON s.id=bay.stage_id AND s.code='BUS_4X4'
WHERE bay.bay_number=3 AND b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage')
 AND coalesce((pdc_bus_private.booking_rule(b.vehicle_id,b.bay_id,NULL)->>'ok')::boolean,false);

CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule(p_vehicle_id uuid, p_bay_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE bay integer; code text; stage text; ready jsonb; model_name text;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT concat_ws(' ',v.model,v.vehicle_description) INTO model_name FROM public.vehicles v WHERE id=p_vehicle_id;
 -- r417 (F32): a planner-confirmed, logged override lets this one booking use Bay 3; the rule itself is unchanged.
 IF bay=3 AND (model_name~* 'coaster' OR (model_name!~* 'hi[[:space:]-]?ace' AND upper(btrim(model_name))<>'TOYHIA'))
  AND NOT pdc_bay_rules_private.override_active(p_booking_id,p_vehicle_id,p_bay_id,'bus_bay_vehicle_incompatible') THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'required_model','HiAce'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id
  AND b.bay_id=p_bay_id AND b.deleted_at IS NULL AND b.status IN('planned','started','stoppage')) THEN RETURN jsonb_build_object('ok',true); END IF;
 RETURN jsonb_build_object('ok',true);
END $function$;

CREATE OR REPLACE FUNCTION pdc_bay_rules_private.mismatches(p_vehicle_id uuid, p_category text, p_bay_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
-- r417 (F32): which bay rules this vehicle/category would break in this bay. The rules themselves are unchanged
-- (pdc_work_categories_private.allowed_bay and pdc_bus_private.booking_rule); this only explains them.
DECLARE n integer; code text; out jsonb:='[]'::jsonb; rule jsonb; bay_for text;
BEGIN
 SELECT b.bay_number,s.code INTO n,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF n IS NULL OR code IS DISTINCT FROM 'BUS_4X4' THEN RETURN out; END IF;
 IF p_category IS NOT NULL AND NOT pdc_work_categories_private.allowed_bay(p_category,n) THEN
  SELECT string_agg(pdc_bay_rules_private.category_label(c),' and ' ORDER BY o) INTO bay_for
  FROM (VALUES('BUS_MECHANICAL',1),('BUS_ELECTRICAL',2),('BUS_ACCESSORIES',3),('BUS_QA',4)) x(c,o) WHERE pdc_work_categories_private.preferred_bay(c,n);
  out:=out||jsonb_build_array(jsonb_build_object('rule','category_bay_mismatch','bay_number',n,'work_category',p_category,
   'message',format('Bay %s is set up for %s work, and this booking is %s work.',n,coalesce(bay_for,'other'),pdc_bay_rules_private.category_label(p_category))));
 END IF;
 rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,NULL);
 IF rule->>'error'='bus_bay_vehicle_incompatible' THEN
  out:=out||jsonb_build_array(jsonb_build_object('rule','bus_bay_vehicle_incompatible','bay_number',n,
   'message',format('Bay %s is for %s vehicles only, and this vehicle is not a %s.',n,coalesce(rule->>'required_model','HiAce'),coalesce(rule->>'required_model','HiAce'))));
 END IF;
 RETURN out;
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='fc9b14ff691b36205c24977ccb07388e',release='r417',note='F32: bay rule mismatch warns; confirmed overrides are logged',updated_at='2026-10-20 23:36:17.059572+00'
 WHERE signature='pdc_bus_private.booking_rule(uuid,uuid,uuid)' AND prosrc_md5='72e436aa18baad933dbc38d50933eaa6' AND release='r448';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0af8a12ddb42988b169d1fbf07a15d57',release='r417',note='F32: bay rule mismatch warns; confirmed overrides are logged',updated_at='2026-10-20 23:36:17.059572+00'
 WHERE signature='pdc_bay_rules_private.mismatches(uuid,text,uuid)' AND prosrc_md5='0f21e96fe19b3736235088a133a8ad52' AND release='r448';

INSERT INTO pdc_bay_rules_private.overrides(actor_id,actor_email,vehicle_id,booking_id,bay_id,bay_number,stage_code,work_category,rule,message,action,source,outcome,finished_at)
SELECT '00000000-0000-0000-0000-000000000000'::uuid,'r448 undo (no person)',o.vehicle_id,o.booking_id,o.bay_id,3,'BUS_4X4',o.work_category,'bus_bay_vehicle_incompatible',
 'Booked in Bay 3 while r448 let any vehicle except a Coaster use it. Kept where it was placed.','move','r448_undo_kept','applied',clock_timestamp()
FROM r448_new_ok o
WHERE pdc_bus_private.booking_rule(o.vehicle_id,o.bay_id,NULL)->>'error'='bus_bay_vehicle_incompatible'
 AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides x WHERE x.booking_id=o.booking_id AND x.bay_id=o.bay_id
  AND x.rule='bus_bay_vehicle_incompatible' AND x.outcome='applied' AND x.revoked_at IS NULL);

DELETE FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448' AND added_in='r448';

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'fc9b14ff691b36205c24977ccb07388e' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448 undo: booking_rule not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0af8a12ddb42988b169d1fbf07a15d57' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448 undo: mismatches not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r448') OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature IN ('pdc_bus_private.booking_rule(uuid,uuid,uuid)','pdc_bay_rules_private.mismatches(uuid,text,uuid)') AND release='r417')<>2 THEN RAISE EXCEPTION 'r448 undo: pins not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r448') THEN RAISE EXCEPTION 'r448 undo: check not removed'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
   WHERE b.deleted_at IS NULL AND b.status IN('planned','started','stoppage') AND bay.bay_number=3
    AND pdc_bus_private.booking_rule(b.vehicle_id,b.bay_id,NULL)->>'error'='bus_bay_vehicle_incompatible'
    AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id AND o.rule='bus_bay_vehicle_incompatible' AND o.outcome='applied' AND o.revoked_at IS NULL))
 THEN RAISE EXCEPTION 'r448 undo: a Bay 3 booking would break the HiAce rule without an override'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448 undo: clock tick changed'; END IF;
END $g$;
SELECT pg_temp.deadline();
DO $b$ DECLARE r jsonb; b3 uuid; ot uuid; BEGIN
 SELECT res INTO r FROM r448_t;
 SELECT id INTO b3 FROM public.workshop_bays WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='BUS_4X4') AND bay_number=3;
 SELECT v.id INTO ot FROM public.vehicles v WHERE v.deleted_at IS NULL AND upper(btrim(concat_ws(' ',v.model,v.vehicle_description))) IN ('TOYHIL','ISUDMA','TOYLAN','TOYPRA') AND pdc_bus_private.active_vehicle(v.id) ORDER BY v.id LIMIT 1;
 r:=r||jsonb_build_object('undone_pins_equal_before',(SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5)=(SELECT pins0 FROM r448_t),'undo_kept',(SELECT count(*) FROM pdc_bay_rules_private.overrides WHERE source='r448_undo_kept'),
   'undone_other_rule',pdc_bus_private.booking_rule(ot,b3,NULL)->>'error','undone_check_rows',(SELECT count(*) FROM pdc_ops.regression_checks WHERE added_in='r448'));
 UPDATE r448_t SET res=r WHERE true;
END $b$;
SELECT pg_temp.deadline();
-- r448 (F61, change request: Bhavesh 21 Oct 18:19 AWST "RE: Bays - Dept 138 – Station & Bay Rules", approved by Craig): Bay 3
-- takes any vehicle except a Coaster ("Keep flexibility for any car except coaster in that bay"). A Coaster (model text with
-- "coaster" or the TOYCOA model code) stays warn-and-confirm with a logged override (r417, controllers/admins); Book all stations
-- skips Bay 3 for a Coaster (it only books where booking_rule is ok). A HiAce, a Hilux, any other model and a vehicle with no model
-- are now accepted with no warning. The warning text now says "Bay 3 has a height restriction and does not take a Coaster."
-- Changes pdc_bus_private.booking_rule and pdc_bay_rules_private.mismatches (pins move from r417 to r448). New check
-- bay3_no_coaster_448 (sort 247); bay3_hiace_only (r399) still holds (Coaster refused, HiAce accepted) and stays.
-- No booking, override or vehicle row is written. Not touched: workshop_clock_tick, workshop_validate_booking, bay guide (r447),
-- book_all_vehicle_stations, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r448: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r448: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r448: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'fc9b14ff691b36205c24977ccb07388e' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: booking_rule is not the r417 version; nothing changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0af8a12ddb42988b169d1fbf07a15d57' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: mismatches is not the r417 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE (signature='pdc_bus_private.booking_rule(uuid,uuid,uuid)' AND prosrc_md5='fc9b14ff691b36205c24977ccb07388e' AND release='r417')
      OR (signature='pdc_bay_rules_private.mismatches(uuid,text,uuid)' AND prosrc_md5='0af8a12ddb42988b169d1fbf07a15d57' AND release='r417'))<>2 THEN RAISE EXCEPTION 'r448: pins are not the expected r417 pins'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r448')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448' OR added_in='r448') THEN RAISE EXCEPTION 'r448: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=247) THEN RAISE EXCEPTION 'r448: sort_order 247 taken'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r447') THEN RAISE EXCEPTION 'r448: r447 is not applied'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule(p_vehicle_id uuid, p_bay_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE bay integer; code text; stage text; ready jsonb; model_name text;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT concat_ws(' ',v.model,v.vehicle_description) INTO model_name FROM public.vehicles v WHERE id=p_vehicle_id;
 -- r448 (F61, Bhavesh 21 Oct 18:19): Bay 3 has a height restriction and takes any vehicle except a Coaster (model text with
 -- "coaster" or the TOYCOA model code). A vehicle with no or an unknown model is allowed. A planner-confirmed, logged override
 -- (r417) still lets one Coaster booking use Bay 3; Book all stations skips Bay 3 for a Coaster.
 IF bay=3 AND (model_name~* 'coaster' OR upper(btrim(model_name))='TOYCOA')
  AND NOT pdc_bay_rules_private.override_active(p_booking_id,p_vehicle_id,p_bay_id,'bus_bay_vehicle_incompatible') THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'refused_model','Coaster'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id
  AND b.bay_id=p_bay_id AND b.deleted_at IS NULL AND b.status IN('planned','started','stoppage')) THEN RETURN jsonb_build_object('ok',true); END IF;
 RETURN jsonb_build_object('ok',true);
END $function$;

CREATE OR REPLACE FUNCTION pdc_bay_rules_private.mismatches(p_vehicle_id uuid, p_category text, p_bay_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
-- r417 (F32): which bay rules this vehicle/category would break in this bay. The rules themselves are unchanged
-- (pdc_work_categories_private.allowed_bay and pdc_bus_private.booking_rule); this only explains them.
DECLARE n integer; code text; out jsonb:='[]'::jsonb; rule jsonb; bay_for text;
BEGIN
 SELECT b.bay_number,s.code INTO n,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF n IS NULL OR code IS DISTINCT FROM 'BUS_4X4' THEN RETURN out; END IF;
 IF p_category IS NOT NULL AND NOT pdc_work_categories_private.allowed_bay(p_category,n) THEN
  SELECT string_agg(pdc_bay_rules_private.category_label(c),' and ' ORDER BY o) INTO bay_for
  FROM (VALUES('BUS_MECHANICAL',1),('BUS_ELECTRICAL',2),('BUS_ACCESSORIES',3),('BUS_QA',4)) x(c,o) WHERE pdc_work_categories_private.preferred_bay(c,n);
  out:=out||jsonb_build_array(jsonb_build_object('rule','category_bay_mismatch','bay_number',n,'work_category',p_category,
   'message',format('Bay %s is set up for %s work, and this booking is %s work.',n,coalesce(bay_for,'other'),pdc_bay_rules_private.category_label(p_category))));
 END IF;
 rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,NULL);
 IF rule->>'error'='bus_bay_vehicle_incompatible' THEN
  out:=out||jsonb_build_array(jsonb_build_object('rule','bus_bay_vehicle_incompatible','bay_number',n,
   -- r448 (F61): Bay 3 takes any vehicle except a Coaster.
   'message',format('Bay %s has a height restriction and does not take a Coaster.',n)));
 END IF;
 RETURN out;
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='72e436aa18baad933dbc38d50933eaa6',release='r448',note='r448: Bay 3 takes any vehicle except a Coaster (F61)',updated_at=clock_timestamp()
 WHERE signature='pdc_bus_private.booking_rule(uuid,uuid,uuid)' AND prosrc_md5='fc9b14ff691b36205c24977ccb07388e' AND release='r417';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0f21e96fe19b3736235088a133a8ad52',release='r448',note='r448: Bay 3 Coaster warning text (F61)',updated_at=clock_timestamp()
 WHERE signature='pdc_bay_rules_private.mismatches(uuid,text,uuid)' AND prosrc_md5='0af8a12ddb42988b169d1fbf07a15d57' AND release='r417';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('bay3_no_coaster_448','F61','Bus Bay 3 (r448) takes any vehicle except a Coaster: a Coaster by model text or TOYCOA code is refused (warn-and-confirm), a HiAce and another model are accepted, the warning names the Coaster, both functions pinned',
  $chk$WITH bay AS (SELECT b.id FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='BUS_4X4' AND b.bay_number=3),
v AS (SELECT v.id,concat_ws(' ',v.model,v.vehicle_description) m FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND pdc_bus_private.active_vehicle(v.id)),
pick AS (
 SELECT (SELECT id FROM v WHERE m~*'coaster' ORDER BY id LIMIT 1) coaster_text,
  (SELECT id FROM v WHERE upper(btrim(m))='TOYCOA' ORDER BY id LIMIT 1) coaster_code,
  (SELECT id FROM v WHERE (m~*'hi[[:space:]-]?ace' OR upper(btrim(m))='TOYHIA') AND m!~*'coaster' ORDER BY id LIMIT 1) hiace,
  (SELECT id FROM v WHERE m!~*'coaster' AND m!~*'hi[[:space:]-]?ace' AND upper(btrim(m)) NOT IN ('TOYHIA','TOYCOA') ORDER BY id LIMIT 1) other),
r AS (
 SELECT (SELECT pdc_bus_private.booking_rule(p.coaster_text,bay.id,NULL)->>'error' FROM bay) ct,
  (SELECT pdc_bus_private.booking_rule(p.coaster_code,bay.id,NULL)->>'error' FROM bay) cc,
  (SELECT pdc_bus_private.booking_rule(p.hiace,bay.id,NULL)->>'ok' FROM bay) hi,
  (SELECT pdc_bus_private.booking_rule(p.other,bay.id,NULL)->>'ok' FROM bay) ot,
  (SELECT pdc_bay_rules_private.mismatches(coalesce(p.coaster_text,p.coaster_code),NULL,bay.id)->0->>'message' FROM bay) msg,
  p.* FROM pick p),
pins AS (
 SELECT count(*) FILTER (WHERE md5(pr.prosrc)=e.prosrc_md5) n FROM pdc_ops.expected_function_md5 e
 JOIN pg_proc pr ON pr.oid=to_regprocedure(e.signature) WHERE e.release='r448')
SELECT (coaster_text IS NULL OR ct='bus_bay_vehicle_incompatible') AND (coaster_code IS NULL OR cc='bus_bay_vehicle_incompatible')
  AND (hiace IS NULL OR hi='true') AND (other IS NULL OR ot='true')
  AND (coalesce(coaster_text,coaster_code) IS NULL OR msg ~ 'does not take a Coaster')
  AND (SELECT n FROM pins)=2 AS ok,
 'Bay 3 (r448): Coaster by model text: '||coalesce(ct,CASE WHEN coaster_text IS NULL THEN 'no active one to test' ELSE 'ALLOWED' END)
 ||'; Coaster by TOYCOA code: '||coalesce(cc,CASE WHEN coaster_code IS NULL THEN 'no active one to test' ELSE 'ALLOWED' END)
 ||'; HiAce ok: '||coalesce(hi,'no active HiAce to test')||'; other vehicle ok: '||coalesce(ot,'no other active vehicle to test')
 ||'; warning: '||coalesce(msg,'-')||'; r448 pins matching: '||(SELECT n FROM pins)||'/2' AS detail
FROM r$chk$,true,247,'r448');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'72e436aa18baad933dbc38d50933eaa6' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: booking_rule did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0f21e96fe19b3736235088a133a8ad52' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: mismatches did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r448')<>2 THEN RAISE EXCEPTION 'r448: pins not moved'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448' AND added_in='r448')<>'bb01c45979e533e206ea8ad024877063' THEN RAISE EXCEPTION 'r448: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r448: check bay3_no_coaster_448 not OK: %',x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay3_hiace_only') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r448: check bay3_hiace_only not OK: %',x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448: clock tick changed'; END IF;
END $g$;
SELECT pg_temp.deadline();
DO $c$ DECLARE r jsonb; BEGIN
 SELECT res INTO r FROM r448_t;
 r:=r||jsonb_build_object('reapplied_pins_equal_first',(SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5)=(r->>'pins1'),'window',pg_temp.window_report());
 RAISE EXCEPTION 'R448_RB_RESULT %',r;
END $c$;
ROLLBACK;
