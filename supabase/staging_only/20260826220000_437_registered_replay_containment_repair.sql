-- STAGING ONLY 437: allow registered synthetic replays after ordinary mutable staging state changes.
-- Replays do not write; write paths retain exact before-vs-after containment.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-437-registered-replay-containment-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826215000' AND name='436_current_containment_read_repair')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826215000') THEN
  RAISE EXCEPTION 'PDC_437_STAGING_HEAD_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

DO $repair$
DECLARE d text; repaired text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 repaired:=replace(d,
   'public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->''protected_state''',
   'NOT public.pdc_hermes_containment_contract_432()');
 IF repaired=d OR position('NOT public.pdc_hermes_containment_contract_432()' IN repaired)=0
   OR position('public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->''protected_state''' IN repaired)>0 THEN
  RAISE EXCEPTION 'PDC_437_CREATE_REPLAY_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;

 SELECT pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 repaired:=replace(d,
   'public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->''protected_state''',
   'NOT public.pdc_hermes_containment_contract_432()');
 IF repaired=d OR position('NOT public.pdc_hermes_containment_contract_432()' IN repaired)=0
   OR position('public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->''protected_state''' IN repaired)>0 THEN
  RAISE EXCEPTION 'PDC_437_LIFECYCLE_REPLAY_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;
END $repair$;

REVOKE ALL ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) TO authenticated;

DO $post$
BEGIN
 IF position('public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->''protected_state''' IN pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure))>0
   OR position('public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->''protected_state''' IN pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure))>0
   OR has_function_privilege('public','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('public','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR NOT public.pdc_hermes_containment_contract_432()
   OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE sent_at IS NOT NULL OR delivered_at IS NOT NULL) THEN
  RAISE EXCEPTION 'PDC_437_REPLAY_ACL_OR_CONTAINMENT_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826220000','437_registered_replay_containment_repair',ARRAY[
 'Append-only repair after current 436 containment/read repair; no applied migration rewritten',
 'Registered synthetic replays no longer compare mutable current protected state to an old receipt snapshot',
 'Replay remains registry-bound, identity-bound, authenticated-only and guarded by current staging containment',
 'Write paths retain exact protected, notification and outbound before-vs-after postconditions',
 'No notification/outbound delivery, mailbox runtime, Production sentinel or production data is enabled or mutated'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
