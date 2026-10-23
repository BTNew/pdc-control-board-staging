-- r519 (F133): clear current JITA ETA rows on staging. Craig asked to hide the paste and clear dates already written.
-- Staging cdsmnqxtyyoeoznmbidd only. Never production. Run between :02 and :45.
-- The board date is public.pdc_jita_eta.eta_date where superseded is false (one current row per vehicle).
-- This marks those rows superseded and keeps a copy in pdc_ops.r519_jita_eta_clear for the down SQL.
-- It does not update public.pdc_parts_eta, public.pdc_parts_eta_audit, or public.vehicle_parts_updates.
-- It does not replace set_parts_eta, get_pdc_parts_eta_board, or the r518 Parts Jita tick.
-- It does not drop the r516 paste functions. This is not a rollback of r516 or r518.
-- Undo: supabase/rollbacks/20261023233000_r519_clear_jita_eta.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r519: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r519: staging only'; END IF;
 IF to_regclass('pdc_ops.r519_jita_eta_clear') IS NOT NULL
    OR EXISTS(SELECT 1 FROM public.pdc_jita_eta_audit WHERE status='cleared_r519')
  THEN RAISE EXCEPTION 'r519: already applied'; END IF;
 IF to_regclass('public.pdc_jita_eta') IS NULL OR to_regprocedure('public.get_pdc_jita_eta_board()') IS NULL THEN RAISE EXCEPTION 'r519: JITA ETA table is missing'; END IF;
 IF to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)') IS NULL
    OR to_regclass('pdc_ops.r518_parts_jita_tick_audit') IS NULL
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r518')<>2
  THEN RAISE EXCEPTION 'r519: r518 Parts Jita tick is missing; refusing to clear without it'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>230 THEN RAISE EXCEPTION 'r519: pin count is not 230'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r519: set_parts_eta is not the r436 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec' THEN RAISE EXCEPTION 'r519: get_pdc_parts_eta_board is not the r436 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.import_jita_eta_516(text,boolean)')) IS DISTINCT FROM '46c1cae33eb789cf362e5db461baa971' THEN RAISE EXCEPTION 'r519: import_jita_eta_516 is not the r516 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_jita_eta_board()')) IS DISTINCT FROM '29dcb35956acd61b6a8aa2ca07a80182' THEN RAISE EXCEPTION 'r519: get_pdc_jita_eta_board is not the r516 body'; END IF;
 PERFORM set_config('pdc.r519_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r519_jita_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)')),true);
 PERFORM set_config('pdc.r519_r518_n',(SELECT count(*)::text FROM pdc_ops.r518_parts_jita_tick_audit),true);
 PERFORM set_config('pdc.r519_parts',(SELECT md5(count(*)::text||':'||coalesce(sum(hashtext(id::text||':'||coalesce(eta_date::text,'')||':'||superseded::text))::text,'0')) FROM public.pdc_parts_eta),true);
 PERFORM set_config('pdc.r519_parts_audit',(SELECT count(*)::text FROM public.pdc_parts_eta_audit),true);
 PERFORM set_config('pdc.r519_worst',(SELECT md5(count(*)::text||':'||coalesce(sum(hashtext(vehicle_id::text||':'||coalesce(worst_eta::text,'')||':'||parts_received::text||':'||coalesce(parts_ordered::text,'')))::text,'0')) FROM public.vehicle_parts_updates),true);
END $g$;

CREATE TABLE pdc_ops.r519_jita_eta_clear (
  jita_eta_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  stock_number text NOT NULL,
  eta_date date NOT NULL,
  rule text NOT NULL,
  cleared_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_ops.r519_jita_eta_clear ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_ops.r519_jita_eta_clear FROM PUBLIC, anon, authenticated, service_role;

WITH cleared AS (
  UPDATE public.pdc_jita_eta
  SET superseded = true,
      superseded_at = clock_timestamp(),
      superseded_by = 'a5190519-0519-4519-8519-000000000519'::uuid
  WHERE NOT superseded
  RETURNING id, vehicle_id, stock_number, eta_date, rule
)
INSERT INTO pdc_ops.r519_jita_eta_clear(jita_eta_id, vehicle_id, stock_number, eta_date, rule)
SELECT id, vehicle_id, stock_number, eta_date, rule FROM cleared;

INSERT INTO public.pdc_jita_eta_audit(actor, actor_role, dry_run, status, result)
SELECT 'r519', 'staging-clear', false, 'cleared_r519',
  jsonb_build_object(
    'cleared', (SELECT count(*) FROM pdc_ops.r519_jita_eta_clear),
    'sentinel', 'a5190519-0519-4519-8519-000000000519',
    'sample_13102912', (SELECT eta_date FROM pdc_ops.r519_jita_eta_clear WHERE stock_number='13102912')
  );

DO $g$ DECLARE y record; BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_jita_eta WHERE NOT superseded) THEN RAISE EXCEPTION 'r519: a current JITA ETA remains'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_jita_eta WHERE stock_number='13102912' AND NOT superseded) THEN RAISE EXCEPTION 'r519: stock 13102912 still has a current JITA ETA'; END IF;
 IF (SELECT count(*) FROM pdc_ops.r519_jita_eta_clear)<>(SELECT count(*) FROM public.pdc_jita_eta WHERE superseded_by='a5190519-0519-4519-8519-000000000519'::uuid) THEN RAISE EXCEPTION 'r519: archive count does not match the cleared rows'; END IF;
 IF (SELECT md5(count(*)::text||':'||coalesce(sum(hashtext(id::text||':'||coalesce(eta_date::text,'')||':'||superseded::text))::text,'0')) FROM public.pdc_parts_eta) IS DISTINCT FROM current_setting('pdc.r519_parts') THEN RAISE EXCEPTION 'r519: pdc_parts_eta changed'; END IF;
 IF (SELECT count(*)::text FROM public.pdc_parts_eta_audit) IS DISTINCT FROM current_setting('pdc.r519_parts_audit') THEN RAISE EXCEPTION 'r519: pdc_parts_eta_audit changed'; END IF;
 IF (SELECT md5(count(*)::text||':'||coalesce(sum(hashtext(vehicle_id::text||':'||coalesce(worst_eta::text,'')||':'||parts_received::text||':'||coalesce(parts_ordered::text,'')))::text,'0')) FROM public.vehicle_parts_updates) IS DISTINCT FROM current_setting('pdc.r519_worst') THEN RAISE EXCEPTION 'r519: vehicle_parts_updates changed'; END IF;
 IF (SELECT count(*)::text FROM pdc_ops.r518_parts_jita_tick_audit) IS DISTINCT FROM current_setting('pdc.r519_r518_n') THEN RAISE EXCEPTION 'r519: r518 tick audit changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)')) IS DISTINCT FROM current_setting('pdc.r519_jita_tick') THEN RAISE EXCEPTION 'r519: r518 tick function changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r519_tick') THEN RAISE EXCEPTION 'r519: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r519: set_parts_eta changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>230 THEN RAISE EXCEPTION 'r519: pin count changed'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='jita_eta_upload_516') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r519: jita_eta_upload_516 not OK: %', y.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='navision_jita_station_tick_518') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r519: navision_jita_station_tick_518 not OK: %', y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
 RAISE NOTICE 'r519 cleared % JITA ETA rows', (SELECT count(*) FROM pdc_ops.r519_jita_eta_clear);
END $g$;
