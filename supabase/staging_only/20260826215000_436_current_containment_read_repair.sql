-- STAGING ONLY 436: stop read-only synthetic inventory from inheriting a frozen 432 baseline.
-- Synthetic writes retain exact protected/notification/outbound before-vs-after checks.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-436-current-containment-read-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826214000' AND name='435_acceptance_postcondition_delta')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826214000') THEN
  RAISE EXCEPTION 'PDC_436_STAGING_HEAD_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

-- The baseline row remains immutable evidence, but ordinary current staging
-- operations must not make read-only synthetic inventory unavailable. The
-- contract therefore guards environment/registry/outbound delivery state only.
CREATE OR REPLACE FUNCTION public.pdc_hermes_containment_contract_432()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $contract$
 SELECT (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')=1
   AND to_regclass('public.pdc_production_environment_sentinel') IS NULL
   AND public.pdc_monitor_staging_guard()
   AND (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)=1
   AND (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)=1
   AND NOT EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   AND NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   AND EXISTS(SELECT 1 FROM public.pdc_hermes_containment_baseline_432 WHERE singleton)
   AND public.pdc_hermes_authorized_registry_contract_432()
   AND NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE sent_at IS NOT NULL OR delivered_at IS NOT NULL);
$contract$;
REVOKE ALL ON FUNCTION public.pdc_hermes_containment_contract_432() FROM public,anon,authenticated,service_role;

DO $repair$
DECLARE d text; repaired text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 repaired:=replace(d,
   'v_protected_before jsonb; v_protected_after jsonb; v_notifications_before bigint; v_pdc_before bigint; v_pdc_after bigint;',
   'v_protected_before jsonb; v_protected_after jsonb; v_notifications_before bigint; v_notification_state_before text; v_notification_state_after text; v_outbound_before text; v_outbound_after text; v_pdc_before bigint; v_pdc_after bigint;');
 repaired:=replace(repaired,
   'v_protected_before:=public.pdc_acceptance_protected_digest_375(); v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);',
   'v_protected_before:=public.pdc_acceptance_protected_digest_375(); v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications); v_notification_state_before:=public.pdc_hermes_notification_state_sha256_432(); v_outbound_before:=public.pdc_hermes_outbound_state_sha256_432();');
 repaired:=replace(repaired,
   'v_protected_after:=public.pdc_acceptance_protected_digest_375();',
   'v_protected_after:=public.pdc_acceptance_protected_digest_375(); v_notification_state_after:=public.pdc_hermes_notification_state_sha256_432(); v_outbound_after:=public.pdc_hermes_outbound_state_sha256_432();');
 repaired:=replace(repaired,
   'IF v_protected_after IS DISTINCT FROM v_protected_before OR (SELECT count(*) FROM public.vehicle_notifications)<>v_notifications_before',
   'IF v_protected_after IS DISTINCT FROM v_protected_before OR v_notification_state_after<>v_notification_state_before OR v_outbound_after<>v_outbound_before');
 IF repaired=d OR position('v_notification_state_before' IN repaired)=0 OR position('v_notification_state_after' IN repaired)=0
   OR position('v_outbound_before' IN repaired)=0 OR position('v_outbound_after' IN repaired)=0
   OR position('v_notification_state_after<>v_notification_state_before' IN repaired)=0
   OR position('v_outbound_after<>v_outbound_before' IN repaired)=0
   OR position('(SELECT count(*) FROM public.vehicle_notifications)<>v_notifications_before' IN repaired)>0
   OR position('v_notifications_before<>0' IN repaired)>0 OR position('v_notifications_after<>0' IN repaired)>0
   OR position('(SELECT count(*) FROM public.vehicle_notifications)<>0' IN repaired)>0 THEN
  RAISE EXCEPTION 'PDC_436_CREATE_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;

 SELECT pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 repaired:=replace(d,
   'v_protected_before jsonb; v_protected_after jsonb; v_notifications_before bigint; v_notifications_after bigint;',
   'v_protected_before jsonb; v_protected_after jsonb; v_notifications_before bigint; v_notifications_after bigint; v_notification_state_before text; v_notification_state_after text; v_outbound_before text; v_outbound_after text;');
 repaired:=replace(repaired,
   'v_protected_before:=public.pdc_acceptance_protected_digest_375(); v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);',
   'v_protected_before:=public.pdc_acceptance_protected_digest_375(); v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications); v_notification_state_before:=public.pdc_hermes_notification_state_sha256_432(); v_outbound_before:=public.pdc_hermes_outbound_state_sha256_432();');
 repaired:=replace(repaired,
   'v_protected_after:=public.pdc_acceptance_protected_digest_375(); v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);',
   'v_protected_after:=public.pdc_acceptance_protected_digest_375(); v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications); v_notification_state_after:=public.pdc_hermes_notification_state_sha256_432(); v_outbound_after:=public.pdc_hermes_outbound_state_sha256_432();');
 repaired:=replace(repaired,
   'IF v_protected_after IS DISTINCT FROM v_protected_before OR v_notifications_after<>v_notifications_before',
   'IF v_protected_after IS DISTINCT FROM v_protected_before OR v_notification_state_after<>v_notification_state_before OR v_outbound_after<>v_outbound_before');
 IF repaired=d OR position('v_notification_state_before' IN repaired)=0 OR position('v_notification_state_after' IN repaired)=0
   OR position('v_outbound_before' IN repaired)=0 OR position('v_outbound_after' IN repaired)=0
   OR position('v_notification_state_after<>v_notification_state_before' IN repaired)=0
   OR position('v_outbound_after<>v_outbound_before' IN repaired)=0
   OR position('v_notifications_before<>0' IN repaired)>0 OR position('v_notifications_after<>0' IN repaired)>0
   OR position('(SELECT count(*) FROM public.vehicle_notifications)<>0' IN repaired)>0 THEN
  RAISE EXCEPTION 'PDC_436_LIFECYCLE_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;
