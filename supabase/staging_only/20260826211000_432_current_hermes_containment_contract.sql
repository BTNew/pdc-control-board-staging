-- STAGING ONLY 432: replace stale fixed containment snapshots with a current derived contract.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-432-current-hermes-containment-contract',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826210000' AND name='431_intercept_storage_security_definer_predicate')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826210000')
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_432_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

CREATE TABLE public.pdc_hermes_containment_baseline_432(
 singleton boolean PRIMARY KEY CHECK(singleton),
 protected_state jsonb NOT NULL CHECK(jsonb_typeof(protected_state)='object'),
 notification_state_sha256 text NOT NULL CHECK(notification_state_sha256~'^[a-f0-9]{64}$'),
 outbound_state_sha256 text NOT NULL CHECK(outbound_state_sha256~'^[a-f0-9]{64}$'),
 notification_count bigint NOT NULL CHECK(notification_count>=0),
 outbound_pending_count bigint NOT NULL CHECK(outbound_pending_count>=0),
 captured_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_hermes_containment_baseline_432 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_hermes_containment_baseline_432 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_hermes_containment_baseline_432 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_hermes_authorized_vehicle_432(p_vehicle_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $authorized$
 SELECT EXISTS(
   SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
   WHERE r.run_id='HERMES-TEST-RUN-20260824' AND r.vehicle_id=p_vehicle_id
 ) OR EXISTS(
   SELECT 1 FROM public.pdc_acceptance_vehicle_bindings_375 b
   JOIN public.pdc_acceptance_vehicle_registry_375 r ON r.registry_id=b.registry_id
   WHERE r.run_id='HERMES-TEST-ACCEPTANCE-20260825' AND b.vehicle_id=p_vehicle_id
 );
$authorized$;
REVOKE ALL ON FUNCTION public.pdc_hermes_authorized_vehicle_432(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_hermes_authorized_registry_contract_432()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $registry$
 SELECT public.pdc_hermes_test_registry_guard_365()
   AND (SELECT count(*) FROM public.pdc_acceptance_vehicle_registry_375)=3
   AND NOT EXISTS(
     SELECT 1 FROM public.pdc_acceptance_vehicle_registry_375 r
     WHERE r.run_id<>'HERMES-TEST-ACCEPTANCE-20260825'
       OR r.stock_number NOT IN('HERMES-TEST-AC','HERMES-TEST-AC-A','HERMES-TEST-AC-B','HERMES-TEST-AC-C')
       OR r.customer_name NOT LIKE 'HERMES-TEST%'
       OR r.vehicle_description NOT LIKE 'HERMES-TEST%'
       OR r.job_card_number NOT LIKE 'HERMES-TEST%'
   )
   AND NOT EXISTS(
     SELECT 1 FROM public.pdc_acceptance_vehicle_bindings_375 b
     JOIN public.pdc_acceptance_vehicle_registry_375 r ON r.registry_id=b.registry_id
     JOIN public.vehicles v ON v.id=b.vehicle_id
     WHERE v.deleted_at IS NOT NULL
       OR v.stock_number IS DISTINCT FROM r.stock_number
       OR v.customer_name IS DISTINCT FROM r.customer_name
       OR v.vehicle_description IS DISTINCT FROM r.vehicle_description
       OR v.job_card_number IS DISTINCT FROM r.job_card_number
       OR v.source_system<>'hermes_acceptance_synthetic'
       OR v.source_batch_id<>'HERMES-TEST-ACCEPTANCE-20260825'
       OR v.source_record_id IS DISTINCT FROM r.stock_number
   );
$registry$;
REVOKE ALL ON FUNCTION public.pdc_hermes_authorized_registry_contract_432() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_current_protected_state_digest_432()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $digest$
 WITH protected AS MATERIALIZED(
   SELECT v.id FROM public.vehicles v
   WHERE NOT public.pdc_hermes_authorized_vehicle_432(v.id)
 ), material AS(
   SELECT 'vehicles' relation,to_jsonb(v) row_data FROM public.vehicles v JOIN protected p ON p.id=v.id
   UNION ALL SELECT 'vehicle_work_items',to_jsonb(x) FROM public.vehicle_work_items x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'workshop_bookings',to_jsonb(x) FROM public.workshop_bookings x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'workshop_booking_assignments',to_jsonb(a) FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id JOIN protected p ON p.id=b.vehicle_id
   UNION ALL SELECT 'workshop_booking_history',to_jsonb(h) FROM public.workshop_booking_history h JOIN public.workshop_bookings b ON b.id=h.booking_id JOIN protected p ON p.id=b.vehicle_id
   UNION ALL SELECT 'workshop_parts_overrides',to_jsonb(x) FROM public.workshop_parts_overrides x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'vehicle_parts_updates',to_jsonb(x) FROM public.vehicle_parts_updates x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'pdc_sublet_booking_instances',to_jsonb(x) FROM public.pdc_sublet_booking_instances x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'pdc_sublet_booking_instance_history',to_jsonb(x) FROM public.pdc_sublet_booking_instance_history x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'vehicle_movements',to_jsonb(x) FROM public.vehicle_movements x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'audit_events',to_jsonb(x) FROM public.audit_events x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'vehicle_workshop_line_adjustments',to_jsonb(x) FROM public.vehicle_workshop_line_adjustments x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'pdc_authenticated_email_operation_lines',to_jsonb(x) FROM public.pdc_authenticated_email_operation_lines x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'pdc_overnight_synthetic_estimates_369',to_jsonb(x) FROM public.pdc_overnight_synthetic_estimates_369 x JOIN protected p ON p.id=x.vehicle_id
   UNION ALL SELECT 'pdc_overnight_synthetic_estimate_receipts_369',to_jsonb(x) FROM public.pdc_overnight_synthetic_estimate_receipts_369 x JOIN protected p ON p.id=x.vehicle_id
 ) SELECT jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(convert_to(
   coalesce(jsonb_agg(jsonb_build_object('relation',relation,'row',row_data) ORDER BY relation,row_data::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM material;
$digest$;
REVOKE ALL ON FUNCTION public.pdc_current_protected_state_digest_432() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_hermes_test_protected_digest_365()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $digest$
 SELECT public.pdc_current_protected_state_digest_432();
$digest$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_protected_digest_365() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_acceptance_protected_digest_375()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $digest$
 SELECT public.pdc_current_protected_state_digest_432();
$digest$;
REVOKE ALL ON FUNCTION public.pdc_acceptance_protected_digest_375() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_hermes_notification_state_sha256_432()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $state$
 SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(n) ORDER BY n.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
 FROM public.vehicle_notifications n;
$state$;
REVOKE ALL ON FUNCTION public.pdc_hermes_notification_state_sha256_432() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_hermes_outbound_state_sha256_432()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $state$
 SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(o) ORDER BY o.notification_id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
 FROM public.pdc_rft_transport_salesperson_outbox_412 o;
$state$;
REVOKE ALL ON FUNCTION public.pdc_hermes_outbound_state_sha256_432() FROM public,anon,authenticated,service_role;

INSERT INTO public.pdc_hermes_containment_baseline_432(singleton,protected_state,notification_state_sha256,outbound_state_sha256,notification_count,outbound_pending_count)
SELECT true,public.pdc_current_protected_state_digest_432(),public.pdc_hermes_notification_state_sha256_432(),public.pdc_hermes_outbound_state_sha256_432(),
 (SELECT count(*) FROM public.vehicle_notifications),
 (SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE delivery_status='pending' AND sent_at IS NULL AND delivered_at IS NULL);

CREATE OR REPLACE FUNCTION public.pdc_hermes_containment_contract_432()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $contract$
 SELECT (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')=1
   AND to_regclass('public.pdc_production_environment_sentinel') IS NULL
   AND public.pdc_monitor_staging_guard()
   AND (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)=1
   AND (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)=1
   AND NOT EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   AND NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   AND public.pdc_hermes_authorized_registry_contract_432()
   AND EXISTS(SELECT 1 FROM public.pdc_hermes_containment_baseline_432 b WHERE b.singleton
     AND b.protected_state IS NOT DISTINCT FROM public.pdc_current_protected_state_digest_432()
     AND b.notification_state_sha256=public.pdc_hermes_notification_state_sha256_432()
     AND b.outbound_state_sha256=public.pdc_hermes_outbound_state_sha256_432()
     AND b.notification_count=(SELECT count(*) FROM public.vehicle_notifications)
     AND b.outbound_pending_count=(SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE delivery_status='pending' AND sent_at IS NULL AND delivered_at IS NULL));
$contract$;
REVOKE ALL ON FUNCTION public.pdc_hermes_containment_contract_432() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_hermes_test_dependency_guard_365()
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $dependency$
DECLARE v record; v_route_def text;
BEGIN
 FOR v IN SELECT * FROM (VALUES
  ('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'),('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'),('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'),('public.start_workshop_work(uuid,integer,timestamptz,jsonb)'),('public.stop_workshop_work(uuid,integer,text,jsonb)'),('public.resume_workshop_work(uuid,integer,jsonb)'),('public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)'),('public.pmb_transfer_vehicle(uuid,integer)'),('public.mark_vehicle_ready_for_qc(uuid,integer)'),('public.rft_collect_vehicle(uuid,integer)'),('public.update_pdc_parts_eta(uuid,integer,date)'),('public.mark_pdc_parts_ordered(uuid,integer)'),('public.mark_pdc_parts_complete(uuid,integer)'),('public.create_pdc_sublet_booking(uuid,bigint,uuid,date,date,text,text)'),('public.update_pdc_sublet_booking(uuid,bigint,date,date,text)'),('public.return_pdc_sublet_booking(uuid,bigint,timestamptz)'),('public.schedule_vehicle_work_pre345(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'),('public.start_workshop_work_pre345(uuid,integer,timestamptz,jsonb)'),('public.stop_workshop_work_pre345(uuid,integer,text,jsonb)'),('public.resume_workshop_work_pre345(uuid,integer,jsonb)'),('public.complete_workshop_work_pre345(uuid,integer,text,timestamptz,jsonb)'),('public.update_pdc_sublet_booking_pre171(uuid,bigint,date,date,text)'),('public.return_pdc_sublet_booking_pre172(uuid,bigint,timestamptz)')
 ) d(signature) LOOP
  IF to_regprocedure(v.signature) IS NULL OR NOT EXISTS(
    SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(v.signature) AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
      AND NOT has_function_privilege('public',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) THEN RETURN false; END IF;
 END LOOP;
 v_route_def:=pg_get_functiondef('public.pdc_hermes_test_actor_route_guard_365()'::regprocedure);
 IF position('pdc.hermes_test_wrapper_vehicle_365' in v_route_def)=0
   OR position('pdc.hermes_test_estimate_wrapper_vehicle_369' in v_route_def)=0
   OR position('WHERE r.vehicle_id=v_vehicle_id' in v_route_def)=0
   OR position('r.actor_id=auth.uid()' in v_route_def)>0
   OR (SELECT array_agg(c.relname::text ORDER BY c.relname::text) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND t.tgname='pdc_hermes_test_actor_route_guard_365' AND t.tgfoid='public.pdc_hermes_test_actor_route_guard_365()'::regprocedure
       AND t.tgtype=31 AND t.tgenabled='O' AND t.tgqual IS NULL AND NOT t.tgisinternal)
    IS DISTINCT FROM ARRAY['audit_events','pdc_authenticated_email_operation_lines','pdc_overnight_synthetic_estimate_receipts_369','pdc_overnight_synthetic_estimates_369','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances','vehicle_movements','vehicle_parts_updates','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles','workshop_booking_assignments','workshop_booking_history','workshop_bookings','workshop_parts_overrides']::text[] THEN RETURN false; END IF;
 RETURN true;
END $dependency$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_dependency_guard_365() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.read_pdc_hermes_test_mutation_state_365(p_run_id text,p_vehicle_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_result jsonb;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved') THEN RAISE EXCEPTION 'PDC_365_READ_UNAUTHORIZED_OR_RUN_INVALID' USING errcode='42501'; END IF;
 IF NOT public.pdc_hermes_containment_contract_432() OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365() THEN RAISE EXCEPTION 'PDC_365_READ_CONTAINMENT_DRIFT' USING errcode='55000'; END IF;
 IF p_vehicle_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id) THEN RAISE EXCEPTION 'PDC_365_READ_OUTSIDE_REGISTRY' USING errcode='42501'; END IF;
 SELECT jsonb_build_object('ok',true,'run_id',p_run_id,'vehicle_id',p_vehicle_id,'vehicles',coalesce(jsonb_agg(jsonb_build_object('scenario_no',r.scenario_no,'scenario_name',r.scenario_name,'vehicle',to_jsonb(v),'work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),'bookings',coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.created_at,b.id) FROM public.workshop_bookings b WHERE b.vehicle_id=v.id),'[]'::jsonb),'booking_assignments',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE b.vehicle_id=v.id),'[]'::jsonb),'booking_history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.history_id) FROM public.workshop_booking_history h JOIN public.workshop_bookings b ON b.id=h.booking_id WHERE b.vehicle_id=v.id),'[]'::jsonb),'parts_overrides',coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) FROM public.workshop_parts_overrides o WHERE o.vehicle_id=v.id),'[]'::jsonb),'parts',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.updated_at,p.id) FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id),'[]'::jsonb),'sublets',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.created_at,s.booking_id) FROM public.pdc_sublet_booking_instances s WHERE s.vehicle_id=v.id),'[]'::jsonb),'movements',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.vehicle_movements m WHERE m.vehicle_id=v.id),'[]'::jsonb),'audit_events',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.audit_events a WHERE a.vehicle_id=v.id),'[]'::jsonb),'sublet_history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.history_id) FROM public.pdc_sublet_booking_instance_history h WHERE h.vehicle_id=v.id),'[]'::jsonb),'receipts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.receipt_id) FROM public.pdc_overnight_synthetic_mutation_receipts_365 x WHERE x.vehicle_id=v.id),'[]'::jsonb)) ORDER BY r.scenario_no),'[]'::jsonb),'protected_state',public.pdc_hermes_test_protected_digest_365(),'revisions',jsonb_build_object('pdc_email',(SELECT revision FROM public.pdc_email_vehicle_revision WHERE singleton),'workshop',(SELECT revision FROM public.workshop_revision WHERE id=1),'navision',(SELECT revision FROM public.navision_backend_revision WHERE singleton)),'notification_count',(SELECT count(*) FROM public.vehicle_notifications)) INTO v_result
 FROM public.pdc_overnight_synthetic_fleet_registry_363 r JOIN public.vehicles v ON v.id=r.vehicle_id WHERE r.run_id=p_run_id AND (p_vehicle_id IS NULL OR r.vehicle_id=p_vehicle_id);
 RETURN v_result;
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_hermes_test_mutation_state_365(text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_hermes_test_mutation_state_365(text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.read_pdc_acceptance_vehicle_state_375()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_result jsonb;
BEGIN
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved') THEN RAISE EXCEPTION 'PDC_375_READ_UNAUTHORIZED' USING errcode='42501'; END IF;
 IF NOT public.pdc_hermes_containment_contract_432() THEN RAISE EXCEPTION 'PDC_375_READ_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 SELECT jsonb_build_object('ok',true,'run_id','HERMES-TEST-ACCEPTANCE-20260825','protected_state',public.pdc_acceptance_protected_digest_375(),'notification_count',(SELECT count(*) FROM public.vehicle_notifications),'vehicles',coalesce(jsonb_agg(jsonb_build_object('registry',to_jsonb(r),'binding',to_jsonb(b),'vehicle',to_jsonb(v),'work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),'bookings',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.id) FROM public.workshop_bookings x WHERE x.vehicle_id=v.id),'[]'::jsonb),'parts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.updated_at,x.id) FROM public.vehicle_parts_updates x WHERE x.vehicle_id=v.id),'[]'::jsonb),'sublets',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.booking_id) FROM public.pdc_sublet_booking_instances x WHERE x.vehicle_id=v.id),'[]'::jsonb),'movements',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.moved_at,x.id) FROM public.vehicle_movements x WHERE x.vehicle_id=v.id),'[]'::jsonb),'audit_events',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.id) FROM public.audit_events x WHERE x.vehicle_id=v.id),'[]'::jsonb),'lifecycle_receipts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.receipt_id) FROM public.pdc_acceptance_lifecycle_receipts_375 x WHERE x.vehicle_id=v.id),'[]'::jsonb),'create_receipt',to_jsonb(c)) ORDER BY r.journey_code),'[]'::jsonb)) INTO v_result
 FROM public.pdc_acceptance_vehicle_registry_375 r LEFT JOIN public.pdc_acceptance_vehicle_bindings_375 b ON b.registry_id=r.registry_id LEFT JOIN public.vehicles v ON v.id=b.vehicle_id LEFT JOIN public.pdc_acceptance_vehicle_create_receipts_375 c ON c.registry_id=r.registry_id;
 RETURN v_result;
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_acceptance_vehicle_state_375() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_acceptance_vehicle_state_375() TO authenticated;

