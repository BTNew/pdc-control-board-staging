-- r554 (F168). Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Craig approved go-live again 26 Oct 2026. Rebased onto main 193447af (r552 / F166).
-- Live ahead of this release: r553 / F167 / sort 328 and r552 / F166 / sort 327.
-- F165 and sort 326 are retired preview numbers and are not reused.
-- Open previews still hold r541 / F155 / sort 319, r543 / F157 / sort 321 and r544 / F158 / sort 322.
-- This is the next free id: r554 / F168 / sort 329.
-- is_pdc_role stays the r421 body 39a794b23d1d63117cf549d78acba4de. That function is not rewritten.
-- Codex #534 conditional board transport and the r552 clock step stay. This release does not edit them.
-- A quiet-window eligibility miss was 2190.3 ms against a 2202.1 ms original, same JSON, so eligibility stays.
-- The location and eligibility calculations are copied unchanged. The public functions cache them for 15 seconds.
-- QC lines stay on public.get_pdc_email_vehicle_location_snapshot_pre_691 (md5 775d90e421042423670990b467f157be).
-- Pin count stays 241. The location pin stays release r454 and its prosrc_md5 moves to the public wrapper.
-- The board body stays ae706516b88574c1162e2c5889e4b4a9. The clock tick stays fa17068b106bbb9488c257e61d32e483.
-- Undo: supabase/rollbacks/20261027050000_r554_read_once_snapshots.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r554: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r554: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r554: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r554: location snapshot is not the r454 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_eligibility_snapshot()')) IS DISTINCT FROM 'f744636778e0f10128d6457605430c2f' THEN RAISE EXCEPTION 'r554: eligibility snapshot changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.is_pdc_role(public.pdc_role)')) IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r554: is_pdc_role is not the r421 body'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.is_pdc_role(public.pdc_role)') IS DISTINCT FROM 'r421' THEN RAISE EXCEPTION 'r554: role pin release moved'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_calendar_minute_available(timestamptz)')) IS DISTINCT FROM '6b53f98e01026e379d5498d668ec6cbd' THEN RAISE EXCEPTION 'r554: calendar minute changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.minute_available(timestamptz,uuid)')) IS DISTINCT FROM 'b65554007366b7fd862b3a73f3cbbc54' THEN RAISE EXCEPTION 'r554: bus minute changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'fa17068b106bbb9488c257e61d32e483' THEN RAISE EXCEPTION 'r554: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM 'ae706516b88574c1162e2c5889e4b4a9' THEN RAISE EXCEPTION 'r554: board wrapper changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot_pre_691()')) IS DISTINCT FROM '775d90e421042423670990b467f157be' THEN RAISE EXCEPTION 'r554: qc layer changed'; END IF;
 IF to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()') IS NOT NULL OR to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()') IS NOT NULL THEN RAISE EXCEPTION 'r554: compute function already exists'; END IF;
 IF to_regclass('pdc_ops.vehicle_location_snapshot_cache_554') IS NOT NULL OR to_regclass('pdc_ops.eligibility_snapshot_cache_554') IS NOT NULL THEN RAISE EXCEPTION 'r554: cache table already exists'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=329 OR fault_id='F168' OR check_name='read_once_snapshots_554' OR added_in='r554') THEN RAISE EXCEPTION 'r554: sort 329 / F168 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='vehicle_board_snapshot_cache_545' AND fault_id='F159' AND sort_order=323 AND added_in='r545') THEN RAISE EXCEPTION 'r554: r545 check missing'; END IF;
END $g$;

