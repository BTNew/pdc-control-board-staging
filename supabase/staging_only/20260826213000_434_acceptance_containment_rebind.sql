-- STAGING ONLY 434: rebind acceptance writes to the current containment contract.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-434-acceptance-containment-rebind',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826212000' AND name='433_containment_readback_column_repair')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826212000') THEN
  RAISE EXCEPTION 'PDC_434_STAGING_HEAD_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

DO $repair$
DECLARE d text; repaired text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 repaired:=replace(d,'(SELECT count(*) FROM public.vehicle_notifications)<>0','NOT public.pdc_hermes_containment_contract_432()');
 repaired:=replace(repaired,
   'IF NOT public.pdc_monitor_staging_guard()\n   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref=''cdsmnqxtyyoeoznmbidd'')<>1\n   OR to_regclass(''public.pdc_production_environment_sentinel'') IS NOT NULL\n   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)\n   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)\n   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN',
   'IF NOT public.pdc_hermes_containment_contract_432() THEN');
 repaired:=replace(repaired,
   'v_notifications_before<>0 OR (SELECT count(*) FROM public.vehicle_notifications)<>0',
   '(SELECT count(*) FROM public.vehicle_notifications)<>v_notifications_before');
 IF repaired=d OR position('pdc_hermes_containment_contract_432()' IN repaired)=0 OR position('(SELECT count(*) FROM public.vehicle_notifications)<>0' IN repaired)>0 THEN
  RAISE EXCEPTION 'PDC_434_CREATE_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;

 SELECT pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 repaired:=replace(d,'(SELECT count(*) FROM public.vehicle_notifications)<>0','NOT public.pdc_hermes_containment_contract_432()');
 repaired:=replace(repaired,
   'IF NOT public.pdc_monitor_staging_guard()\n   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref=''cdsmnqxtyyoeoznmbidd'')<>1\n   OR to_regclass(''public.pdc_production_environment_sentinel'') IS NOT NULL\n   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)\n   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)\n   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN',
   'IF NOT public.pdc_hermes_containment_contract_432() THEN');
 repaired:=replace(repaired,
   'v_notifications_before<>0 OR v_notifications_after<>0',
   'v_notifications_after<>v_notifications_before');
 IF repaired=d OR position('pdc_hermes_containment_contract_432()' IN repaired)=0 OR position('(SELECT count(*) FROM public.vehicle_notifications)<>0' IN repaired)>0 THEN
  RAISE EXCEPTION 'PDC_434_LIFECYCLE_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;
END $repair$;

REVOKE ALL ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) TO authenticated;

DO $post$
BEGIN
 IF position('pdc_hermes_containment_contract_432()' IN pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure))=0
   OR position('pdc_hermes_containment_contract_432()' IN pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure))=0
   OR position('(SELECT count(*) FROM public.vehicle_notifications)<>0' IN pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure))>0
   OR position('(SELECT count(*) FROM public.vehicle_notifications)<>0' IN pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure))>0
   OR has_function_privilege('public','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('public','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_434_FUNCTION_OR_ACL_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826213000','434_acceptance_containment_rebind',ARRAY[
 'Append-only repair after current 433 readback correction',
 'Acceptance create and lifecycle wrappers use the derived 432 containment contract rather than a stale zero-row notification constant',
 'Notification and outbound state remains delta-contained; synthetic and acceptance identity, receipts, replay, stale rejection and authenticated ACLs remain intact'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
