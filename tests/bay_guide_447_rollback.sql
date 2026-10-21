-- r447 (F60) rolled-back test: apply -> behaviour -> undo -> re-apply, then everything is rolled back (R447_RB_RESULT).
-- No booking, vehicle or line is written; the only writes are the release rows themselves, all rolled back.
-- Rolled-back release test window (F15, r405). Paste at the very top of every rolled-back test
-- that calls board write functions, and replace R447 with the release tag (e.g. R405).
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
    IF i > 75 THEN RAISE EXCEPTION 'R447_WINDOW: clock tick not seen; test not started'; END IF;
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
    RAISE EXCEPTION 'R447_DEADLINE: stopped before the next clock tick; everything rolled back';
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
CREATE TEMP TABLE r447_t ON COMMIT DROP AS SELECT (SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5) pins0, public.workshop_clock_tick(false,clock_timestamp()) tick0, '{}'::jsonb res;
SELECT pg_temp.deadline();
-- r447 (F60, change request: Bhavesh 21 Oct 18:19 AWST "RE: Bays - Dept 138 – Station & Bay Rules", approved by Craig): Dept 138 bay
-- work-type guide. Bays 1-4 take Mechanical and Accessories, 5-6 are overflow for any Bus 4x4 work, 7 QA, 8-10 Electrical and
-- Accessories, all with no warning. Anything else stays warn-and-confirm with a logged override (r417, controllers/admins).
-- Book all stations books each category only into its own bays (never the overflow 5-6). Hard blocks are untouched (bay and
-- vehicle overlap, technician double-booking, leave/inactive, working hours, Bay 3 rule).
-- Changes two functions: pdc_work_categories_private.preferred_bay and allowed_bay (pins baseline/#386 move to r447).
-- Active bookings that the old rule accepted without a warning but the new guide would warn about (Mechanical already in
-- Bay 9 or 10) are kept where they are: each gets an 'applied' override row tagged source 'r447_grandfathered', so the
-- booking validator, the booking trigger and the clock tick keep accepting them. A planner moving one to another time or bay
-- is asked to confirm like any other mismatch. Checks bays_9_10_accept_mech_elec_acc and bus_bay_category_grid (r399)
-- described the old grid and are disabled; new check bus_bay_guide_447 (sort 246).
-- Not touched: workshop_clock_tick, workshop_validate_booking, booking_rule (Bay 3), book_all_vehicle_stations, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r447: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r447: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r447: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r447: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'9a785c3f4301213c4dae78e3717611ee' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447: preferred_bay is not the baseline version; nothing changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'a9e529f8e2153924fd8a5d323084f1c1' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447: allowed_bay is not the #386 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE (signature='pdc_work_categories_private.preferred_bay(text,integer)' AND prosrc_md5='9a785c3f4301213c4dae78e3717611ee' AND release='baseline')
      OR (signature='pdc_work_categories_private.allowed_bay(text,integer)' AND prosrc_md5='a9e529f8e2153924fd8a5d323084f1c1' AND release='#386'))<>2 THEN RAISE EXCEPTION 'r447: pins are not the expected baseline/#386 pins'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r447')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447' OR added_in='r447')
    OR EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides WHERE source='r447_grandfathered') THEN RAISE EXCEPTION 'r447: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=246) THEN RAISE EXCEPTION 'r447: sort_order 246 taken'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('bays_9_10_accept_mech_elec_acc','bus_bay_category_grid') AND enabled)<>2 THEN RAISE EXCEPTION 'r447: r399 grid checks not as expected'; END IF;
END $g$;

-- Bookings the old rule accepted without a warning, captured before the rule changes.
DROP TABLE IF EXISTS pg_temp.r447_old_ok;
CREATE TEMP TABLE r447_old_ok ON COMMIT DROP AS
SELECT b.id booking_id,b.vehicle_id,b.bay_id,bay.bay_number,b.work_category
FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id JOIN public.workshop_stages s ON s.id=b.stage_id AND s.code='BUS_4X4'
WHERE b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
 AND pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number);