DO $copy$
DECLARE def text; v_owner name; n int;
BEGIN
  SELECT pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure) INTO def;
  n := (length(def)-length(replace(def,'public.get_pdc_email_vehicle_location_snapshot()','')))/length('public.get_pdc_email_vehicle_location_snapshot()');
  IF n<>1 THEN RAISE EXCEPTION 'r554: location functiondef shape %', n; END IF;
  def := regexp_replace(def, 'public\.get_pdc_email_vehicle_location_snapshot\(\)', 'pdc_ops.vehicle_location_snapshot_compute_554()');
  EXECUTE def;
  SELECT pg_get_userbyid(proowner) INTO v_owner FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()');
  EXECUTE format('ALTER FUNCTION pdc_ops.vehicle_location_snapshot_compute_554() OWNER TO %I', v_owner);
  REVOKE ALL ON FUNCTION pdc_ops.vehicle_location_snapshot_compute_554() FROM PUBLIC, anon, authenticated, service_role;
  EXECUTE format('GRANT EXECUTE ON FUNCTION pdc_ops.vehicle_location_snapshot_compute_554() TO %I', v_owner);

  SELECT pg_get_functiondef('public.get_workshop_eligibility_snapshot()'::regprocedure) INTO def;
  n := (length(def)-length(replace(def,'public.get_workshop_eligibility_snapshot()','')))/length('public.get_workshop_eligibility_snapshot()');
  IF n<>1 THEN RAISE EXCEPTION 'r554: eligibility functiondef shape %', n; END IF;
  def := regexp_replace(def, 'public\.get_workshop_eligibility_snapshot\(\)', 'pdc_ops.eligibility_snapshot_compute_554()');
  EXECUTE def;
  SELECT pg_get_userbyid(proowner) INTO v_owner FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_eligibility_snapshot()');
  EXECUTE format('ALTER FUNCTION pdc_ops.eligibility_snapshot_compute_554() OWNER TO %I', v_owner);
  REVOKE ALL ON FUNCTION pdc_ops.eligibility_snapshot_compute_554() FROM PUBLIC, anon, authenticated, service_role;
  EXECUTE format('GRANT EXECUTE ON FUNCTION pdc_ops.eligibility_snapshot_compute_554() TO %I', v_owner);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r554: location calculation changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()')) IS DISTINCT FROM 'f744636778e0f10128d6457605430c2f' THEN RAISE EXCEPTION 'r554: eligibility calculation changed'; END IF;
  IF (SELECT provolatile<>'s' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()')) THEN RAISE EXCEPTION 'r554: location calculation is not a stable definer'; END IF;
END
$copy$;

CREATE TABLE pdc_ops.vehicle_location_snapshot_cache_554 (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  email_revision bigint NOT NULL,
  snapshot jsonb NOT NULL,
  computed_at timestamptz NOT NULL
);
CREATE TABLE pdc_ops.eligibility_snapshot_cache_554 (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  workshop_revision bigint NOT NULL,
  snapshot jsonb NOT NULL,
  computed_at timestamptz NOT NULL
);
ALTER TABLE pdc_ops.vehicle_location_snapshot_cache_554 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_ops.eligibility_snapshot_cache_554 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_ops.vehicle_location_snapshot_cache_554, pdc_ops.eligibility_snapshot_cache_554 FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON TABLE pdc_ops.vehicle_location_snapshot_cache_554 IS
  'r554 (F168): one Vehicle Locations payload. No API access. The location function is the only reader and writer.';
COMMENT ON TABLE pdc_ops.eligibility_snapshot_cache_554 IS
  'r554 (F168): one planner eligibility payload. No API access. The eligibility function is the only reader and writer.';

DO $own$
DECLARE v_owner name;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(p.proowner) INTO v_owner FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()');
  EXECUTE format('ALTER TABLE pdc_ops.vehicle_location_snapshot_cache_554 OWNER TO %I', v_owner);
  SELECT pg_catalog.pg_get_userbyid(p.proowner) INTO v_owner FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()');
  EXECUTE format('ALTER TABLE pdc_ops.eligibility_snapshot_cache_554 OWNER TO %I', v_owner);
END
$own$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_role text;
  v_rev bigint;
  v_cached jsonb;
  v_lock boolean;
  v_base jsonb;
BEGIN
  v_role := public.current_pdc_user_role()::text;
  IF v_role IS NULL OR v_role NOT IN ('viewer','operator','importer','administrator') THEN
    RETURN pdc_ops.vehicle_location_snapshot_compute_554();
  END IF;
  SELECT r.revision INTO v_rev FROM public.pdc_email_vehicle_revision r WHERE r.singleton;
  v_rev := coalesce(v_rev, 0);
  SELECT c.snapshot INTO v_cached
  FROM pdc_ops.vehicle_location_snapshot_cache_554 c
  WHERE c.singleton
    AND c.email_revision = v_rev
    AND c.computed_at > clock_timestamp() - interval '15 seconds';
  IF v_cached IS NOT NULL THEN
    RETURN v_cached;
  END IF;
  v_lock := pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r554-vehicle-location', 0));
  IF NOT v_lock THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r554-vehicle-location', 0));
    SELECT r.revision INTO v_rev FROM public.pdc_email_vehicle_revision r WHERE r.singleton;
    v_rev := coalesce(v_rev, 0);
    SELECT c.snapshot INTO v_cached
    FROM pdc_ops.vehicle_location_snapshot_cache_554 c
    WHERE c.singleton
      AND c.email_revision = v_rev
      AND c.computed_at > clock_timestamp() - interval '15 seconds';
    IF v_cached IS NOT NULL THEN
      RETURN v_cached;
    END IF;
  END IF;
  v_base := pdc_ops.vehicle_location_snapshot_compute_554();
  IF coalesce((v_base->>'ok')::boolean, false)
     AND jsonb_typeof(v_base#>'{data,vehicles}') = 'array' THEN
    INSERT INTO pdc_ops.vehicle_location_snapshot_cache_554 (singleton, email_revision, snapshot, computed_at)
    VALUES (true, v_rev, v_base, clock_timestamp())
    ON CONFLICT (singleton) DO UPDATE
      SET email_revision = EXCLUDED.email_revision,
          snapshot = EXCLUDED.snapshot,
          computed_at = EXCLUDED.computed_at
      WHERE vehicle_location_snapshot_cache_554.singleton;
  END IF;
  RETURN v_base;
END
$function$;

CREATE OR REPLACE FUNCTION public.get_workshop_eligibility_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_rev bigint;
  v_cached jsonb;
  v_lock boolean;
  v_base jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pdc_ops.eligibility_snapshot_compute_554();
  END IF;
  PERFORM public.require_pdc_role('viewer');
  SELECT r.revision INTO v_rev FROM public.workshop_revision r WHERE r.id = 1;
  v_rev := coalesce(v_rev, 0);
  SELECT c.snapshot INTO v_cached
  FROM pdc_ops.eligibility_snapshot_cache_554 c
  WHERE c.singleton
    AND c.workshop_revision = v_rev
    AND c.computed_at > clock_timestamp() - interval '15 seconds';
  IF v_cached IS NOT NULL THEN
    RETURN v_cached;
  END IF;
  v_lock := pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r554-eligibility', 0));
  IF NOT v_lock THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r554-eligibility', 0));
    SELECT r.revision INTO v_rev FROM public.workshop_revision r WHERE r.id = 1;
    v_rev := coalesce(v_rev, 0);
    SELECT c.snapshot INTO v_cached
    FROM pdc_ops.eligibility_snapshot_cache_554 c
    WHERE c.singleton
      AND c.workshop_revision = v_rev
      AND c.computed_at > clock_timestamp() - interval '15 seconds';
    IF v_cached IS NOT NULL THEN
      RETURN v_cached;
    END IF;
  END IF;
  v_base := pdc_ops.eligibility_snapshot_compute_554();
  IF jsonb_typeof(v_base) = 'object'
     AND coalesce(v_base->>'code', '') IS DISTINCT FROM 'unauthorized' THEN
    INSERT INTO pdc_ops.eligibility_snapshot_cache_554 (singleton, workshop_revision, snapshot, computed_at)
    VALUES (true, v_rev, v_base, clock_timestamp())
    ON CONFLICT (singleton) DO UPDATE
      SET workshop_revision = EXCLUDED.workshop_revision,
          snapshot = EXCLUDED.snapshot,
          computed_at = EXCLUDED.computed_at
      WHERE eligibility_snapshot_cache_554.singleton;
  END IF;
  RETURN v_base;
END
$function$;

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_workshop_eligibility_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_workshop_eligibility_snapshot() TO authenticated, service_role;
COMMENT ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() IS
  'r554 (F168): vehicle location snapshot. One shared copy for 15 seconds, dropped when pdc_email_vehicle_revision changes. Calculation md5 e7f77fad301b8a87ef548472a8f790a6.';
COMMENT ON FUNCTION public.get_workshop_eligibility_snapshot() IS
  'r554 (F168): planner eligibility snapshot. One shared copy for 15 seconds, dropped when workshop_revision changes. Calculation md5 f744636778e0f10128d6457605430c2f.';

DO $wrap$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '2067547fafa49f0bfeb54c4bc18a824e' THEN RAISE EXCEPTION 'r554: location wrapper md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_eligibility_snapshot()')) IS DISTINCT FROM '9207f7c1664552122775bb4a2e6d9f25' THEN RAISE EXCEPTION 'r554: eligibility wrapper md5'; END IF;
END $wrap$;

