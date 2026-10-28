-- r595 (F209) undo. Restores one-at-a-time station bumps and removes the 120s RPC timeout.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- No release-time clock window.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r595 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r595 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r595 undo: department 135 changed'; END IF;
 IF (SELECT position('pdc:workshop:station-revision' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_bump_station_revision(text)')) = 0 THEN RAISE EXCEPTION 'r595 undo: single bump is not the r595 body'; END IF;
 IF (SELECT position('pdc:workshop:station-revision' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_bump_all_station_revisions()')) = 0 THEN RAISE EXCEPTION 'r595 undo: all-station bump is not the r595 body'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_bump_station_revision(p_stage_code text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public
AS $r595undoone$
declare v_code text := upper(btrim(coalesce(p_stage_code, ''))); v_revision bigint;
begin
  if v_code = '' or not exists (select 1 from public.workshop_stages where code = v_code) then return null; end if;
  insert into public.workshop_station_revision(stage_code, revision, updated_at)
  values (v_code, 1, now())
  on conflict (stage_code) do update set revision = public.workshop_station_revision.revision + 1, updated_at = now()
  returning revision into v_revision;
  return v_revision;
end;
$r595undoone$;

CREATE OR REPLACE FUNCTION public.workshop_bump_all_station_revisions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $r595undoall$
begin
  update public.workshop_station_revision
     set revision=revision+1,updated_at=now()
   where stage_code in (select code from public.workshop_stages);
  insert into public.workshop_station_revision(stage_code,revision,updated_at)
  select code,1,now() from public.workshop_stages
  on conflict(stage_code) do nothing;
  return null;
end $r595undoall$;

ALTER FUNCTION public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint) RESET statement_timeout;

DELETE FROM pdc_ops.regression_checks WHERE check_name='pilbara_apply_lock_timeout_595' AND fault_id='F209' AND added_in='r595';

DO $proof$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_bump_station_revision(text)')) IS DISTINCT FROM '7aa472fdd742efb91d733fde081f8e70' THEN RAISE EXCEPTION 'r595 undo: single bump md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_bump_all_station_revisions()')) IS DISTINCT FROM '22d5581551c6bf710df1ef94e11949e4' THEN RAISE EXCEPTION 'r595 undo: all-station bump md5'; END IF;
 IF (SELECT proconfig FROM pg_proc WHERE oid=to_regprocedure('public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint)')) IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[] THEN RAISE EXCEPTION 'r595 undo: apply timeout still set'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pilbara_apply_lock_timeout_595') THEN RAISE EXCEPTION 'r595 undo: check remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r595 undo: pin count changed'; END IF;
END $proof$;