CREATE OR REPLACE FUNCTION pdc_work_categories_private.preferred_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 -- r447 (F60, Bhavesh 21 Oct 18:19): each Dept 138 work category's own bays. Book all stations books only these, and the
 -- warning text names them. Bays 1-4 Mechanical and Accessories, Bay 7 QA, Bays 8-10 Electrical and Accessories.
 SELECT CASE category WHEN 'BUS_MECHANICAL' THEN bay IN(1,2,3,4)
 WHEN 'BUS_ACCESSORIES' THEN bay IN(1,2,3,4,8,9,10) WHEN 'BUS_ELECTRICAL' THEN bay IN(8,9,10) WHEN 'BUS_QA' THEN bay=7 ELSE false END
$function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.allowed_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 -- r447 (F60): no warning in the category's own bays or in the overflow Bays 5-6 (any Bus 4x4 work). Anything else is
 -- warn-and-confirm with a logged override (pdc_bay_rules_private, r417).
 SELECT pdc_work_categories_private.preferred_bay(category,bay)
  OR (bay IN (5,6) AND category IN ('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES','BUS_QA'))
$function$;

INSERT INTO pdc_bay_rules_private.overrides(actor_id,actor_email,vehicle_id,booking_id,bay_id,bay_number,stage_code,work_category,rule,message,action,source,outcome,finished_at)
SELECT '00000000-0000-0000-0000-000000000000'::uuid,'r447 release (no person)',o.vehicle_id,o.booking_id,o.bay_id,o.bay_number,'BUS_4X4',o.work_category,'category_bay_mismatch',
 format('Booked in Bay %s before the r447 bay guide, when %s work went there without a warning. Kept where it was placed.',o.bay_number,pdc_bay_rules_private.category_label(o.work_category)),
 'move','r447_grandfathered','applied',clock_timestamp()
FROM r447_old_ok o
WHERE NOT pdc_work_categories_private.allowed_bay(o.work_category,o.bay_number)
 AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides x WHERE x.booking_id=o.booking_id AND x.bay_id=o.bay_id
  AND x.rule='category_bay_mismatch' AND x.outcome='applied' AND x.revoked_at IS NULL);

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='5e0484d7690c91912b80fcef099d268a',release='r447',note='r447: Dept 138 bay guide, own bays (F60)',updated_at=clock_timestamp()
 WHERE signature='pdc_work_categories_private.preferred_bay(text,integer)' AND prosrc_md5='9a785c3f4301213c4dae78e3717611ee' AND release='baseline';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='bb83ffbf0580d6a384dc28b04d9361ea',release='r447',note='r447: Dept 138 bay guide, no-warning bays incl. overflow 5-6 (F60)',updated_at=clock_timestamp()
 WHERE signature='pdc_work_categories_private.allowed_bay(text,integer)' AND prosrc_md5='a9e529f8e2153924fd8a5d323084f1c1' AND release='#386';