CREATE FUNCTION public.workshop_settings_bag_554()
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $function$
DECLARE raw text; bag jsonb;
BEGIN
  raw := current_setting('pdc.r554_settings', true);
  IF raw IS NOT NULL AND raw <> '' THEN
    RETURN raw::jsonb;
  END IF;
  SELECT coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) INTO bag FROM public.workshop_settings s;
  PERFORM set_config('pdc.r554_settings', bag::text, true);
  RETURN bag;
END
$function$;

CREATE FUNCTION public.workshop_bay_stage_554(p_bay_id uuid, OUT bay_number integer, OUT code text)
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $function$
DECLARE raw text; bag jsonb; row jsonb;
BEGIN
  raw := current_setting('pdc.r554_bays', true);
  IF raw IS NULL OR raw = '' THEN
    SELECT coalesce(jsonb_object_agg(b.id::text, jsonb_build_object('bay_number', b.bay_number, 'code', s.code)), '{}'::jsonb)
    INTO bag
    FROM public.workshop_bays b
    JOIN public.workshop_stages s ON s.id = b.stage_id;
    PERFORM set_config('pdc.r554_bays', bag::text, true);
  ELSE
    bag := raw::jsonb;
  END IF;
  row := bag -> p_bay_id::text;
  bay_number := (row->>'bay_number')::integer;
  code := row->>'code';
