-- Undo r554 (F168). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Restores the r454 location snapshot and the eligibility snapshot, and the calendar reads.
-- Does not change is_pdc_role, the r552 clock tick, the r545 board wrapper, or the #534 conditional board read.
-- Pin count stays 241. The location pin goes back to e7f77fad301b8a87ef548472a8f790a6 and stays release r454.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r554 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r554 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r554 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r554 undo: location calculation changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()')) IS DISTINCT FROM 'f744636778e0f10128d6457605430c2f' THEN RAISE EXCEPTION 'r554 undo: eligibility calculation changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '2067547fafa49f0bfeb54c4bc18a824e' THEN RAISE EXCEPTION 'r554 undo: location wrapper is not r554'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.is_pdc_role(public.pdc_role)')) IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r554 undo: role body changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'fa17068b106bbb9488c257e61d32e483' THEN RAISE EXCEPTION 'r554 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM 'ae706516b88574c1162e2c5889e4b4a9' THEN RAISE EXCEPTION 'r554 undo: board changed'; END IF;
END $g$;

DO $back$
DECLARE def text;
BEGIN
  SELECT pg_get_functiondef('pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure) INTO def;
  def := regexp_replace(def, 'pdc_ops\.vehicle_location_snapshot_compute_554\(\)', 'public.get_pdc_email_vehicle_location_snapshot()');
  EXECUTE def;
  SELECT pg_get_functiondef('pdc_ops.eligibility_snapshot_compute_554()'::regprocedure) INTO def;
  def := regexp_replace(def, 'pdc_ops\.eligibility_snapshot_compute_554\(\)', 'public.get_workshop_eligibility_snapshot()');
  EXECUTE def;

  SELECT pg_get_functiondef('public.workshop_calendar_minute_available(timestamptz)'::regprocedure) INTO def;
  def := replace(def, $new$
  v_settings:=public.workshop_settings_bag_554();$new$, $old$
  select jsonb_object_agg(key,value) into v_settings from public.workshop_settings
  where key in('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');$old$);
  IF position('workshop_settings_bag_554' IN def)>0 THEN RAISE EXCEPTION 'r554 undo: calendar rewrite remains'; END IF;
  EXECUTE def;

  SELECT pg_get_functiondef('pdc_bus_private.minute_available(timestamptz,uuid)'::regprocedure) INTO def;
  def := replace(def,
    'SELECT f.bay_number, f.code INTO bay, code FROM public.workshop_bay_stage_554(p_bay_id) f;',
    'SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;');
  def := replace(def,
    'breaks:=coalesce(public.workshop_settings_bag_554()->''break_windows'',''[]''::jsonb);' || E'\n' ||
    ' closures:=coalesce(public.workshop_settings_bag_554()->''closures'',''[]''::jsonb);',
    'SELECT coalesce(value,''[]''::jsonb) INTO breaks FROM public.workshop_settings WHERE key=''break_windows'';' || E'\n' ||
    ' SELECT coalesce(value,''[]''::jsonb) INTO closures FROM public.workshop_settings WHERE key=''closures'';');
  IF position('workshop_settings_bag_554' IN def)>0 OR position('workshop_bay_stage_554' IN def)>0 THEN
    RAISE EXCEPTION 'r554 undo: bus minute rewrite remains';
  END IF;
  EXECUTE def;
END
$back$;

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_workshop_eligibility_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_workshop_eligibility_snapshot() TO authenticated, service_role;

UPDATE pdc_ops.expected_function_md5
 SET prosrc_md5='e7f77fad301b8a87ef548472a8f790a6',
     note='r454 location snapshot (r554 undo)',
     updated_at=now()
 WHERE signature='public.get_pdc_email_vehicle_location_snapshot()'
   AND release='r454'
   AND prosrc_md5='2067547fafa49f0bfeb54c4bc18a824e';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(replace(check_sql,
   '|| kept.n || ''/13 old layer functions kept for undo; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e'' AS detail',
   '|| kept.n || ''/13 old layer functions kept for undo'' AS detail'),
   'AND kept.n = 13 AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'' AS ok',
   'AND kept.n = 13 AS ok'),
   '(''pdc_ops.vehicle_location_snapshot_compute_554()'', ''get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()'', NULL, ''outer'')',
   '(''public.get_pdc_email_vehicle_location_snapshot()'', ''get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()'', NULL, ''outer'')')
 WHERE check_name='snapshot_segments_collapsed';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(replace(check_sql,
   'ELSE ''NOT as r412 left it'' END || ''; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e'' AS detail',
   'ELSE ''NOT as r412 left it'' END AS detail'),
   'SELECT s.bad = 0 AND coalesce(s.outer_ok, false) AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'' AS ok',
   'SELECT s.bad = 0 AND coalesce(s.outer_ok, false) AS ok'),
   '''pdc_ops.vehicle_location_snapshot_compute_554()''',
   '''public.get_pdc_email_vehicle_location_snapshot()''')
 WHERE check_name='snapshot_outer_single_eval';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(replace(check_sql,
   '||''; vehicles on the board now: ''||(SELECT n FROM board)||''; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e'' AS detail',
   '||''; vehicles on the board now: ''||(SELECT n FROM board) AS detail'),
   'AND coalesce((SELECT ok FROM uses),false) AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'' AS ok',
   'AND coalesce((SELECT ok FROM uses),false) AS ok'),
   'to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()'')',
   'to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()'')')
 WHERE check_name='history_board_visibility_453';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(replace(check_sql,
   '||''; active/RFT vehicles whose dealer comes from their own source record: ''||(SELECT n FROM found)||''; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e'' AS detail',
   '||''; active/RFT vehicles whose dealer comes from their own source record: ''||(SELECT n FROM found) AS detail'),
   'AND (SELECT other FROM dealer_users)=0 AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'' AS ok',
   'AND (SELECT other FROM dealer_users)=0 AS ok'),
   'pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''),' || E'\n' ||
   '     pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''),',
   'pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''),')
 WHERE check_name='board_identity_open_454';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(check_sql,
   'revision reread %s; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e',
   'revision reread %s'),
   '(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e''',
   '(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''e7f77fad301b8a87ef548472a8f790a6''')
 WHERE check_name='vehicle_board_snapshot_cache_545';