UPDATE pdc_ops.regression_checks SET enabled=false
 WHERE check_name IN ('bays_9_10_accept_mech_elec_acc','bus_bay_category_grid') AND added_in='r399' AND enabled;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('bus_bay_guide_447','F60','Dept 138 bay guide (r447): allowed_bay/preferred_bay match the 4 x 10 grid (Bays 1-4 Mechanical and Accessories, 5-6 overflow for any Bus work, 7 QA, 8-10 Electrical and Accessories), both pinned; reports bookings kept where they were placed before r447 and overrides since',
  $chk$WITH want(cat,own,free) AS (VALUES
  ('BUS_MECHANICAL',ARRAY[1,2,3,4],ARRAY[1,2,3,4,5,6]),
  ('BUS_ACCESSORIES',ARRAY[1,2,3,4,8,9,10],ARRAY[1,2,3,4,5,6,8,9,10]),
  ('BUS_ELECTRICAL',ARRAY[8,9,10],ARRAY[5,6,8,9,10]),
  ('BUS_QA',ARRAY[7],ARRAY[5,6,7])),
g AS (
  SELECT w.cat,b,(b=ANY(w.free)) want_free,pdc_work_categories_private.allowed_bay(w.cat,b) got_free,
   (b=ANY(w.own)) want_own,pdc_work_categories_private.preferred_bay(w.cat,b) got_own
  FROM want w CROSS JOIN generate_series(1,10) b),
pins AS (
  SELECT count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) n FROM pdc_ops.expected_function_md5 e
  JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r447'),
gf AS (
  SELECT count(*) n,count(*) FILTER (WHERE b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage')) active
  FROM pdc_bay_rules_private.overrides o JOIN public.workshop_bookings b ON b.id=o.booking_id WHERE o.source='r447_grandfathered'),
ov AS (
  SELECT count(*) n FROM pdc_bay_rules_private.overrides o
  WHERE o.rule='category_bay_mismatch' AND o.outcome='applied' AND o.source IS DISTINCT FROM 'r447_grandfathered'
   AND o.created_at>(SELECT min(e.updated_at) FROM pdc_ops.expected_function_md5 e WHERE e.release='r447'))
SELECT count(*) FILTER (WHERE want_free IS DISTINCT FROM got_free OR want_own IS DISTINCT FROM got_own)=0 AND (SELECT n FROM pins)=2 AS ok,
 'Dept 138 bay guide (r447): '||coalesce('MISMATCH '||string_agg(cat||' bay '||b||' free='||got_free||' own='||got_own,', ') FILTER (WHERE want_free IS DISTINCT FROM got_free OR want_own IS DISTINCT FROM got_own),
  '80 cells match (1-4 Mech+Acc, 5-6 overflow any, 7 QA, 8-10 Elec+Acc; Book all uses own bays, never 5-6)')
 ||'; r447 pins matching: '||(SELECT n FROM pins)||'/2'
 ||'; bookings kept where they were placed before r447: '||(SELECT n FROM gf)||' ('||(SELECT active FROM gf)||' still active)'
 ||'; warn-and-confirm overrides since r447: '||(SELECT n FROM ov) AS detail
FROM g$chk$,true,246,'r447');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'5e0484d7690c91912b80fcef099d268a' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447: preferred_bay did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'bb83ffbf0580d6a384dc28b04d9361ea' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447: allowed_bay did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r447')<>2 THEN RAISE EXCEPTION 'r447: pins not moved'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447' AND added_in='r447')<>'77df90f3b79ed50823d68f6bef1bc3f2' THEN RAISE EXCEPTION 'r447: check did not land as expected'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
   WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
    AND NOT pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number)
    AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id AND o.rule='category_bay_mismatch' AND o.outcome='applied' AND o.revoked_at IS NULL))
 THEN RAISE EXCEPTION 'r447: an active booking would break the new guide without an override'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r447: check bus_bay_guide_447 not OK: %',x.detail; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r447: clock tick changed'; END IF;
END $g$;
SELECT pg_temp.deadline();
DO $a$ DECLARE r jsonb:='{}'; x record; bad text; v uuid; b9 uuid; b5 uuid; b1 uuid; tick jsonb; BEGIN
 SELECT id INTO b9 FROM public.workshop_bays WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='BUS_4X4') AND bay_number=9;
 SELECT id INTO b5 FROM public.workshop_bays WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='BUS_4X4') AND bay_number=5;
 SELECT id INTO b1 FROM public.workshop_bays WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='BUS_4X4') AND bay_number=1;
 SELECT b.vehicle_id INTO v FROM public.workshop_bookings b JOIN pdc_bay_rules_private.overrides o ON o.booking_id=b.id AND o.source='r447_grandfathered' LIMIT 1;
 r:=r||jsonb_build_object('grandfathered',(SELECT jsonb_agg(jsonb_build_object('booking',left(o.booking_id::text,8),'bay',o.bay_number,'cat',o.work_category)) FROM pdc_bay_rules_private.overrides o WHERE o.source='r447_grandfathered'));
 SELECT string_agg(left(b.id::text,8)||':'||(public.workshop_validate_booking(b.id,b.vehicle_id,b.stage_id,b.bay_id,b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,b.status,
   (SELECT a.technician_id FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL ORDER BY CASE WHEN a.assignment_type='primary' THEN 0 ELSE 1 END,a.assigned_at DESC LIMIT 1),true)::text),' ')
  INTO bad FROM public.workshop_bookings b JOIN pdc_bay_rules_private.overrides o ON o.booking_id=b.id AND o.source='r447_grandfathered';
 r:=r||jsonb_build_object('grandfathered_validate',bad);
 r:=r||jsonb_build_object('mech_bay9',pdc_bay_rules_private.mismatches(v,'BUS_MECHANICAL',b9),'elec_bay5',pdc_bay_rules_private.mismatches(v,'BUS_ELECTRICAL',b5),
   'acc_bay1',pdc_bay_rules_private.mismatches(v,'BUS_ACCESSORIES',b1),'elec_bay1',pdc_bay_rules_private.mismatches(v,'BUS_ELECTRICAL',b1),'qa_bay5',pdc_bay_rules_private.mismatches(v,'BUS_QA',b5));
 IF jsonb_array_length(pdc_bay_rules_private.mismatches(v,'BUS_ELECTRICAL',b5))<>0 OR jsonb_array_length(pdc_bay_rules_private.mismatches(v,'BUS_ACCESSORIES',b1))<>0 OR jsonb_array_length(pdc_bay_rules_private.mismatches(v,'BUS_MECHANICAL',b9))<>1 THEN RAISE EXCEPTION 'R447 mismatch behaviour wrong %',r; END IF;
 tick:=public.workshop_clock_tick(false,clock_timestamp());
 r:=r||jsonb_build_object('tick_dry_ok',tick->'ok','tick_dry_issues',tick->'issues','tick0_issues',(SELECT tick0->'issues' FROM r447_t),'tick_keys',(SELECT jsonb_agg(k) FROM jsonb_object_keys(tick) k));
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 r:=r||jsonb_build_object('check_ok',x.ok,'check',x.detail,'pins1',(SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5),'npins',(SELECT count(*) FROM pdc_ops.expected_function_md5));
 UPDATE r447_t SET res=r WHERE true;