END
$function$;

REVOKE ALL ON FUNCTION public.workshop_settings_bag_554(), public.workshop_bay_stage_554(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.r554_clear_read_once()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO pg_catalog
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'workshop_settings' THEN
    PERFORM set_config('pdc.r554_settings', '', true);
  ELSE
    PERFORM set_config('pdc.r554_bays', '', true);
  END IF;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION public.r554_clear_read_once() FROM PUBLIC, anon, authenticated, service_role;

DO $grant$
DECLARE v_owner name;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO v_owner FROM pg_proc WHERE oid=to_regprocedure('public.workshop_calendar_minute_available(timestamptz)');
  EXECUTE format('GRANT EXECUTE ON FUNCTION public.workshop_settings_bag_554(), public.workshop_bay_stage_554(uuid), public.r554_clear_read_once() TO %I', v_owner);
  EXECUTE format('ALTER FUNCTION public.workshop_settings_bag_554() OWNER TO %I', v_owner);
  EXECUTE format('ALTER FUNCTION public.workshop_bay_stage_554(uuid) OWNER TO %I', v_owner);
  EXECUTE format('ALTER FUNCTION public.r554_clear_read_once() OWNER TO %I', v_owner);
END
$grant$;

CREATE TRIGGER r554_workshop_settings_read_once
  AFTER INSERT OR UPDATE OR DELETE ON public.workshop_settings
  FOR EACH STATEMENT EXECUTE FUNCTION public.r554_clear_read_once();
CREATE TRIGGER r554_workshop_bays_read_once
  AFTER INSERT OR UPDATE OR DELETE ON public.workshop_bays
  FOR EACH STATEMENT EXECUTE FUNCTION public.r554_clear_read_once();
CREATE TRIGGER r554_workshop_stages_read_once
  AFTER INSERT OR UPDATE OR DELETE ON public.workshop_stages
  FOR EACH STATEMENT EXECUTE FUNCTION public.r554_clear_read_once();

DO $rew$
DECLARE def text;
BEGIN
  SELECT pg_get_functiondef('public.workshop_calendar_minute_available(timestamptz)'::regprocedure) INTO def;
  IF position('select jsonb_object_agg(key,value) into v_settings from public.workshop_settings' IN def)=0 THEN
    RAISE EXCEPTION 'r554: calendar settings read not found';
  END IF;
  def := replace(def, $old$
  select jsonb_object_agg(key,value) into v_settings from public.workshop_settings
  where key in('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');$old$,
  $new$
  v_settings:=public.workshop_settings_bag_554();$new$);
  IF position('workshop_settings_bag_554' IN def)=0 THEN RAISE EXCEPTION 'r554: calendar rewrite missed'; END IF;
  EXECUTE def;

  SELECT pg_get_functiondef('pdc_bus_private.minute_available(timestamptz,uuid)'::regprocedure) INTO def;
  IF position('SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;' IN def)=0
     OR position('SELECT coalesce(value,''[]''::jsonb) INTO breaks FROM public.workshop_settings WHERE key=''break_windows'';' IN def)=0 THEN
    RAISE EXCEPTION 'r554: bus minute reads not found';
  END IF;
  def := replace(def,
    'SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;',
    'SELECT f.bay_number, f.code INTO bay, code FROM public.workshop_bay_stage_554(p_bay_id) f;');
  def := replace(def,
    'SELECT coalesce(value,''[]''::jsonb) INTO breaks FROM public.workshop_settings WHERE key=''break_windows'';' || E'\n' ||
    ' SELECT coalesce(value,''[]''::jsonb) INTO closures FROM public.workshop_settings WHERE key=''closures'';',
    'breaks:=coalesce(public.workshop_settings_bag_554()->''break_windows'',''[]''::jsonb);' || E'\n' ||
    ' closures:=coalesce(public.workshop_settings_bag_554()->''closures'',''[]''::jsonb);');
  IF position('workshop_settings_bag_554' IN def)=0 OR position('workshop_bay_stage_554' IN def)=0 THEN
    RAISE EXCEPTION 'r554: bus minute rewrite missed';
  END IF;
  EXECUTE def;
END
$rew$;

DO $prove$
DECLARE
  v_uid uuid;
  v_email text;
  t0 timestamptz;
  j1 jsonb;
  j2 jsonb;
  loc_compute_ms numeric;
  loc_miss_ms numeric;
  elig_compute_ms numeric;
  elig_miss_ms numeric;
  loc_md5 text;
  elig_md5 text;
  qc int;
  vehicles int;
BEGIN
  SELECT r.auth_user_id, r.email INTO v_uid, v_email
  FROM public.pdc_user_roles r
  WHERE r.role::text='administrator' AND r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL
  ORDER BY r.auth_user_id
  LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'r554: no administrator'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'email', v_email)::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
  PERFORM set_config('request.jwt.claim.email', v_email, true);
  t0 := clock_timestamp();
  j1 := pdc_ops.vehicle_location_snapshot_compute_554();
  loc_compute_ms := round((extract(epoch FROM clock_timestamp()-t0)*1000)::numeric, 1);
  t0 := clock_timestamp();
  j2 := public.get_pdc_email_vehicle_location_snapshot();
  loc_miss_ms := round((extract(epoch FROM clock_timestamp()-t0)*1000)::numeric, 1);
  IF md5(j1::text) IS DISTINCT FROM md5(j2::text) THEN
    RAISE EXCEPTION 'r554: location payload differs compute % wrapper %', md5(j1::text), md5(j2::text);
  END IF;
  loc_md5 := md5(j2::text);
  vehicles := jsonb_array_length(j2#>'{data,vehicles}');
  SELECT count(*) INTO qc FROM jsonb_array_elements(j2#>'{data,vehicles}') v WHERE v ? 'qc_operation_lines';
  IF coalesce((j2->>'ok')::boolean, false) IS NOT TRUE OR qc < 1 THEN
    RAISE EXCEPTION 'r554: location payload not ok or qc_operation_lines missing';
  END IF;
  t0 := clock_timestamp();
  j1 := pdc_ops.eligibility_snapshot_compute_554();
  elig_compute_ms := round((extract(epoch FROM clock_timestamp()-t0)*1000)::numeric, 1);
  t0 := clock_timestamp();
  j2 := public.get_workshop_eligibility_snapshot();
  elig_miss_ms := round((extract(epoch FROM clock_timestamp()-t0)*1000)::numeric, 1);
  IF md5(j1::text) IS DISTINCT FROM md5(j2::text) THEN
    RAISE EXCEPTION 'r554: eligibility payload differs compute % wrapper %', md5(j1::text), md5(j2::text);
  END IF;
  elig_md5 := md5(j2::text);
  IF jsonb_typeof(j2) IS DISTINCT FROM 'object' OR coalesce(j2->>'code','') = 'unauthorized' THEN
    RAISE EXCEPTION 'r554: eligibility payload not cacheable';
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.email', '', true);
  CREATE TEMP TABLE r554_proof (
    loc_payload text, qc int, vehicles int,
    loc_compute_ms numeric, loc_miss_ms numeric,
    elig_payload text, elig_compute_ms numeric, elig_miss_ms numeric
  );
  INSERT INTO r554_proof VALUES (loc_md5, qc, vehicles, loc_compute_ms, loc_miss_ms, elig_md5, elig_compute_ms, elig_miss_ms);
END
$prove$;

UPDATE pdc_ops.expected_function_md5
 SET prosrc_md5='2067547fafa49f0bfeb54c4bc18a824e',
     note='r554 (F168): public wrapper md5 2067547fafa49f0bfeb54c4bc18a824e (old e7f77fad301b8a87ef548472a8f790a6). Calculation copy pdc_ops.vehicle_location_snapshot_compute_554 stays e7f77fad301b8a87ef548472a8f790a6. release stays r454 so board_identity_open_454 still counts 6.',
     updated_at=now()
 WHERE signature='public.get_pdc_email_vehicle_location_snapshot()'
   AND release='r454'
   AND prosrc_md5='e7f77fad301b8a87ef548472a8f790a6';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(replace(check_sql,
   '(''public.get_pdc_email_vehicle_location_snapshot()'', ''get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()'', NULL, ''outer'')',
   '(''pdc_ops.vehicle_location_snapshot_compute_554()'', ''get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()'', NULL, ''outer'')'),
   'AND kept.n = 13 AS ok',
   'AND kept.n = 13 AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'' AS ok'),
   '|| kept.n || ''/13 old layer functions kept for undo'' AS detail',
   '|| kept.n || ''/13 old layer functions kept for undo; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e'' AS detail')
 WHERE check_name='snapshot_segments_collapsed'
   AND position('public.get_pdc_email_vehicle_location_snapshot()' IN check_sql)>0;

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(check_sql,
   '''public.get_pdc_email_vehicle_location_snapshot()''',
   '''pdc_ops.vehicle_location_snapshot_compute_554()'''),
   'SELECT s.bad = 0 AND coalesce(s.outer_ok, false) AS ok',
   'SELECT s.bad = 0 AND coalesce(s.outer_ok, false) AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'' AS ok')
 WHERE check_name='snapshot_outer_single_eval';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(check_sql,
   'ELSE ''NOT as r412 left it'' END AS detail',
   'ELSE ''NOT as r412 left it'' END || ''; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e'' AS detail')
 WHERE check_name='snapshot_outer_single_eval';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(replace(check_sql,
   'to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()'')',
   'to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()'')'),
   'AND coalesce((SELECT ok FROM uses),false) AS ok',
   'AND coalesce((SELECT ok FROM uses),false) AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'' AS ok'),
   '||''; vehicles on the board now: ''||(SELECT n FROM board) AS detail',
   '||''; vehicles on the board now: ''||(SELECT n FROM board)||''; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e'' AS detail')
 WHERE check_name='history_board_visibility_453';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(replace(check_sql,
   'pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''),',
   'pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''),' || E'\n' ||
   '     pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''),'),
   'AND (SELECT other FROM dealer_users)=0 AS ok',
   'AND (SELECT other FROM dealer_users)=0 AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'' AS ok'),
   '||''; active/RFT vehicles whose dealer comes from their own source record: ''||(SELECT n FROM found) AS detail',
   '||''; active/RFT vehicles whose dealer comes from their own source record: ''||(SELECT n FROM found)||''; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e'' AS detail')
 WHERE check_name='board_identity_open_454';

