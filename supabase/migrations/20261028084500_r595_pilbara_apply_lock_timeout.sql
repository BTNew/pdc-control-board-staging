-- r595 (F209) / sort 365. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Preview. Craig, 28 Oct 2026 07:41 AWST: Pilbara Navision Apply was cancelled.
--
-- The 07:37 AWST deadlock pair was Craig's apply_navision_upload_profile (pid 3549135)
-- and an MCP fault_regression_check() that started at 07:36:54 AWST (pid 3551100).
-- The check's Bay 8 probe updates workshop_bays, which bumps every station revision.
-- The apply updates vehicles, which bump one station. Those two locks were taken in
-- opposite orders. The clock tick was slow in the same minute (3-22s) but it was not
-- the other side of the deadlock. Two later applies then died at the 30s role cap.
-- The public RPC lost statement_timeout=120s when it was recreated on 20 Oct with
-- only search_path. PostgREST reads that setting before the statement. A SET inside
-- the private function cannot raise it. A one-row apply is not used as a proof:
-- this upload is a full dealer snapshot and would mark about 1005 live rows missing
-- before the rollback.
--
-- Pin count stays 241. Department 135 stays fd05b9eef69498002ac06dd68e01cdff.
-- Kajel rows stay 9be0883b1a555f48f3c1ba9fa111c891 and apply stays b62fb7c29ffd2a1629f214f696e5cb14.
-- Undo: supabase/rollbacks/20261028084500_r595_pilbara_apply_lock_timeout.down.sql
-- No release-time clock window. Craig approved go-live 28 Oct 2026 08:42 AWST.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r595: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r595: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r595: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r595: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r595: Kajel apply changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r595: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_bump_station_revision(text)')) IS DISTINCT FROM '7aa472fdd742efb91d733fde081f8e70' THEN RAISE EXCEPTION 'r595: single station bump changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_bump_all_station_revisions()')) IS DISTINCT FROM '22d5581551c6bf710df1ef94e11949e4' THEN RAISE EXCEPTION 'r595: all-station bump changed'; END IF;
 IF (SELECT proconfig FROM pg_proc WHERE oid=to_regprocedure('public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint)'))
    IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[] THEN RAISE EXCEPTION 'r595: apply RPC settings are not search_path only'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=365 OR fault_id='F209' OR check_name='pilbara_apply_lock_timeout_595' OR added_in='r595') THEN RAISE EXCEPTION 'r595: sort 365 / F209 is taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_bump_station_revision(p_stage_code text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public
AS $r595one$
declare v_code text := upper(btrim(coalesce(p_stage_code, ''))); v_revision bigint;
begin
  if v_code = '' or not exists (select 1 from public.workshop_stages where code = v_code) then return null; end if;
  -- r595: same lock as the all-station bump, taken before any revision row.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc:workshop:station-revision', 0));
  insert into public.workshop_station_revision(stage_code, revision, updated_at)
  values (v_code, 1, now())
  on conflict (stage_code) do update set revision = public.workshop_station_revision.revision + 1, updated_at = now()
  returning revision into v_revision;
  return v_revision;
end;
$r595one$;

CREATE OR REPLACE FUNCTION public.workshop_bump_all_station_revisions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $r595all$
begin
  -- r595: same lock as the single-station bump, taken before any revision row.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc:workshop:station-revision', 0));
  update public.workshop_station_revision
     set revision=revision+1,updated_at=now()
   where stage_code in (select code from public.workshop_stages);
  insert into public.workshop_station_revision(stage_code,revision,updated_at)
  select code,1,now() from public.workshop_stages
  on conflict(stage_code) do nothing;
  return null;
end
$r595all$;

ALTER FUNCTION public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint) SET statement_timeout = '120s';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('pilbara_apply_lock_timeout_595','F209','Pilbara Navision apply (r595): the save is allowed 120s and station bumps take one lock',
 $chk595$SELECT
  (cfg.ok AND locks.ok AND pins.ok) AS ok,
 format('timeout %s; locks %s; pins %s', cfg.ok, locks.ok, pins.ok) AS detail
 FROM (
  SELECT (p.proconfig @> ARRAY['statement_timeout=120s']::text[])
     AND (p.proconfig @> ARRAY['search_path=pg_catalog']::text[])
     AND has_function_privilege('authenticated','public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint)','EXECUTE')
     AND NOT has_function_privilege('anon','public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint)','EXECUTE')
    AS ok
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint)')
 ) cfg
 CROSS JOIN (
  SELECT (SELECT position('pdc:workshop:station-revision' IN prosrc)>0
            AND position('pg_advisory_xact_lock' IN prosrc) < position('insert into public.workshop_station_revision' IN prosrc)
            FROM pg_proc WHERE oid=to_regprocedure('public.workshop_bump_station_revision(text)'))
     AND (SELECT position('pdc:workshop:station-revision' IN prosrc)>0
            AND position('pg_advisory_xact_lock' IN prosrc) < position('update public.workshop_station_revision' IN prosrc)
            FROM pg_proc WHERE oid=to_regprocedure('public.workshop_bump_all_station_revisions()'))
    AS ok
 ) locks
 CROSS JOIN (
  SELECT (SELECT count(*) FROM pdc_ops.expected_function_md5)=241
     AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))='fd05b9eef69498002ac06dd68e01cdff'
     AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'))='9be0883b1a555f48f3c1ba9fa111c891'
     AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)'))='b62fb7c29ffd2a1629f214f696e5cb14'
     AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)'))='3b2398e33a2ea35fc137deeedeca4af5'
    AS ok
 ) pins
$chk595$,
 true, 365, 'r595');

DO $proof$
DECLARE
  actor record;
  preview jsonb;
BEGIN
  SELECT r.email, r.auth_user_id INTO actor
  FROM public.pdc_user_roles r
  WHERE r.role::text='administrator' AND r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL
  ORDER BY r.auth_user_id
  LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', actor.auth_user_id, 'email', actor.email, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', actor.auth_user_id::text, true);
  PERFORM set_config('request.jwt.claim.email', actor.email, true);
  preview := public.preview_navision_upload_profile(
    'pilbara',
    jsonb_build_array(jsonb_build_object(
      'id','TOYOTA-ORDER-900001','order','900001','stock','13999901','batch','13999901',
      'dealer_code','014450','cosi','Yes',
      'navisionRawEvidence', jsonb_build_object('columns', jsonb_build_array(
        jsonb_build_object('header','Dealer','value','014450'),
        jsonb_build_object('header','Order','value','900001'),
        jsonb_build_object('header','Batch','value','13999901'),
        jsonb_build_object('header','COSI','value','Yes'))))),
    'r595-pilbara-sample.tsv',
    clock_timestamp());
  IF preview->>'ok' IS DISTINCT FROM 'true'
     OR preview->'data'->'items'->0->>'classification' IS DISTINCT FROM 'new'
     OR preview->'data'->'items'->0->>'dealer_code' IS DISTINCT FROM '14450' THEN
    RAISE EXCEPTION 'r595: pilbara sample did not parse (%)', preview->>'code';
  END IF;
  IF (SELECT proconfig @> ARRAY['statement_timeout=120s']::text[] FROM pg_proc WHERE oid=to_regprocedure('public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint)')) IS NOT TRUE THEN
    RAISE EXCEPTION 'r595: 120s was not published on the RPC';
  END IF;
  PERFORM set_config('request.jwt.claims','', true);
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r595: pin count changed'; END IF;
END $proof$;