DROP TRIGGER IF EXISTS r554_workshop_settings_read_once ON public.workshop_settings;
DROP TRIGGER IF EXISTS r554_workshop_bays_read_once ON public.workshop_bays;
DROP TRIGGER IF EXISTS r554_workshop_stages_read_once ON public.workshop_stages;
DROP FUNCTION IF EXISTS public.r554_clear_read_once();
DROP FUNCTION IF EXISTS public.workshop_settings_bag_554();
DROP FUNCTION IF EXISTS public.workshop_bay_stage_554(uuid);
DROP TABLE IF EXISTS pdc_ops.vehicle_location_snapshot_cache_554;
DROP TABLE IF EXISTS pdc_ops.eligibility_snapshot_cache_554;
DROP FUNCTION IF EXISTS pdc_ops.vehicle_location_snapshot_compute_554();
DROP FUNCTION IF EXISTS pdc_ops.eligibility_snapshot_compute_554();

DELETE FROM pdc_ops.regression_checks
 WHERE check_name='read_once_snapshots_554' AND fault_id='F168' AND sort_order=329 AND added_in='r554';

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r554 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r554 undo: location md5'; END IF;
 IF (SELECT provolatile<>'s' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) THEN RAISE EXCEPTION 'r554 undo: location is not a stable definer'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_eligibility_snapshot()')) IS DISTINCT FROM 'f744636778e0f10128d6457605430c2f' THEN RAISE EXCEPTION 'r554 undo: eligibility md5'; END IF;
 IF (SELECT provolatile<>'s' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_eligibility_snapshot()')) THEN RAISE EXCEPTION 'r554 undo: eligibility is not a stable definer'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.is_pdc_role(public.pdc_role)')) IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r554 undo: role md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_calendar_minute_available(timestamptz)')) IS DISTINCT FROM '6b53f98e01026e379d5498d668ec6cbd' THEN RAISE EXCEPTION 'r554 undo: calendar md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.minute_available(timestamptz,uuid)')) IS DISTINCT FROM 'b65554007366b7fd862b3a73f3cbbc54' THEN RAISE EXCEPTION 'r554 undo: bus minute md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM 'ae706516b88574c1162e2c5889e4b4a9' THEN RAISE EXCEPTION 'r554 undo: board md5'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_location_snapshot()' AND release='r454') IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r554 undo: location pin'; END IF;
 IF to_regclass('pdc_ops.vehicle_location_snapshot_cache_554') IS NOT NULL OR to_regclass('pdc_ops.eligibility_snapshot_cache_554') IS NOT NULL THEN RAISE EXCEPTION 'r554 undo: cache remains'; END IF;
 IF to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()') IS NOT NULL THEN RAISE EXCEPTION 'r554 undo: compute remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554' OR fault_id='F168' OR added_in='r554' OR sort_order=329) THEN RAISE EXCEPTION 'r554 undo: check remains'; END IF;
 IF (SELECT position('pdc_ops.vehicle_location_snapshot_compute_554()' IN check_sql) FROM pdc_ops.regression_checks WHERE check_name='vehicle_board_snapshot_cache_545')<>0 THEN RAISE EXCEPTION 'r554 undo: r545 check still names the compute copy'; END IF;
 IF (SELECT position('public.get_pdc_email_vehicle_location_snapshot()' IN check_sql)=0 FROM pdc_ops.regression_checks WHERE check_name='vehicle_board_snapshot_cache_545') THEN RAISE EXCEPTION 'r554 undo: r545 check lost the public location function'; END IF;
 IF (SELECT position('2067547fafa49f0bfeb54c4bc18a824e' IN check_sql) FROM pdc_ops.regression_checks WHERE check_name='snapshot_segments_collapsed')<>0 THEN RAISE EXCEPTION 'r554 undo: segments check still has the wrapper md5'; END IF;
 IF (SELECT position('pdc_ops.vehicle_location_snapshot_compute_554()' IN check_sql) FROM pdc_ops.regression_checks WHERE check_name='history_board_visibility_453')<>0 THEN RAISE EXCEPTION 'r554 undo: history check still names the compute copy'; END IF;
 IF (SELECT position('pdc_ops.vehicle_location_snapshot_compute_554()' IN check_sql) FROM pdc_ops.regression_checks WHERE check_name='board_identity_open_454')<>0 THEN RAISE EXCEPTION 'r554 undo: identity check still names the compute copy'; END IF;
 IF (SELECT position('public.get_pdc_email_vehicle_location_snapshot()' IN check_sql)=0 FROM pdc_ops.regression_checks WHERE check_name='snapshot_outer_single_eval') THEN RAISE EXCEPTION 'r554 undo: outer check lost the public function'; END IF;
END $p$;