UPDATE pdc_ops.regression_checks
 SET check_sql = replace(replace(check_sql,
   '(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''e7f77fad301b8a87ef548472a8f790a6''',
   '(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(''pdc_ops.vehicle_location_snapshot_compute_554()''))=''e7f77fad301b8a87ef548472a8f790a6'' AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(''public.get_pdc_email_vehicle_location_snapshot()''))=''2067547fafa49f0bfeb54c4bc18a824e'''),
   'revision reread %s',
   'revision reread %s; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e')
 WHERE check_name='vehicle_board_snapshot_cache_545'
   AND position('e7f77fad301b8a87ef548472a8f790a6' IN check_sql)>0;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('read_once_snapshots_554','F168',
  'Read-once snapshots (r554). Location and eligibility calculations are unchanged. is_pdc_role is unchanged. QC lines are written by pre_691. Old location md5 e7f77fad301b8a87ef548472a8f790a6 new public md5 2067547fafa49f0bfeb54c4bc18a824e. Old eligibility md5 f744636778e0f10128d6457605430c2f new public md5 9207f7c1664552122775bb4a2e6d9f25.',
 $chk554$SELECT
  (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()'))='e7f77fad301b8a87ef548472a8f790a6'
  AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()'))='2067547fafa49f0bfeb54c4bc18a824e'
  AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('pdc_ops.eligibility_snapshot_compute_554()'))='f744636778e0f10128d6457605430c2f'
  AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_workshop_eligibility_snapshot()'))='9207f7c1664552122775bb4a2e6d9f25'
  AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.is_pdc_role(public.pdc_role)'))='39a794b23d1d63117cf549d78acba4de'
  AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.is_pdc_role(public.pdc_role)')='r421'
  AND (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.is_pdc_role(public.pdc_role)')='39a794b23d1d63117cf549d78acba4de'
  AND (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_location_snapshot()')='r454'
  AND (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_location_snapshot()')='2067547fafa49f0bfeb54c4bc18a824e'
  AND (SELECT p.provolatile='v' AND p.prosecdef
        AND position('pdc-r554-vehicle-location' IN p.prosrc)>0
        AND position('WHERE vehicle_location_snapshot_cache_554.singleton' IN p.prosrc)>0
        AND position('interval ''15 seconds''' IN p.prosrc)>0
        AND (length(p.prosrc)-length(replace(p.prosrc,'FROM public.pdc_email_vehicle_revision','')))/length('FROM public.pdc_email_vehicle_revision')=2
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()'))
  AND (SELECT p.provolatile='v' AND p.prosecdef
        AND position('pdc-r554-eligibility' IN p.prosrc)>0
        AND position('WHERE eligibility_snapshot_cache_554.singleton' IN p.prosrc)>0
        AND (length(p.prosrc)-length(replace(p.prosrc,'FROM public.workshop_revision','')))/length('FROM public.workshop_revision')=2
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_workshop_eligibility_snapshot()'))
  AND (SELECT position('pdc_qc_operation_lines_379' IN prosrc)>0 AND md5(prosrc)='775d90e421042423670990b467f157be'
       FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_location_snapshot_pre_691()'))
  AND (SELECT position('get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1' IN prosrc)>0
       FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()'))
  AND (SELECT position('workshop_settings_bag_554' IN prosrc)>0
       FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_calendar_minute_available(timestamptz)'))
  AND (SELECT position('workshop_settings_bag_554' IN prosrc)>0 AND position('workshop_bay_stage_554' IN prosrc)>0
       FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('pdc_bus_private.minute_available(timestamptz,uuid)'))
  AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)'))='fa17068b106bbb9488c257e61d32e483'
  AND (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()'))='ae706516b88574c1162e2c5889e4b4a9'
  AND (SELECT c.relrowsecurity AND NOT c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid='pdc_ops.vehicle_location_snapshot_cache_554'::regclass)
  AND (SELECT c.relrowsecurity AND NOT c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid='pdc_ops.eligibility_snapshot_cache_554'::regclass)
  AND NOT has_table_privilege('anon','pdc_ops.vehicle_location_snapshot_cache_554','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege('authenticated','pdc_ops.vehicle_location_snapshot_cache_554','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege('service_role','pdc_ops.vehicle_location_snapshot_cache_554','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege('anon','pdc_ops.eligibility_snapshot_cache_554','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege('authenticated','pdc_ops.eligibility_snapshot_cache_554','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_function_privilege('anon','pdc_ops.vehicle_location_snapshot_compute_554()','EXECUTE')
  AND NOT has_function_privilege('authenticated','pdc_ops.vehicle_location_snapshot_compute_554()','EXECUTE')
  AND NOT has_function_privilege('anon','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
  AND has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
  AND has_function_privilege('authenticated','public.get_workshop_eligibility_snapshot()','EXECUTE')
  AND timed.ms < 2000
 AS ok,
 format('3000 calendar checks in %s ms; old md5 e7f77fad301b8a87ef548472a8f790a6 new md5 2067547fafa49f0bfeb54c4bc18a824e; old eligibility md5 f744636778e0f10128d6457605430c2f new md5 9207f7c1664552122775bb4a2e6d9f25; qc writer pre_691 md5 775d90e421042423670990b467f157be; payload_md5=PENDING', timed.ms) AS detail
 FROM (
   SELECT round(extract(epoch FROM clock_timestamp()-t0)*1000,1) AS ms
   FROM (SELECT clock_timestamp() AS t0) s,
   LATERAL (
     SELECT count(*) AS n FROM generate_series(1,3000) g
     WHERE public.workshop_calendar_minute_available(timestamptz '2026-10-26 10:00+08' + g * interval '1 minute') IS NOT NULL
        OR true
   ) calls
 ) timed$chk554$,
 true, 329, 'r554');

UPDATE pdc_ops.regression_checks c
 SET description = c.description || format(
   ' Proved identical JSON in this migration. Location payload %s, %s vehicles, %s with qc_operation_lines, calculation %s ms, wrapper miss %s ms. Eligibility payload %s, calculation %s ms, wrapper miss %s ms.',
   p.loc_payload, p.vehicles, p.qc, p.loc_compute_ms, p.loc_miss_ms, p.elig_payload, p.elig_compute_ms, p.elig_miss_ms),
     check_sql = replace(c.check_sql, 'payload_md5=PENDING',
       format('payload_md5=%s qc=%s elig_payload_md5=%s', p.loc_payload, p.qc, p.elig_payload))
 FROM r554_proof p
 WHERE c.check_name='read_once_snapshots_554'
   AND position('payload_md5=PENDING' IN c.check_sql)>0;

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r554: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r454')<>6 THEN RAISE EXCEPTION 'r554: r454 pin count changed'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_location_snapshot()' AND release='r454') IS DISTINCT FROM '2067547fafa49f0bfeb54c4bc18a824e' THEN RAISE EXCEPTION 'r554: location pin was not moved'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.is_pdc_role(public.pdc_role)' AND release='r421') IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r554: role pin changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.is_pdc_role(public.pdc_role)')) IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r554: role body changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'fa17068b106bbb9488c257e61d32e483' THEN RAISE EXCEPTION 'r554: clock changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM 'ae706516b88574c1162e2c5889e4b4a9' THEN RAISE EXCEPTION 'r554: board changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='snapshot_segments_collapsed' AND position('pdc_ops.vehicle_location_snapshot_compute_554()' IN check_sql)>0 AND position('2067547fafa49f0bfeb54c4bc18a824e' IN check_sql)>0 AND position('e7f77fad301b8a87ef548472a8f790a6' IN check_sql)>0)<>1 THEN RAISE EXCEPTION 'r554: segments check not retargeted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='snapshot_outer_single_eval' AND position('pdc_ops.vehicle_location_snapshot_compute_554()' IN check_sql)>0 AND position('2067547fafa49f0bfeb54c4bc18a824e' IN check_sql)>0 AND position('public.get_pdc_email_vehicle_location_snapshot()'', ''s'', true' IN check_sql)=0)<>1 THEN RAISE EXCEPTION 'r554: outer check not retargeted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='history_board_visibility_453' AND position('pdc_ops.vehicle_location_snapshot_compute_554()' IN check_sql)>0 AND position('2067547fafa49f0bfeb54c4bc18a824e' IN check_sql)>0)<>1 THEN RAISE EXCEPTION 'r554: history check not retargeted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='board_identity_open_454' AND position('pdc_ops.vehicle_location_snapshot_compute_554()' IN check_sql)>0 AND position('2067547fafa49f0bfeb54c4bc18a824e' IN check_sql)>0)<>1 THEN RAISE EXCEPTION 'r554: identity check not retargeted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='vehicle_board_snapshot_cache_545' AND position('pdc_ops.vehicle_location_snapshot_compute_554()' IN check_sql)>0 AND position('2067547fafa49f0bfeb54c4bc18a824e' IN check_sql)>0)<>1 THEN RAISE EXCEPTION 'r554: r545 check not retargeted'; END IF;
 IF (SELECT position('payload_md5=PENDING' IN check_sql) FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554')<>0 THEN RAISE EXCEPTION 'r554: payload proof was not recorded'; END IF;
 IF (SELECT qc FROM r554_proof) < 1 THEN RAISE EXCEPTION 'r554: qc proof missing'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554' AND fault_id='F168' AND sort_order=329 AND added_in='r554' AND enabled)<>1 THEN RAISE EXCEPTION 'r554: check missing'; END IF;
 IF (SELECT position(p.loc_payload IN c.check_sql)=0 FROM pdc_ops.regression_checks c, r554_proof p WHERE c.check_name='read_once_snapshots_554') THEN RAISE EXCEPTION 'r554: location payload md5 not in the check'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r554: pins drifted'; END IF;
END $p$;