END $a$;
SELECT pg_temp.deadline();
-- r447 undo (F60): restores pdc_work_categories_private.preferred_bay (baseline, md5 9a785c3f4301213c4dae78e3717611ee) and
-- allowed_bay (#386, md5 a9e529f8e2153924fd8a5d323084f1c1) byte for byte, puts their pins back, re-enables the r399 grid checks
-- and drops bus_bay_guide_447. The 'r447_grandfathered' override rows are removed (the old rule accepts those bookings again).
-- Bookings placed after r447 that the old rule would warn about (e.g. Mechanical in Bay 5, Accessories in Bay 1) are kept where
-- they are with an 'applied' override row tagged 'r447_undo_kept', so the validator and the clock tick keep accepting them.
-- Overrides that planners confirmed while r447 was live stay (history). Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r447 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r447 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r447 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r447 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'5e0484d7690c91912b80fcef099d268a' OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'bb83ffbf0580d6a384dc28b04d9361ea' THEN RAISE EXCEPTION 'r447 undo: functions are not the r447 versions; nothing restored'; END IF;
END $g$;

DROP TABLE IF EXISTS pg_temp.r447_new_ok;
CREATE TEMP TABLE r447_new_ok ON COMMIT DROP AS
SELECT b.id booking_id,b.vehicle_id,b.bay_id,bay.bay_number,b.work_category
FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id JOIN public.workshop_stages s ON s.id=b.stage_id AND s.code='BUS_4X4'
WHERE b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
 AND pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number);

CREATE OR REPLACE FUNCTION pdc_work_categories_private.preferred_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT CASE category WHEN 'BUS_MECHANICAL' THEN bay IN(1,2,3,4)
 WHEN 'BUS_ELECTRICAL' THEN bay IN(8,9) WHEN 'BUS_ACCESSORIES' THEN bay=10 WHEN 'BUS_QA' THEN bay=7 ELSE false END
$function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.allowed_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT pdc_work_categories_private.preferred_bay(category,bay)
  OR (bay IN (9,10) AND category IN ('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES'))
$function$;

DELETE FROM pdc_bay_rules_private.overrides WHERE source='r447_grandfathered';

INSERT INTO pdc_bay_rules_private.overrides(actor_id,actor_email,vehicle_id,booking_id,bay_id,bay_number,stage_code,work_category,rule,message,action,source,outcome,finished_at)
SELECT '00000000-0000-0000-0000-000000000000'::uuid,'r447 undo (no person)',o.vehicle_id,o.booking_id,o.bay_id,o.bay_number,'BUS_4X4',o.work_category,'category_bay_mismatch',
 format('Booked in Bay %s while the r447 bay guide was live (%s work went there without a warning). Kept where it was placed when r447 was undone.',o.bay_number,pdc_bay_rules_private.category_label(o.work_category)),
 'move','r447_undo_kept','applied',clock_timestamp()
