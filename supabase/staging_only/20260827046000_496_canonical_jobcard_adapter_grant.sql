-- STAGING ONLY 496: restore typed canonical Job Card adapter execution to authenticated identities; function-internal importer/writer gates remain authoritative.
BEGIN;
SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-496-canonical-jobcard-adapter-grant',0));
DO $guard$ DECLARE v_head text;BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  OR v_head IS DISTINCT FROM '20260827045000'
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827045000' AND name='495_archive_navision_reconcile_order')
  OR encode(extensions.digest(convert_to(pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')<>'d84f03903eec8ca6b7b345426c1d233b94cfa0536164e9a75e51f6a06daf3908'
  OR position('r.role in(''viewer'',''importer'')' in pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure))=0
  OR position('pdc_monitor_stage_activation_writers' in pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure))=0
 THEN RAISE EXCEPTION 'PDC_496_TARGET_HEAD_FUNCTION_OR_INTERNAL_GATE_MISMATCH' USING errcode='55000';END IF;
END $guard$;
REVOKE ALL ON FUNCTION public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) TO authenticated;
DO $post$ BEGIN
 IF has_function_privilege('public','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
  OR has_function_privilege('anon','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
  OR has_function_privilege('service_role','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'PDC_496_CANONICAL_ADAPTER_ACL_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827046000','496_canonical_jobcard_adapter_grant',ARRAY[
 'Restore PostgREST execution for the authenticated role on the typed canonical Job Card attachment adapter',
 'Retain exact actor role, approved account and active staging writer checks inside the security-definer function',
 'Keep public, anon and service_role execution denied',
 'Production untouched'
]);NOTIFY pgrst,'reload schema';COMMIT;