DO $post$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_hermes_containment_baseline_432 WHERE singleton)
   OR NOT public.pdc_hermes_containment_contract_432()
   OR pg_get_functiondef('public.pdc_hermes_test_protected_digest_365()'::regprocedure) LIKE '%1498%'
   OR pg_get_functiondef('public.pdc_acceptance_protected_digest_375()'::regprocedure) LIKE '%1498%'
   OR has_function_privilege('public','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE')
   OR has_function_privilege('public','public.read_pdc_acceptance_vehicle_state_375()','EXECUTE')
   OR has_function_privilege('anon','public.read_pdc_acceptance_vehicle_state_375()','EXECUTE')
   OR has_function_privilege('service_role','public.read_pdc_acceptance_vehicle_state_375()','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.read_pdc_acceptance_vehicle_state_375()','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_432_FUNCTION_OR_ACL_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826211000','432_current_hermes_containment_contract',ARRAY[
 'Append-only current staging head correction after 431; no applied migration rewritten',
 'Mechanically derived protected digest excludes every currently authorised HERMES overnight and acceptance registry-bound vehicle',
 'Notification and outbound hashes preserve immutable pre-existing staging evidence and reject ordinary drift without creating delivery',
 '365 dependency/read and 375 acceptance read functions re-bound to the current catalog with authenticated-only ACLs',
 'Exact staging sentinel, absent Production sentinel, stopped Monitor, inactive mailbox/writer and synthetic namespace guards'
]);
NOTIFY pgrst,'reload schema';

DO $final$
BEGIN
 IF NOT public.pdc_hermes_containment_contract_432()
   OR (SELECT count(*) FROM public.vehicle_notifications)<>(SELECT notification_count FROM public.pdc_hermes_containment_baseline_432 WHERE singleton)
   OR (SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE sent_at IS NOT NULL OR delivered_at IS NOT NULL)<>0 THEN
  RAISE EXCEPTION 'PDC_432_FINAL_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END $final$;
COMMIT;
