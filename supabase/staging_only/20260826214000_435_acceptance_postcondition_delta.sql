-- STAGING ONLY 435: repair the acceptance-create notification delta postcondition.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-435-acceptance-postcondition-delta',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826213000' AND name='434_acceptance_containment_rebind')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826213000') THEN
  RAISE EXCEPTION 'PDC_435_STAGING_HEAD_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

DO $repair$
DECLARE d text; repaired text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 repaired:=replace(d,
   'v_notifications_before<>0',
   '(SELECT count(*) FROM public.vehicle_notifications)<>v_notifications_before');
 IF repaired=d OR position('(SELECT count(*) FROM public.vehicle_notifications)<>v_notifications_before' IN repaired)=0 OR position('v_notifications_before<>0' IN repaired)>0 OR position('pdc_hermes_containment_contract_432()' IN repaired)=0 THEN
  RAISE EXCEPTION 'PDC_435_CREATE_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;
END $repair$;

REVOKE ALL ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) TO authenticated;

DO $post$
BEGIN
 IF position('v_notifications_before<>0' IN pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure))>0
   OR position('(SELECT count(*) FROM public.vehicle_notifications)<>v_notifications_before' IN pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure))=0
   OR has_function_privilege('public','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_435_FUNCTION_OR_ACL_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826214000','435_acceptance_postcondition_delta',ARRAY[
 'Append-only repair after current 434 acceptance containment rebind',
 'Acceptance creation compares notification count before and after rather than requiring an obsolete zero-row baseline',
 'Derived protected state, exact synthetic identity, receipt/replay, ACL and staging-only guards remain enforced'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
