-- STAGING ONLY: expose immutable hours-correction provenance in the authoritative detail DTO.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010100-craig-hours-provenance-read-model',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
 SELECT version INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260904010000'
    OR to_regprocedure('public.get_vehicle_workshop_detail(uuid)') IS NULL
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904010100')
 THEN RAISE EXCEPTION 'PDC_20260904010100_STAGING_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

DO $patch$
DECLARE original text; patched text; needle text;
BEGIN
 original:=pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure);
 needle:='''description'',a.description,''estimated_hours'',a.estimated_hours,''version'',a.version,''created_at'',a.created_at,''updated_at'',a.updated_at)';
 IF position('''correction_origin'',a.correction_origin' in original)>0 OR position(needle in original)=0 THEN
   RAISE EXCEPTION 'PDC_20260904010100_DETAIL_SHAPE_DRIFT' USING errcode='55000';
 END IF;
 patched:=replace(original,needle,
   '''description'',a.description,''estimated_hours'',a.estimated_hours,''correction_origin'',a.correction_origin,''manual_assignment_locked'',a.manual_assignment_locked,''version'',a.version,''created_at'',a.created_at,''updated_at'',a.updated_at)');
 EXECUTE patched;
END $patch$;

REVOKE ALL ON FUNCTION public.get_vehicle_workshop_detail(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_vehicle_workshop_detail(uuid) TO authenticated;

DO $post$
DECLARE d text;
BEGIN
 d:=pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure);
 IF position('''correction_origin'',a.correction_origin' in d)=0
    OR position('''manual_assignment_locked'',a.manual_assignment_locked' in d)=0
    OR has_function_privilege('public','public.get_vehicle_workshop_detail(uuid)','EXECUTE')
    OR has_function_privilege('anon','public.get_vehicle_workshop_detail(uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.get_vehicle_workshop_detail(uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.get_vehicle_workshop_detail(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'PDC_20260904010100_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904010100','craig_hours_provenance_read_model',ARRAY[
 'Guarded STAGING-only successor exposing correction provenance through the authoritative vehicle Workshop detail DTO',
 'SECURITY DEFINER search_path and least-privilege execute grants preserved; source evidence and RLS unchanged',
 'Production untouched'
]);
COMMIT;