END $repair$;

REVOKE ALL ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.read_pdc_hermes_test_mutation_state_365(text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_hermes_test_mutation_state_365(text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.read_pdc_acceptance_vehicle_state_375() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_acceptance_vehicle_state_375() TO authenticated;

DO $post$
BEGIN
 IF NOT public.pdc_hermes_containment_contract_432()
   OR position('v_notification_state_after<>v_notification_state_before' IN pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure))=0
   OR position('v_outbound_after<>v_outbound_before' IN pg_get_functiondef('public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)'::regprocedure))=0
   OR position('v_notification_state_after<>v_notification_state_before' IN pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure))=0
   OR position('v_outbound_after<>v_outbound_before' IN pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure))=0
   OR has_function_privilege('public','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('public','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('public','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR has_function_privilege('public','public.read_pdc_acceptance_vehicle_state_375()','EXECUTE')
   OR has_function_privilege('anon','public.read_pdc_acceptance_vehicle_state_375()','EXECUTE')
   OR has_function_privilege('service_role','public.read_pdc_acceptance_vehicle_state_375()','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.read_pdc_acceptance_vehicle_state_375()','EXECUTE')
   OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE sent_at IS NOT NULL OR delivered_at IS NOT NULL) THEN
  RAISE EXCEPTION 'PDC_436_FUNCTION_ACL_OR_CONTAINMENT_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826215000','436_current_containment_read_repair',ARRAY[
 'Append-only repair after current 435 acceptance postcondition correction; no applied migration rewritten',
 'Read containment no longer freezes ordinary mutable protected or notification state at the one-time 432 baseline',
 'Synthetic create and lifecycle writes compare exact protected, notification and outbound state before versus after',
 'Exact staging sentinel, absent Production sentinel, stopped Monitor, inactive mailbox/writer, synthetic registry and no sent/delivered outbound guards',
 'Authenticated-only execute ACLs and effective pg_get_functiondef postconditions retained'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