FROM r447_new_ok o
WHERE NOT pdc_work_categories_private.allowed_bay(o.work_category,o.bay_number)
 AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides x WHERE x.booking_id=o.booking_id AND x.bay_id=o.bay_id
  AND x.rule='category_bay_mismatch' AND x.outcome='applied' AND x.revoked_at IS NULL);

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='9a785c3f4301213c4dae78e3717611ee',release='baseline',note='preferred bays',updated_at='2026-10-20T10:55:01.195622+00:00'
 WHERE signature='pdc_work_categories_private.preferred_bay(text,integer)' AND prosrc_md5='5e0484d7690c91912b80fcef099d268a' AND release='r447';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='a9e529f8e2153924fd8a5d323084f1c1',release='#386',note='Bays 9/10 accept MECH/ELEC/ACC',updated_at='2026-10-20T10:55:01.195622+00:00'
 WHERE signature='pdc_work_categories_private.allowed_bay(text,integer)' AND prosrc_md5='bb83ffbf0580d6a384dc28b04d9361ea' AND release='r447';
UPDATE pdc_ops.regression_checks SET enabled=true WHERE check_name IN ('bays_9_10_accept_mech_elec_acc','bus_bay_category_grid') AND added_in='r399' AND NOT enabled;
DELETE FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447' AND added_in='r447';

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'9a785c3f4301213c4dae78e3717611ee' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447 undo: preferred_bay not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'a9e529f8e2153924fd8a5d323084f1c1' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447 undo: allowed_bay not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r447') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r447')
    OR EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides WHERE source='r447_grandfathered')
    OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('bays_9_10_accept_mech_elec_acc','bus_bay_category_grid') AND enabled)<>2
 THEN RAISE EXCEPTION 'r447 undo: r447 rows remain'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
   WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
    AND NOT pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number)
    AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id AND o.rule='category_bay_mismatch' AND o.outcome='applied' AND o.revoked_at IS NULL))
 THEN RAISE EXCEPTION 'r447 undo: an active booking would break the restored rule without an override'; END IF;
END $g$;
SELECT pg_temp.deadline();
DO $b$ DECLARE r jsonb; BEGIN
 SELECT res INTO r FROM r447_t;
 r:=r||jsonb_build_object('undone_pins_equal_before',(SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5)=(SELECT pins0 FROM r447_t),'undo_kept',(SELECT count(*) FROM pdc_bay_rules_private.overrides WHERE source='r447_undo_kept'),
   'undone_mech9',pdc_work_categories_private.allowed_bay('BUS_MECHANICAL',9),'undone_elec5',pdc_work_categories_private.allowed_bay('BUS_ELECTRICAL',5));
 UPDATE r447_t SET res=r WHERE true;
END $b$;
SELECT pg_temp.deadline();
-- r447 (F60, change request: Bhavesh 21 Oct 18:19 AWST "RE: Bays - Dept 138 – Station & Bay Rules", approved by Craig): Dept 138 bay
-- work-type guide. Bays 1-4 take Mechanical and Accessories, 5-6 are overflow for any Bus 4x4 work, 7 QA, 8-10 Electrical and
-- Accessories, all with no warning. Anything else stays warn-and-confirm with a logged override (r417, controllers/admins).
-- Book all stations books each category only into its own bays (never the overflow 5-6). Hard blocks are untouched (bay and
-- vehicle overlap, technician double-booking, leave/inactive, working hours, Bay 3 rule).
-- Changes two functions: pdc_work_categories_private.preferred_bay and allowed_bay (pins baseline/#386 move to r447).
-- Active bookings that the old rule accepted without a warning but the new guide would warn about (Mechanical already in
-- Bay 9 or 10) are kept where they are: each gets an 'applied' override row tagged source 'r447_grandfathered', so the
-- booking validator, the booking trigger and the clock tick keep accepting them. A planner moving one to another time or bay
-- is asked to confirm like any other mismatch. Checks bays_9_10_accept_mech_elec_acc and bus_bay_category_grid (r399)
-- described the old grid and are disabled; new check bus_bay_guide_447 (sort 246).
-- Not touched: workshop_clock_tick, workshop_validate_booking, booking_rule (Bay 3), book_all_vehicle_stations, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r447: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r447: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r447: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r447: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'9a785c3f4301213c4dae78e3717611ee' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447: preferred_bay is not the baseline version; nothing changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'a9e529f8e2153924fd8a5d323084f1c1' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447: allowed_bay is not the #386 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE (signature='pdc_work_categories_private.preferred_bay(text,integer)' AND prosrc_md5='9a785c3f4301213c4dae78e3717611ee' AND release='baseline')
      OR (signature='pdc_work_categories_private.allowed_bay(text,integer)' AND prosrc_md5='a9e529f8e2153924fd8a5d323084f1c1' AND release='#386'))<>2 THEN RAISE EXCEPTION 'r447: pins are not the expected baseline/#386 pins'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r447')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447' OR added_in='r447')
    OR EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides WHERE source='r447_grandfathered') THEN RAISE EXCEPTION 'r447: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=246) THEN RAISE EXCEPTION 'r447: sort_order 246 taken'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('bays_9_10_accept_mech_elec_acc','bus_bay_category_grid') AND enabled)<>2 THEN RAISE EXCEPTION 'r447: r399 grid checks not as expected'; END IF;
