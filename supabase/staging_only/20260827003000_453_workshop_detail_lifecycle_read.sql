-- STAGING ONLY 453: RFT and Completed cards may read authoritative Workshop history.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-453-workshop-detail-lifecycle-read',0));

DO $pre$
DECLARE v_head text; d text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 d:=pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure);
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR v_head IS DISTINCT FROM '20260827002000'
   OR d IS NULL
   OR position('v.lifecycle_state=''active''' in d)=0 THEN
  RAISE EXCEPTION 'PDC_453_STAGING_HEAD_OR_PATCH_ANCHOR_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

DO $patch$
DECLARE original text; patched text;
BEGIN
 original:=pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure);
 patched:=replace(original,'v.lifecycle_state=''active''','v.lifecycle_state IN(''active'',''rft'',''completed'')');
 IF patched=original OR position('v.lifecycle_state IN(''active'',''rft'',''completed'')' in patched)=0 THEN
  RAISE EXCEPTION 'PDC_453_PATCH_FAILED' USING errcode='55000';
 END IF;
 EXECUTE patched;
END $patch$;

REVOKE ALL ON FUNCTION public.get_vehicle_workshop_detail(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_vehicle_workshop_detail(uuid) TO authenticated;

DO $post$
DECLARE d text;
BEGIN
 d:=pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure);
 IF position('v.lifecycle_state IN(''active'',''rft'',''completed'')' in d)=0
   OR has_function_privilege('public','public.get_vehicle_workshop_detail(uuid)','EXECUTE')
   OR has_function_privilege('anon','public.get_vehicle_workshop_detail(uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.get_vehicle_workshop_detail(uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.get_vehicle_workshop_detail(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_453_POSTCONDITION_FAILED' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827003000','453_workshop_detail_lifecycle_read',ARRAY[
 'The read-only authoritative Workshop detail RPC now accepts active, RFT and Completed lifecycle rows',
 'RFT Open vehicle no longer reports vehicle_not_found solely because the lifecycle is RFT',
 'Viewer-role read authority, UUID identity, immutable history and all mutation contracts remain unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