END $g$;

-- Bookings the old rule accepted without a warning, captured before the rule changes.
DROP TABLE IF EXISTS pg_temp.r447_old_ok;
CREATE TEMP TABLE r447_old_ok ON COMMIT DROP AS
SELECT b.id booking_id,b.vehicle_id,b.bay_id,bay.bay_number,b.work_category
FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id JOIN public.workshop_stages s ON s.id=b.stage_id AND s.code='BUS_4X4'
WHERE b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
 AND pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number);

CREATE OR REPLACE FUNCTION pdc_work_categories_private.preferred_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 -- r447 (F60, Bhavesh 21 Oct 18:19): each Dept 138 work category's own bays. Book all stations books only these, and the
 -- warning text names them. Bays 1-4 Mechanical and Accessories, Bay 7 QA, Bays 8-10 Electrical and Accessories.
 SELECT CASE category WHEN 'BUS_MECHANICAL' THEN bay IN(1,2,3,4)
 WHEN 'BUS_ACCESSORIES' THEN bay IN(1,2,3,4,8,9,10) WHEN 'BUS_ELECTRICAL' THEN bay IN(8,9,10) WHEN 'BUS_QA' THEN bay=7 ELSE false END
$function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.allowed_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 -- r447 (F60): no warning in the category's own bays or in the overflow Bays 5-6 (any Bus 4x4 work). Anything else is
 -- warn-and-confirm with a logged override (pdc_bay_rules_private, r417).
 SELECT pdc_work_categories_private.preferred_bay(category,bay)
  OR (bay IN (5,6) AND category IN ('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES','BUS_QA'))
$function$;

INSERT INTO pdc_bay_rules_private.overrides(actor_id,actor_email,vehicle_id,booking_id,bay_id,bay_number,stage_code,work_category,rule,message,action,source,outcome,finished_at)
SELECT '00000000-0000-0000-0000-000000000000'::uuid,'r447 release (no person)',o.vehicle_id,o.booking_id,o.bay_id,o.bay_number,'BUS_4X4',o.work_category,'category_bay_mismatch',
 format('Booked in Bay %s before the r447 bay guide, when %s work went there without a warning. Kept where it was placed.',o.bay_number,pdc_bay_rules_private.category_label(o.work_category)),
 'move','r447_grandfathered','applied',clock_timestamp()
FROM r447_old_ok o
WHERE NOT pdc_work_categories_private.allowed_bay(o.work_category,o.bay_number)
 AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides x WHERE x.booking_id=o.booking_id AND x.bay_id=o.bay_id
  AND x.rule='category_bay_mismatch' AND x.outcome='applied' AND x.revoked_at IS NULL);

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='5e0484d7690c91912b80fcef099d268a',release='r447',note='r447: Dept 138 bay guide, own bays (F60)',updated_at=clock_timestamp()
 WHERE signature='pdc_work_categories_private.preferred_bay(text,integer)' AND prosrc_md5='9a785c3f4301213c4dae78e3717611ee' AND release='baseline';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='bb83ffbf0580d6a384dc28b04d9361ea',release='r447',note='r447: Dept 138 bay guide, no-warning bays incl. overflow 5-6 (F60)',updated_at=clock_timestamp()
 WHERE signature='pdc_work_categories_private.allowed_bay(text,integer)' AND prosrc_md5='a9e529f8e2153924fd8a5d323084f1c1' AND release='#386';

UPDATE pdc_ops.regression_checks SET enabled=false
 WHERE check_name IN ('bays_9_10_accept_mech_elec_acc','bus_bay_category_grid') AND added_in='r399' AND enabled;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('bus_bay_guide_447','F60','Dept 138 bay guide (r447): allowed_bay/preferred_bay match the 4 x 10 grid (Bays 1-4 Mechanical and Accessories, 5-6 overflow for any Bus work, 7 QA, 8-10 Electrical and Accessories), both pinned; reports bookings kept where they were placed before r447 and overrides since',
  $chk$WITH want(cat,own,free) AS (VALUES
  ('BUS_MECHANICAL',ARRAY[1,2,3,4],ARRAY[1,2,3,4,5,6]),
  ('BUS_ACCESSORIES',ARRAY[1,2,3,4,8,9,10],ARRAY[1,2,3,4,5,6,8,9,10]),
  ('BUS_ELECTRICAL',ARRAY[8,9,10],ARRAY[5,6,8,9,10]),
  ('BUS_QA',ARRAY[7],ARRAY[5,6,7])),
g AS (
  SELECT w.cat,b,(b=ANY(w.free)) want_free,pdc_work_categories_private.allowed_bay(w.cat,b) got_free,
   (b=ANY(w.own)) want_own,pdc_work_categories_private.preferred_bay(w.cat,b) got_own
  FROM want w CROSS JOIN generate_series(1,10) b),
pins AS (
  SELECT count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) n FROM pdc_ops.expected_function_md5 e
  JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r447'),
gf AS (
  SELECT count(*) n,count(*) FILTER (WHERE b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage')) active
  FROM pdc_bay_rules_private.overrides o JOIN public.workshop_bookings b ON b.id=o.booking_id WHERE o.source='r447_grandfathered'),
ov AS (
  SELECT count(*) n FROM pdc_bay_rules_private.overrides o
  WHERE o.rule='category_bay_mismatch' AND o.outcome='applied' AND o.source IS DISTINCT FROM 'r447_grandfathered'
   AND o.created_at>(SELECT min(e.updated_at) FROM pdc_ops.expected_function_md5 e WHERE e.release='r447'))
SELECT count(*) FILTER (WHERE want_free IS DISTINCT FROM got_free OR want_own IS DISTINCT FROM got_own)=0 AND (SELECT n FROM pins)=2 AS ok,
 'Dept 138 bay guide (r447): '||coalesce('MISMATCH '||string_agg(cat||' bay '||b||' free='||got_free||' own='||got_own,', ') FILTER (WHERE want_free IS DISTINCT FROM got_free OR want_own IS DISTINCT FROM got_own),
  '80 cells match (1-4 Mech+Acc, 5-6 overflow any, 7 QA, 8-10 Elec+Acc; Book all uses own bays, never 5-6)')
 ||'; r447 pins matching: '||(SELECT n FROM pins)||'/2'
 ||'; bookings kept where they were placed before r447: '||(SELECT n FROM gf)||' ('||(SELECT active FROM gf)||' still active)'
 ||'; warn-and-confirm overrides since r447: '||(SELECT n FROM ov) AS detail
FROM g$chk$,true,246,'r447');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'5e0484d7690c91912b80fcef099d268a' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447: preferred_bay did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'bb83ffbf0580d6a384dc28b04d9361ea' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_work_categories_private.allowed_bay(text,integer)'::regprocedure)<>'{postgres=X/postgres}|false|i|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r447: allowed_bay did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r447')<>2 THEN RAISE EXCEPTION 'r447: pins not moved'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447' AND added_in='r447')<>'77df90f3b79ed50823d68f6bef1bc3f2' THEN RAISE EXCEPTION 'r447: check did not land as expected'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
   WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
    AND NOT pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number)
    AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id AND o.rule='category_bay_mismatch' AND o.outcome='applied' AND o.revoked_at IS NULL))
 THEN RAISE EXCEPTION 'r447: an active booking would break the new guide without an override'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r447: check bus_bay_guide_447 not OK: %',x.detail; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r447: clock tick changed'; END IF;
END $g$;
SELECT pg_temp.deadline();
DO $c$ DECLARE r jsonb; BEGIN
 SELECT res INTO r FROM r447_t;
 r:=r||jsonb_build_object('reapplied_pins_equal_first',(SELECT md5(string_agg(signature||':'||prosrc_md5||':'||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5)=(r->>'pins1'),'window',pg_temp.window_report());
 RAISE EXCEPTION 'R447_RB_RESULT %',r;
END $c$;
ROLLBACK;
