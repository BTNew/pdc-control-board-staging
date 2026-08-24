-- STAGING ONLY 365: registry-bound mutation wrappers for the overnight synthetic fleet.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-365-overnight-synthetic-wrappers',0));

LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;

DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825010000' AND name='364_overnight_synthetic_snapshot_projection')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260825010000' AND version~'^[0-9]{14}$')
   OR to_regclass('public.pdc_overnight_synthetic_fleet_registry_363') IS NULL
   OR (SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363 WHERE run_id='HERMES-TEST-RUN-20260824')<>20
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR to_regprocedure('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)') IS NULL
   OR to_regprocedure('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)') IS NULL
   OR to_regprocedure('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)') IS NULL
   OR to_regprocedure('public.start_workshop_work(uuid,integer,timestamptz,jsonb)') IS NULL
   OR to_regprocedure('public.stop_workshop_work(uuid,integer,text,jsonb)') IS NULL
   OR to_regprocedure('public.resume_workshop_work(uuid,integer,jsonb)') IS NULL
   OR to_regprocedure('public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)') IS NULL
   OR to_regprocedure('public.pmb_transfer_vehicle(uuid,integer)') IS NULL
   OR to_regprocedure('public.mark_vehicle_ready_for_qc(uuid,integer)') IS NULL
   OR to_regprocedure('public.rft_collect_vehicle(uuid,integer)') IS NULL
   OR to_regprocedure('public.update_pdc_parts_eta(uuid,integer,date)') IS NULL
   OR to_regprocedure('public.mark_pdc_parts_ordered(uuid,integer)') IS NULL
   OR to_regprocedure('public.mark_pdc_parts_complete(uuid,integer)') IS NULL
   OR to_regprocedure('public.create_pdc_sublet_booking(uuid,bigint,uuid,date,date,text,text)') IS NULL
   OR to_regprocedure('public.update_pdc_sublet_booking(uuid,bigint,date,date,text)') IS NULL
   OR to_regprocedure('public.return_pdc_sublet_booking(uuid,bigint,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'PDC_365_STAGING_TARGET_HEAD_CONTAINMENT_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
 END IF;
END $guard$;

CREATE TABLE public.pdc_overnight_synthetic_mutation_receipts_365(
 receipt_id uuid PRIMARY KEY,
 run_id text NOT NULL CHECK(run_id='HERMES-TEST-RUN-20260824'),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 idempotency_key uuid NOT NULL,
 action text NOT NULL CHECK(action IN(
  'vehicle_edit','work_states','lifecycle_to_pmb','lifecycle_ready_qc','lifecycle_qc_to_rft','lifecycle_collect',
  'parts_eta','parts_ordered','parts_complete','parts_stoppage','parts_recover','workshop_schedule','workshop_move','workshop_start',
  'workshop_stop','workshop_resume','workshop_complete','sublet_create','sublet_update','sublet_return')),
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_overnight_synthetic_mutation_receipts_365 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_overnight_synthetic_mutation_receipts_365 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_overnight_synthetic_mutation_append_only_365()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN RAISE EXCEPTION 'PDC_365_APPEND_ONLY' USING errcode='55000'; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_overnight_synthetic_mutation_append_only_365() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_overnight_synthetic_mutation_receipts_append_only_365
BEFORE UPDATE OR DELETE ON public.pdc_overnight_synthetic_mutation_receipts_365
FOR EACH ROW EXECUTE FUNCTION public.pdc_overnight_synthetic_mutation_append_only_365();

CREATE FUNCTION public.pdc_hermes_test_actor_route_guard_365()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $route$
BEGIN
 IF auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.actor_id=auth.uid())
   AND current_setting('pdc.hermes_test_wrapper_365',true) IS DISTINCT FROM 'on' THEN
  RAISE EXCEPTION 'PDC_365_OVERNIGHT_ACTOR_MUST_USE_SYNTHETIC_WRAPPER' USING errcode='42501';
 END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $route$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_actor_route_guard_365() FROM public,anon,authenticated,service_role;
DO $route_triggers$
DECLARE v_table text;
BEGIN
 FOREACH v_table IN ARRAY ARRAY['vehicles','vehicle_work_items','workshop_bookings','workshop_booking_assignments',
  'workshop_booking_history','workshop_parts_overrides','vehicle_parts_updates','pdc_sublet_booking_instances',
  'pdc_sublet_booking_instance_history','vehicle_movements','audit_events'] LOOP
  EXECUTE format('CREATE TRIGGER pdc_hermes_test_actor_route_guard_365 BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.pdc_hermes_test_actor_route_guard_365()',v_table);
 END LOOP;
END $route_triggers$;

CREATE FUNCTION public.pdc_hermes_test_dependency_guard_365()
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $guard$
DECLARE v record;
BEGIN
 FOR v IN SELECT * FROM (VALUES
  ('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure,'17819f99ab20d552cd13db3b2a09173ebc0f85bb4edb4aada0c46cc5a52aed2b'),
  ('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'::regprocedure,'80073fd48518fcad46da32969980dc75ec312568d44d54a702363ed244a8f49f'),
  ('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure,'4553354d22b9894598311a586b6f68916facaed08466c25f1f762f9f38ba9427'),
  ('public.start_workshop_work(uuid,integer,timestamptz,jsonb)'::regprocedure,'cdcd2210cbf6a0eeda5b1566646d6acb591b82be6f98c393551d86fdd2cda035'),
  ('public.stop_workshop_work(uuid,integer,text,jsonb)'::regprocedure,'f25e81d49e28d3076c1645050ce1783ddbd1acaae7c2218095eea688cbfceb7c'),
  ('public.resume_workshop_work(uuid,integer,jsonb)'::regprocedure,'6158f6a3e529a92884c392383a421b08723ce0ac62c158e92cfcfc29d101f20c'),
  ('public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)'::regprocedure,'f3100d5c0d1b4ae0ac300770066a1a4f642a2ac1e8050bfb09d36799155baefc'),
  ('public.pmb_transfer_vehicle(uuid,integer)'::regprocedure,'a96bd0ee479061c35b8506f30a1ad5234dc6d6059ce871f16229c37b53ab6567'),
  ('public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure,'9436d6812ffb74bf2bd22d261ebd2992cde011dd698366e2127a2da4b1c46fc5'),
  ('public.rft_collect_vehicle(uuid,integer)'::regprocedure,'039ae7fc4dbb8d4015e113d407d22a1d9ee10342b39c513fc02ce65e49ed0cc9'),
  ('public.update_pdc_parts_eta(uuid,integer,date)'::regprocedure,'21537485317de3e01bfe0c9722408e00cdae256f0f2396b6a50a8ac365e2e61a'),
  ('public.mark_pdc_parts_ordered(uuid,integer)'::regprocedure,'6cfdf15e3bd2e1ed93fdbb6b9717cb889eaf1f7aae816212d9c7027057ce906b'),
  ('public.mark_pdc_parts_complete(uuid,integer)'::regprocedure,'f68e9bf7d214bf6bcdc15003937dbf95313b656c604041153420fbd67bd9777c'),
  ('public.create_pdc_sublet_booking(uuid,bigint,uuid,date,date,text,text)'::regprocedure,'c345ce45a88a26cb5abd588ec9ba7c600fc9682adeae4fafb4eccf7717ff30f2'),
  ('public.update_pdc_sublet_booking(uuid,bigint,date,date,text)'::regprocedure,'81b3db339ee6cd1ec3bd1411919ad385642b557e02f125b32e2e325d871ee36d'),
  ('public.return_pdc_sublet_booking(uuid,bigint,timestamptz)'::regprocedure,'cc6a7bb0209cc279e3548b9fc2e37ac4194495d26d5029d1a52034b0be8c51cc'),
  ('public.schedule_vehicle_work_pre345(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'::regprocedure,'38d0cb3c8f8ad17a1c4fdb6c684066348339b6d53845367e43572242ade44e36'),
  ('public.start_workshop_work_pre345(uuid,integer,timestamptz,jsonb)'::regprocedure,'44e6c4ffabb42589304c7d0363a57e629f66c701bf9f3dd9ce1d46a411956b20'),
  ('public.stop_workshop_work_pre345(uuid,integer,text,jsonb)'::regprocedure,'4453b847109fb0a6de109c4961ae94bdbde856b3409f4a6e850eda3ba0891916'),
  ('public.resume_workshop_work_pre345(uuid,integer,jsonb)'::regprocedure,'07f0883833571acd272cc9d3f778c4320f292a8fc65356da5a11e3fd700363b1'),
  ('public.complete_workshop_work_pre345(uuid,integer,text,timestamptz,jsonb)'::regprocedure,'57bd9202bf9fefebb2c809ff3bd3ec9d5cd96e6406726806dd42fd2c5e023ce6'),
  ('public.update_pdc_sublet_booking_pre171(uuid,bigint,date,date,text)'::regprocedure,'08e63ca21f2d4b91a7f23dbd2f6e7ef2d8e2b5a5bc057a220f86c961ced44529'),
  ('public.return_pdc_sublet_booking_pre172(uuid,bigint,timestamptz)'::regprocedure,'524d03f29871312c9028e2ffca531396bf1baa9b4dcc4a95fb4fb4838fd224ad')
 ) d(proc,sha256) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v.proc AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
    AND encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')=v.sha256
    AND NOT has_function_privilege('public',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) THEN
   RETURN false;
  END IF;
 END LOOP;
 RETURN true;
END $guard$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_dependency_guard_365() FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_hermes_test_registry_guard_365()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $guard$
 SELECT (SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363)=20
  AND (SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.scenario_no),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
       FROM public.pdc_overnight_synthetic_fleet_registry_363 r)='61f071efc4218cbf0e07b3699c010e0a79ea43909757f22c9e10f7151d66ded2'
  AND (SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg(r.spec ORDER BY r.scenario_no),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
       FROM public.pdc_overnight_synthetic_fleet_registry_363 r)='0bc2791f0b79bf03018f5d3ec444441253c0aa8a994dd8a31f7bd49f20738d16'
  AND NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r JOIN public.vehicles v ON v.id=r.vehicle_id WHERE
   r.run_id<>'HERMES-TEST-RUN-20260824' OR r.scenario_no IS DISTINCT FROM (r.spec->>'scenario_no')::integer
   OR r.scenario_name IS DISTINCT FROM r.spec->>'scenario_name' OR r.stock_number IS DISTINCT FROM r.spec->>'stock'
   OR r.customer_name IS DISTINCT FROM r.spec->>'customer' OR r.job_card_number IS DISTINCT FROM r.spec->>'job_card'
   OR r.vehicle_description IS DISTINCT FROM r.spec->>'description'
   OR r.registry_id IS DISTINCT FROM extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,r.run_id||':registry:'||r.scenario_no::text)
   OR r.vehicle_id IS DISTINCT FROM extensions.uuid_generate_v5('36300000-0000-5000-8000-000000000363'::uuid,r.run_id||':vehicle:'||r.stock_number)
   OR v.permanent_vehicle_id IS DISTINCT FROM 'HERMES-TEST-PERM-'||lpad(r.scenario_no::text,3,'0')
   OR v.stock_number IS DISTINCT FROM r.stock_number OR v.customer_name IS DISTINCT FROM r.customer_name
   OR v.job_card_number IS DISTINCT FROM r.job_card_number OR v.vehicle_description IS DISTINCT FROM r.vehicle_description
   OR v.source_system IS DISTINCT FROM 'hermes_overnight_synthetic' OR v.source_batch_id IS DISTINCT FROM r.run_id
   OR v.source_record_id IS DISTINCT FROM r.stock_number OR v.source_payload->>'contract' IS DISTINCT FROM 'pdc-overnight-synthetic-fleet-363/render_only'
   OR v.source_payload->>'run_id' IS DISTINCT FROM r.run_id OR (v.source_payload->>'scenario_no')::integer IS DISTINCT FROM r.scenario_no
   OR v.source_payload->>'scenario_name' IS DISTINCT FROM r.scenario_name OR v.source_payload->>'request_sha256' IS DISTINCT FROM r.request_sha256)
  AND NOT has_table_privilege('anon','public.pdc_overnight_synthetic_fleet_registry_363','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege('authenticated','public.pdc_overnight_synthetic_fleet_registry_363','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege('service_role','public.pdc_overnight_synthetic_fleet_registry_363','SELECT,INSERT,UPDATE,DELETE')
  AND EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.pdc_overnight_synthetic_fleet_registry_363'::regclass
   AND t.tgname='pdc_overnight_synthetic_fleet_registry_append_only_363' AND t.tgenabled='O' AND NOT t.tgisinternal
   AND t.tgfoid='public.pdc_overnight_synthetic_fleet_append_only_363()'::regprocedure
   AND pg_get_triggerdef(t.oid)='CREATE TRIGGER pdc_overnight_synthetic_fleet_registry_append_only_363 BEFORE DELETE OR UPDATE ON public.pdc_overnight_synthetic_fleet_registry_363 FOR EACH ROW EXECUTE FUNCTION pdc_overnight_synthetic_fleet_append_only_363()')
  AND EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.pdc_overnight_synthetic_fleet_append_only_363()'::regprocedure
   AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
   AND encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')='9317c5ca289b92f10d9085e7a0dabeb08a4b5d0e04147b6fcfc922af1be4e5b9'
   AND NOT has_function_privilege('public',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
   AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('service_role',p.oid,'EXECUTE'))
$guard$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_registry_guard_365() FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_hermes_test_protected_digest_365()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $digest$
 WITH protected AS MATERIALIZED(SELECT v.id FROM public.vehicles v WHERE NOT EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id)), material AS(
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
 ) SELECT jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(convert_to(
  coalesce(jsonb_agg(jsonb_build_object('relation',relation,'row',row_data) ORDER BY relation,row_data::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM material
$digest$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_protected_digest_365() FROM public,anon,authenticated,service_role;

DO $helper_post$
BEGIN
 IF NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR public.pdc_hermes_test_protected_digest_365() IS NULL
   OR (SELECT count(*) FROM pg_trigger t WHERE t.tgname='pdc_hermes_test_actor_route_guard_365'
       AND t.tgfoid='public.pdc_hermes_test_actor_route_guard_365()'::regprocedure AND t.tgenabled='O' AND NOT t.tgisinternal)<>11 THEN
  RAISE EXCEPTION 'PDC_365_HELPER_POSTCONDITION' USING errcode='55000'; END IF;
END $helper_post$;

CREATE FUNCTION public.pdc_hermes_test_apply_365(
 p_run_id text,p_vehicle_id uuid,p_expected_vehicle_version integer,p_subject_id uuid,
 p_expected_subject_version integer,p_idempotency_key uuid,p_action text,p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $apply$
DECLARE
 v_actor uuid:=auth.uid();
 v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_registry public.pdc_overnight_synthetic_fleet_registry_363%rowtype;
 v_vehicle_before public.vehicles%rowtype;
 v_vehicle_after public.vehicles%rowtype;
 v_receipt public.pdc_overnight_synthetic_mutation_receipts_365%rowtype;
 v_receipt_id uuid;
 v_request_sha text;
 v_result jsonb;
 v_payload jsonb:=coalesce(p_payload,'{}'::jsonb);
 v_protected_before jsonb; v_protected_after jsonb;
 v_target_state_before text; v_target_state_after text;
 v_notifications_before bigint; v_notifications_after bigint;
 v_pdc_revision_before bigint; v_pdc_revision_after bigint;
 v_workshop_revision_before bigint; v_workshop_revision_after bigint;
 v_navision_revision_before bigint; v_navision_revision_after bigint;
 v_replay boolean:=false;
 v_subject_vehicle uuid; v_subject_version_after integer;
 v_parts_before public.vehicle_parts_updates%rowtype; v_parts_after public.vehicle_parts_updates%rowtype;
 v_before_qc public.vehicles%rowtype; v_after_qc public.vehicles%rowtype;
 v_work_key text; v_reason text;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR p_vehicle_id IS NULL
   OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL
   OR p_action IS NULL OR p_payload IS NULL OR jsonb_typeof(v_payload)<>'object' THEN
  RAISE EXCEPTION 'PDC_365_INVALID_INPUT' USING errcode='22023';
 END IF;
 IF p_action NOT IN('vehicle_edit','work_states','lifecycle_to_pmb','lifecycle_ready_qc','lifecycle_qc_to_rft','lifecycle_collect',
  'parts_eta','parts_ordered','parts_complete','parts_stoppage','parts_recover','workshop_schedule','workshop_move','workshop_start','workshop_stop',
  'workshop_resume','workshop_complete','sublet_create','sublet_update','sublet_return') THEN
  RAISE EXCEPTION 'PDC_365_ACTION_NOT_ALLOWED' USING errcode='22023';
 END IF;
 IF p_action NOT IN('workshop_move','workshop_start','workshop_stop','workshop_resume','workshop_complete','sublet_update','sublet_return')
   AND (p_subject_id IS NOT NULL OR p_expected_subject_version IS NOT NULL) THEN
  RAISE EXCEPTION 'PDC_365_SUBJECT_FORBIDDEN_FOR_ACTION' USING errcode='22023'; END IF;
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
   AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE
 ) THEN RAISE EXCEPTION 'PDC_365_UNAUTHORIZED' USING errcode='42501'; END IF;

 v_request_sha:=encode(extensions.digest(convert_to(jsonb_build_object(
  'contract','pdc-overnight-synthetic-mutation-365','run_id',p_run_id,'actor_id',v_actor,
  'vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,
  'subject_id',p_subject_id,'expected_subject_version',p_expected_subject_version,
  'idempotency_key',p_idempotency_key,'action',p_action,'payload',v_payload)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-365-receipt:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_overnight_synthetic_mutation_receipts_365
 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_request_sha OR v_receipt.actor_email<>v_email THEN
   RAISE EXCEPTION 'PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH' USING errcode='22023';
  END IF;
  v_replay:=true;
 END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-365-vehicle:'||p_vehicle_id::text,0));
 LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
 LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
 LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
 LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_hermes_test_dependency_guard_365()
   OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_365_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;

 SELECT r INTO v_registry
 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
 WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_365_REGISTRY_SCOPE_OR_VERSION_MISMATCH' USING errcode='42501'; END IF;
 SELECT * INTO v_vehicle_before FROM public.vehicles v WHERE v.id=v_registry.vehicle_id FOR UPDATE;
 IF NOT FOUND
   OR v_vehicle_before.stock_number IS DISTINCT FROM v_registry.stock_number
   OR v_vehicle_before.customer_name IS DISTINCT FROM v_registry.customer_name
   OR v_vehicle_before.job_card_number IS DISTINCT FROM v_registry.job_card_number
   OR v_vehicle_before.vehicle_description IS DISTINCT FROM v_registry.vehicle_description
   OR v_vehicle_before.source_system IS DISTINCT FROM 'hermes_overnight_synthetic'
   OR v_vehicle_before.source_batch_id IS DISTINCT FROM p_run_id
   OR v_vehicle_before.source_record_id IS DISTINCT FROM v_registry.stock_number
   OR v_vehicle_before.source_payload->>'contract' IS DISTINCT FROM 'pdc-overnight-synthetic-fleet-363/render_only' THEN
  RAISE EXCEPTION 'PDC_365_REGISTRY_SCOPE_OR_VERSION_MISMATCH' USING errcode='40001';
 END IF;
 PERFORM set_config('pdc.hermes_test_wrapper_365','on',true);

 -- Share-lock every protected vehicle row so the cross-relation digest describes one stable set
 -- while different synthetic vehicles remain independently mutable for two-session tests.
 PERFORM 1 FROM public.vehicles v WHERE NOT EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id
 ) ORDER BY v.id FOR SHARE;
 v_protected_before:=public.pdc_hermes_test_protected_digest_365();
 SELECT revision INTO v_pdc_revision_before FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT revision INTO v_workshop_revision_before FROM public.workshop_revision WHERE id=1;
 SELECT revision INTO v_navision_revision_before FROM public.navision_backend_revision WHERE singleton;
 IF v_pdc_revision_before IS NULL OR v_workshop_revision_before IS NULL OR v_navision_revision_before IS NULL THEN
  RAISE EXCEPTION 'PDC_365_REVISION_SINGLETON_MISMATCH' USING errcode='55000'; END IF;
 v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('vehicle',to_jsonb(v_vehicle_before),
  'work',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicle_work_items x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'bookings',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.workshop_bookings x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'parts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicle_parts_updates x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'sublets',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.booking_id) FROM public.pdc_sublet_booking_instances x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'booking_assignments',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE b.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'booking_history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM public.workshop_booking_history h JOIN public.workshop_bookings b ON b.id=h.booking_id WHERE b.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'parts_overrides',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.workshop_parts_overrides x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'sublet_history',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.pdc_sublet_booking_instance_history x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'movements',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicle_movements x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'audit',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.audit_events x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb))::text,'UTF8'),'sha256'),'hex') INTO v_target_state_before;
 IF v_replay THEN
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)||jsonb_build_object(
   'replay_containment_verified',true,'current_vehicle_version',v_vehicle_before.version,
   'current_protected_digest',v_protected_before,'current_notification_count',v_notifications_before);
 END IF;

 IF v_vehicle_before.version<>p_expected_vehicle_version THEN
  v_result:=jsonb_build_object('ok',false,'error','vehicle_version_conflict','current_version',v_vehicle_before.version);
 ELSE
 IF p_action='vehicle_edit' THEN
  IF v_payload<>jsonb_build_object('pmb_key_tag',v_payload->'pmb_key_tag')
    OR coalesce(v_payload->>'pmb_key_tag','')!~'^HERMES-TEST' OR length(v_payload->>'pmb_key_tag')>80 THEN
   RAISE EXCEPTION 'PDC_365_SYNTHETIC_EDIT_PAYLOAD_INVALID' USING errcode='22023'; END IF;
  UPDATE public.vehicles SET pmb_key_tag=v_payload->>'pmb_key_tag',version=version+1,updated_by=v_actor
   WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  PERFORM public.audit_pdc_event('update','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_vehicle_before),to_jsonb(v_vehicle_after),
   jsonb_build_object('action','pdc_hermes_test_vehicle_edit_365','field','pmb_key_tag'));
  v_result:=jsonb_build_object('ok',true,'code','synthetic_vehicle_edited','vehicle',to_jsonb(v_vehicle_after));
 ELSIF p_action='work_states' THEN
  IF jsonb_typeof(v_payload->'work_states')<>'object' OR v_payload<>(jsonb_build_object('work_states',v_payload->'work_states')) THEN
   RAISE EXCEPTION 'PDC_365_WORK_STATES_PAYLOAD_INVALID' USING errcode='22023'; END IF;
  v_result:=public.set_pdc_vehicle_work_states(p_vehicle_id,p_expected_vehicle_version,v_payload->'work_states');
 ELSIF p_action='lifecycle_to_pmb' THEN
  IF v_payload<>'{}'::jsonb THEN RAISE EXCEPTION 'PDC_365_EMPTY_PAYLOAD_REQUIRED' USING errcode='22023'; END IF;
  v_result:=public.pmb_transfer_vehicle(p_vehicle_id,p_expected_vehicle_version);
 ELSIF p_action='lifecycle_ready_qc' THEN
  IF v_payload<>'{}'::jsonb THEN RAISE EXCEPTION 'PDC_365_EMPTY_PAYLOAD_REQUIRED' USING errcode='22023'; END IF;
  v_result:=public.mark_vehicle_ready_for_qc(p_vehicle_id,p_expected_vehicle_version);
 ELSIF p_action='lifecycle_qc_to_rft' THEN
  IF v_payload<>'{}'::jsonb THEN RAISE EXCEPTION 'PDC_365_EMPTY_PAYLOAD_REQUIRED' USING errcode='22023'; END IF;
  IF upper(btrim(coalesce(v_vehicle_before.current_location,'')))<>'QC'
    OR v_vehicle_before.lifecycle_state<>'active' OR v_vehicle_before.deleted_at IS NOT NULL
    OR v_vehicle_before.qc_completed_at IS NOT NULL
    OR coalesce(array_length(public.pdc_qc_gate_issues(p_vehicle_id),1),0)>0 THEN
   v_result:=jsonb_build_object('ok',false,'error','qc_gate_blocked');
  ELSE
   UPDATE public.vehicles SET qc_completed_at=clock_timestamp(),qc_completed_by=v_actor,
    version=version+1,updated_by=v_actor WHERE id=p_vehicle_id RETURNING * INTO v_after_qc;
   PERFORM public.audit_pdc_event('update','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_vehicle_before),to_jsonb(v_after_qc),
    jsonb_build_object('action','pdc_hermes_test_qc_complete_365','notification_enqueued',false));
   v_before_qc:=v_after_qc;
   UPDATE public.vehicles SET lifecycle_state='rft',current_location='RFT',
    rft_transferred_at=coalesce(rft_transferred_at,clock_timestamp()),version=version+1,updated_by=v_actor
    WHERE id=p_vehicle_id RETURNING * INTO v_after_qc;
   INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
   VALUES(p_vehicle_id,v_before_qc.current_location,'RFT',v_before_qc.pmb_stage,v_before_qc.pmb_stage,
    v_before_qc.pmb_bay_stage,v_before_qc.pmb_bay_stage,v_before_qc.pmb_bay_number,v_before_qc.pmb_bay_number,
    'HERMES-TEST QC sign-off to RFT without external notification',v_actor);
   PERFORM public.audit_pdc_event('rft','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before_qc),to_jsonb(v_after_qc),
    jsonb_build_object('action','pdc_hermes_test_qc_to_rft_365','notification_enqueued',false));
   v_result:=jsonb_build_object('ok',true,'code','synthetic_qc_signed_off_to_rft','vehicle',to_jsonb(v_after_qc),
    'qc_signed_off',true,'rft_transferred',true,'notification_id',null,'notification_has_recipient',false);
  END IF;
 ELSIF p_action='lifecycle_collect' THEN
  IF v_payload<>'{}'::jsonb THEN RAISE EXCEPTION 'PDC_365_EMPTY_PAYLOAD_REQUIRED' USING errcode='22023'; END IF;
  v_result:=public.rft_collect_vehicle(p_vehicle_id,p_expected_vehicle_version);
 ELSIF p_action='parts_eta' THEN
  IF v_payload<>jsonb_build_object('worst_eta',v_payload->'worst_eta') THEN RAISE EXCEPTION 'PDC_365_PARTS_ETA_PAYLOAD_INVALID' USING errcode='22023'; END IF;
  v_result:=public.update_pdc_parts_eta(p_vehicle_id,p_expected_vehicle_version,nullif(v_payload->>'worst_eta','')::date);
 ELSIF p_action='parts_ordered' THEN
  IF v_payload<>'{}'::jsonb THEN RAISE EXCEPTION 'PDC_365_EMPTY_PAYLOAD_REQUIRED' USING errcode='22023'; END IF;
  v_result:=public.mark_pdc_parts_ordered(p_vehicle_id,p_expected_vehicle_version);
 ELSIF p_action='parts_complete' THEN
  IF v_payload<>'{}'::jsonb THEN RAISE EXCEPTION 'PDC_365_EMPTY_PAYLOAD_REQUIRED' USING errcode='22023'; END IF;
  v_result:=public.mark_pdc_parts_complete(p_vehicle_id,p_expected_vehicle_version);
 ELSIF p_action IN('parts_stoppage','parts_recover') THEN
  IF p_action='parts_stoppage' THEN
   v_reason:=btrim(coalesce(v_payload->>'reason',''));
   IF v_payload<>jsonb_build_object('reason',v_payload->'reason') OR v_reason!~'^HERMES-TEST' OR length(v_reason)>240 THEN
    RAISE EXCEPTION 'PDC_365_SYNTHETIC_PARTS_STOPPAGE_REASON_REQUIRED' USING errcode='22023'; END IF;
  ELSIF v_payload<>'{}'::jsonb THEN RAISE EXCEPTION 'PDC_365_EMPTY_PAYLOAD_REQUIRED' USING errcode='22023'; END IF;
  SELECT * INTO v_parts_before FROM public.vehicle_parts_updates WHERE vehicle_id=p_vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1;
  INSERT INTO public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,
   parts_stoppage_reason,worst_eta,updated_by,updated_at) VALUES(p_vehicle_id,true,coalesce(v_parts_before.parts_ordered,false),
   coalesce(v_parts_before.parts_received,false),p_action='parts_stoppage',CASE WHEN p_action='parts_stoppage' THEN v_reason END,
   v_parts_before.worst_eta,v_actor,clock_timestamp()) RETURNING * INTO v_parts_after;
  UPDATE public.vehicles SET version=version+1,updated_by=v_actor WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  PERFORM public.audit_pdc_event('insert','vehicle_parts_updates',v_parts_after.id,p_vehicle_id,
   CASE WHEN v_parts_before.id IS NULL THEN NULL ELSE to_jsonb(v_parts_before) END,to_jsonb(v_parts_after),
   jsonb_build_object('action','pdc_hermes_test_'||p_action||'_365','reason',v_reason));
  v_result:=jsonb_build_object('ok',true,'code',p_action,'vehicle',to_jsonb(v_vehicle_after),'parts_update',to_jsonb(v_parts_after));
 ELSIF p_action='workshop_schedule' THEN
  IF v_payload<>jsonb_strip_nulls(jsonb_build_object('stage_code',v_payload->'stage_code','bay_number',v_payload->'bay_number',
    'scheduled_start_at',v_payload->'scheduled_start_at','duration_minutes',v_payload->'duration_minutes',
    'technician_id',v_payload->'technician_id','override_reason',v_payload->'override_reason')) THEN
   RAISE EXCEPTION 'PDC_365_SCHEDULE_PAYLOAD_INVALID' USING errcode='22023'; END IF;
  v_reason:=nullif(btrim(v_payload->>'override_reason'),'');
  IF v_reason IS NOT NULL AND (v_reason!~'^HERMES-TEST' OR length(v_reason)>240) THEN RAISE EXCEPTION 'PDC_365_SYNTHETIC_REASON_REQUIRED' USING errcode='22023'; END IF;
  v_result:=public.schedule_vehicle_work(p_vehicle_id,p_expected_vehicle_version,v_payload->>'stage_code',(v_payload->>'bay_number')::integer,
   (v_payload->>'scheduled_start_at')::timestamptz,(v_payload->>'duration_minutes')::integer,
   nullif(v_payload->>'technician_id','')::uuid,v_reason,jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
 ELSIF p_action='sublet_create' THEN
  IF v_payload<>jsonb_build_object('provider_id',v_payload->'provider_id','out_date',v_payload->'out_date',
     'expected_return_date',v_payload->'expected_return_date','notes',v_payload->'notes')
    OR coalesce(v_payload->>'notes','')!~'^HERMES-TEST' OR length(v_payload->>'notes')>240 THEN
   RAISE EXCEPTION 'PDC_365_SUBLET_CREATE_PAYLOAD_INVALID' USING errcode='22023'; END IF;
  v_result:=public.create_pdc_sublet_booking(p_vehicle_id,p_expected_vehicle_version,(v_payload->>'provider_id')::uuid,
   (v_payload->>'out_date')::date,(v_payload->>'expected_return_date')::date,'',v_payload->>'notes');
 ELSE
  IF p_subject_id IS NULL OR p_expected_subject_version IS NULL OR p_expected_subject_version<1 THEN
   RAISE EXCEPTION 'PDC_365_SUBJECT_REQUIRED' USING errcode='22023'; END IF;
  IF p_action LIKE 'workshop_%' THEN
   SELECT b.vehicle_id INTO v_subject_vehicle FROM public.workshop_bookings b WHERE b.id=p_subject_id FOR UPDATE;
  ELSE
   SELECT b.vehicle_id INTO v_subject_vehicle FROM public.pdc_sublet_booking_instances b WHERE b.booking_id=p_subject_id FOR UPDATE;
  END IF;
  IF v_subject_vehicle IS DISTINCT FROM p_vehicle_id THEN RAISE EXCEPTION 'PDC_365_SUBJECT_OUTSIDE_REGISTRY_VEHICLE' USING errcode='42501'; END IF;
  IF p_action='workshop_move' THEN
   IF v_payload<>jsonb_strip_nulls(jsonb_build_object('stage_code',v_payload->'stage_code','bay_number',v_payload->'bay_number',
    'scheduled_start_at',v_payload->'scheduled_start_at','duration_minutes',v_payload->'duration_minutes','override_reason',v_payload->'override_reason')) THEN
    RAISE EXCEPTION 'PDC_365_WORKSHOP_MOVE_PAYLOAD_INVALID' USING errcode='22023'; END IF;
   v_reason:=nullif(btrim(v_payload->>'override_reason'),'');
   IF v_reason IS NOT NULL AND (v_reason!~'^HERMES-TEST' OR length(v_reason)>240) THEN RAISE EXCEPTION 'PDC_365_SYNTHETIC_REASON_REQUIRED' USING errcode='22023'; END IF;
   v_result:=public.move_workshop_booking(p_subject_id,p_expected_subject_version,v_payload->>'stage_code',(v_payload->>'bay_number')::integer,
    (v_payload->>'scheduled_start_at')::timestamptz,nullif(v_payload->>'duration_minutes','')::integer,v_reason,
    jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='workshop_start' THEN
   IF v_payload<>jsonb_strip_nulls(jsonb_build_object('actual_at',v_payload->'actual_at')) THEN RAISE EXCEPTION 'PDC_365_WORKSHOP_START_PAYLOAD_INVALID' USING errcode='22023'; END IF;
   v_result:=public.start_workshop_work(p_subject_id,p_expected_subject_version,nullif(v_payload->>'actual_at','')::timestamptz,
    jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='workshop_stop' THEN
   IF v_payload<>jsonb_build_object('reason',v_payload->'reason') THEN RAISE EXCEPTION 'PDC_365_WORKSHOP_STOP_PAYLOAD_INVALID' USING errcode='22023'; END IF;
   v_reason:=btrim(coalesce(v_payload->>'reason',''));
   IF v_reason!~'^HERMES-TEST' OR length(v_reason)>240 THEN RAISE EXCEPTION 'PDC_365_SYNTHETIC_REASON_REQUIRED' USING errcode='22023'; END IF;
   v_result:=public.stop_workshop_work(p_subject_id,p_expected_subject_version,v_reason,jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='workshop_resume' THEN
   IF v_payload<>'{}'::jsonb THEN RAISE EXCEPTION 'PDC_365_EMPTY_PAYLOAD_REQUIRED' USING errcode='22023'; END IF;
   v_result:=public.resume_workshop_work(p_subject_id,p_expected_subject_version,jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='workshop_complete' THEN
   IF v_payload<>jsonb_strip_nulls(jsonb_build_object('work_key',v_payload->'work_key','actual_at',v_payload->'actual_at')) THEN RAISE EXCEPTION 'PDC_365_WORKSHOP_COMPLETE_PAYLOAD_INVALID' USING errcode='22023'; END IF;
   v_work_key:=nullif(btrim(v_payload->>'work_key'),'');
   v_result:=public.complete_workshop_work(p_subject_id,p_expected_subject_version,v_work_key,
    nullif(v_payload->>'actual_at','')::timestamptz,jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='sublet_update' THEN
   IF v_payload<>jsonb_build_object('out_date',v_payload->'out_date','expected_return_date',v_payload->'expected_return_date','notes',v_payload->'notes') THEN
    RAISE EXCEPTION 'PDC_365_SUBLET_UPDATE_PAYLOAD_INVALID' USING errcode='22023'; END IF;
   IF coalesce(v_payload->>'notes','')!~'^HERMES-TEST' OR length(v_payload->>'notes')>240 THEN RAISE EXCEPTION 'PDC_365_SYNTHETIC_NOTES_REQUIRED' USING errcode='22023'; END IF;
   v_result:=public.update_pdc_sublet_booking(p_subject_id,p_expected_subject_version,(v_payload->>'out_date')::date,
    (v_payload->>'expected_return_date')::date,v_payload->>'notes');
  ELSIF p_action='sublet_return' THEN
   IF v_payload<>jsonb_build_object('returned_at',v_payload->'returned_at') THEN RAISE EXCEPTION 'PDC_365_SUBLET_RETURN_PAYLOAD_INVALID' USING errcode='22023'; END IF;
   v_result:=public.return_pdc_sublet_booking(p_subject_id,p_expected_subject_version,nullif(v_payload->>'returned_at','')::timestamptz);
  END IF;
 END IF;
 END IF;

 SELECT * INTO v_vehicle_after FROM public.vehicles WHERE id=p_vehicle_id;
 IF v_vehicle_after.stock_number IS DISTINCT FROM v_registry.stock_number
   OR v_vehicle_after.customer_name IS DISTINCT FROM v_registry.customer_name
   OR v_vehicle_after.job_card_number IS DISTINCT FROM v_registry.job_card_number
   OR v_vehicle_after.vehicle_description IS DISTINCT FROM v_registry.vehicle_description
   OR v_vehicle_after.source_system IS DISTINCT FROM 'hermes_overnight_synthetic'
   OR v_vehicle_after.source_batch_id IS DISTINCT FROM p_run_id OR v_vehicle_after.source_record_id IS DISTINCT FROM v_registry.stock_number THEN
  RAISE EXCEPTION 'PDC_365_SYNTHETIC_IDENTITY_POSTCONDITION' USING errcode='55000';
 END IF;
 v_protected_after:=public.pdc_hermes_test_protected_digest_365();
 v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT revision INTO v_pdc_revision_after FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT revision INTO v_workshop_revision_after FROM public.workshop_revision WHERE id=1;
 SELECT revision INTO v_navision_revision_after FROM public.navision_backend_revision WHERE singleton;
 SELECT encode(extensions.digest(convert_to(jsonb_build_object('vehicle',to_jsonb(v_vehicle_after),
  'work',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicle_work_items x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'bookings',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.workshop_bookings x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'parts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicle_parts_updates x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'sublets',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.booking_id) FROM public.pdc_sublet_booking_instances x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'booking_assignments',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE b.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'booking_history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM public.workshop_booking_history h JOIN public.workshop_bookings b ON b.id=h.booking_id WHERE b.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'parts_overrides',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.workshop_parts_overrides x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'sublet_history',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.pdc_sublet_booking_instance_history x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'movements',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicle_movements x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'audit',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.audit_events x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb))::text,'UTF8'),'sha256'),'hex') INTO v_target_state_after;
 IF v_protected_after IS DISTINCT FROM v_protected_before OR v_notifications_before<>0 OR v_notifications_after<>0
   OR v_pdc_revision_after<v_pdc_revision_before OR v_pdc_revision_after-v_pdc_revision_before>10
   OR v_workshop_revision_after<v_workshop_revision_before OR v_workshop_revision_after-v_workshop_revision_before>10
   OR v_navision_revision_after<v_navision_revision_before OR v_navision_revision_after-v_navision_revision_before>10
   OR (NOT coalesce((v_result->>'ok')::boolean,false) AND (
      v_target_state_after IS DISTINCT FROM v_target_state_before
      OR v_pdc_revision_after IS DISTINCT FROM v_pdc_revision_before
      OR v_workshop_revision_after IS DISTINCT FROM v_workshop_revision_before
      OR v_navision_revision_after IS DISTINCT FROM v_navision_revision_before)) THEN
  RAISE EXCEPTION 'PDC_365_PROTECTED_NOTIFICATION_REVISION_OR_FAILED_ACTION_POSTCONDITION' USING errcode='55000';
 END IF;
 IF p_subject_id IS NOT NULL THEN
  IF p_action LIKE 'workshop_%' THEN SELECT version INTO v_subject_version_after FROM public.workshop_bookings WHERE id=p_subject_id;
  ELSE SELECT version INTO v_subject_version_after FROM public.pdc_sublet_booking_instances WHERE booking_id=p_subject_id; END IF;
 END IF;
 v_receipt_id:=extensions.uuid_generate_v5('36500000-0000-5000-8000-000000000365'::uuid,
  p_run_id||':'||v_actor::text||':'||p_idempotency_key::text);
 v_result:=jsonb_build_object('ok',coalesce((v_result->>'ok')::boolean,false),
  'code',CASE WHEN coalesce((v_result->>'ok')::boolean,false) THEN 'synthetic_action_applied' ELSE 'synthetic_action_rejected' END,
  'synthetic_wrapper',true,'replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_sha,'run_id',p_run_id,'action',p_action,
  'vehicle_id',p_vehicle_id,'vehicle_version_before',v_vehicle_before.version,'vehicle_version_after',v_vehicle_after.version,
  'subject_id',p_subject_id,'subject_version_before',p_expected_subject_version,'subject_version_after',v_subject_version_after,
  'protected_state',v_protected_after,'notification_delta',v_notifications_after-v_notifications_before,
  'revisions',jsonb_build_object('pdc_email',jsonb_build_object('before',v_pdc_revision_before,'after',v_pdc_revision_after,'delta',v_pdc_revision_after-v_pdc_revision_before),
   'workshop',jsonb_build_object('before',v_workshop_revision_before,'after',v_workshop_revision_after,'delta',v_workshop_revision_after-v_workshop_revision_before),
   'navision',jsonb_build_object('before',v_navision_revision_before,'after',v_navision_revision_after,'delta',v_navision_revision_after-v_navision_revision_before)),
  'result',v_result);
 INSERT INTO public.pdc_overnight_synthetic_mutation_receipts_365(receipt_id,run_id,vehicle_id,actor_id,actor_email,
  idempotency_key,action,request_sha256,request_payload,response)
 VALUES(v_receipt_id,p_run_id,p_vehicle_id,v_actor,v_email,p_idempotency_key,p_action,v_request_sha,v_payload,v_result);
 IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_365_FINAL_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 RETURN v_result;
END $apply$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb) FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_hermes_test_vehicle_edit_365(text,uuid,integer,uuid,text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'vehicle_edit',jsonb_build_object('pmb_key_tag',$5)) $$;
CREATE FUNCTION public.pdc_hermes_test_set_work_states_365(text,uuid,integer,uuid,jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'work_states',jsonb_build_object('work_states',$5)) $$;
CREATE FUNCTION public.pdc_hermes_test_lifecycle_365(text,uuid,integer,uuid,text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim($5)) NOT IN('to_pmb','ready_qc','qc_to_rft','collect') THEN RAISE EXCEPTION 'PDC_365_LIFECYCLE_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'lifecycle_'||lower(btrim($5)),'{}'::jsonb);
END $$;
CREATE FUNCTION public.pdc_hermes_test_parts_365(text,uuid,integer,uuid,text,date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim($5)) NOT IN('eta','ordered','complete') OR (lower(btrim($5))<>'eta' AND $6 IS NOT NULL) THEN RAISE EXCEPTION 'PDC_365_PARTS_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'parts_'||lower(btrim($5)),
  CASE WHEN lower(btrim($5))='eta' THEN jsonb_build_object('worst_eta',$6) ELSE '{}'::jsonb END);
END $$;
CREATE FUNCTION public.pdc_hermes_test_parts_stoppage_365(text,uuid,integer,uuid,text,text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim($5)) NOT IN('stoppage','recover') OR (lower(btrim($5))='recover' AND $6 IS NOT NULL) THEN RAISE EXCEPTION 'PDC_365_PARTS_STOPPAGE_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'parts_'||lower(btrim($5)),
  CASE WHEN lower(btrim($5))='stoppage' THEN jsonb_build_object('reason',$6) ELSE '{}'::jsonb END);
END $$;
CREATE FUNCTION public.pdc_hermes_test_schedule_365(text,uuid,integer,uuid,text,integer,timestamptz,integer,uuid,text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'workshop_schedule',jsonb_strip_nulls(jsonb_build_object(
  'stage_code',$5,'bay_number',$6,'scheduled_start_at',$7,'duration_minutes',$8,'technician_id',$9,'override_reason',$10))) $$;
CREATE FUNCTION public.pdc_hermes_test_booking_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim($7)) NOT IN('move','start','stop','resume','complete') THEN RAISE EXCEPTION 'PDC_365_BOOKING_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365($1,$2,$3,$4,$5,$6,'workshop_'||lower(btrim($7)),coalesce($8,'{}'::jsonb));
END $$;
CREATE FUNCTION public.pdc_hermes_test_sublet_365(text,uuid,integer,uuid,integer,uuid,text,uuid,date,date,timestamptz,text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF lower(btrim($7)) NOT IN('create','update','return') THEN RAISE EXCEPTION 'PDC_365_SUBLET_FACADE_ACTION_INVALID' USING errcode='22023'; END IF;
 RETURN public.pdc_hermes_test_apply_365($1,$2,$3,$4,$5,$6,'sublet_'||lower(btrim($7)),jsonb_strip_nulls(jsonb_build_object(
  'provider_id',$8,'out_date',$9,'expected_return_date',$10,'returned_at',$11,'notes',$12)));
END $$;

REVOKE ALL ON FUNCTION public.pdc_hermes_test_vehicle_edit_365(text,uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_set_work_states_365(text,uuid,integer,uuid,jsonb) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_lifecycle_365(text,uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_parts_365(text,uuid,integer,uuid,text,date) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_parts_stoppage_365(text,uuid,integer,uuid,text,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_schedule_365(text,uuid,integer,uuid,text,integer,timestamptz,integer,uuid,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_booking_365(text,uuid,integer,uuid,integer,uuid,text,jsonb) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_sublet_365(text,uuid,integer,uuid,integer,uuid,text,uuid,date,date,timestamptz,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_vehicle_edit_365(text,uuid,integer,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_set_work_states_365(text,uuid,integer,uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_lifecycle_365(text,uuid,integer,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_parts_365(text,uuid,integer,uuid,text,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_parts_stoppage_365(text,uuid,integer,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_schedule_365(text,uuid,integer,uuid,text,integer,timestamptz,integer,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_booking_365(text,uuid,integer,uuid,integer,uuid,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_sublet_365(text,uuid,integer,uuid,integer,uuid,text,uuid,date,date,timestamptz,text) TO authenticated;

CREATE FUNCTION public.read_pdc_hermes_test_mutation_state_365(p_run_id text,p_vehicle_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_result jsonb;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR v_actor IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
   AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved') THEN
  RAISE EXCEPTION 'PDC_365_READ_UNAUTHORIZED_OR_RUN_INVALID' USING errcode='42501'; END IF;
 IF NOT public.pdc_monitor_staging_guard() OR NOT public.pdc_hermes_test_dependency_guard_365()
   OR NOT public.pdc_hermes_test_registry_guard_365() OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_365_READ_CONTAINMENT_DRIFT' USING errcode='55000'; END IF;
 IF p_vehicle_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
  WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id) THEN RAISE EXCEPTION 'PDC_365_READ_OUTSIDE_REGISTRY' USING errcode='42501'; END IF;
 SELECT jsonb_build_object('ok',true,'run_id',p_run_id,'vehicle_id',p_vehicle_id,
  'vehicles',coalesce(jsonb_agg(jsonb_build_object('scenario_no',r.scenario_no,'scenario_name',r.scenario_name,
   'vehicle',to_jsonb(v),'work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),
   'bookings',coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.created_at,b.id) FROM public.workshop_bookings b WHERE b.vehicle_id=v.id),'[]'::jsonb),
   'parts',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.updated_at,p.id) FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id),'[]'::jsonb),
   'sublets',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.created_at,s.booking_id) FROM public.pdc_sublet_booking_instances s WHERE s.vehicle_id=v.id),'[]'::jsonb),
   'movements',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.vehicle_movements m WHERE m.vehicle_id=v.id),'[]'::jsonb),
   'audit_events',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.audit_events a WHERE a.vehicle_id=v.id),'[]'::jsonb),
   'sublet_history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM public.pdc_sublet_booking_instance_history h WHERE h.vehicle_id=v.id),'[]'::jsonb),
   'receipts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.receipt_id) FROM public.pdc_overnight_synthetic_mutation_receipts_365 x WHERE x.vehicle_id=v.id),'[]'::jsonb)
  ) ORDER BY r.scenario_no),'[]'::jsonb),
  'protected_state',public.pdc_hermes_test_protected_digest_365(),
  'revisions',jsonb_build_object('pdc_email',(SELECT revision FROM public.pdc_email_vehicle_revision WHERE singleton),
    'workshop',(SELECT revision FROM public.workshop_revision WHERE id=1),
    'navision',(SELECT revision FROM public.navision_backend_revision WHERE singleton)),
  'notification_count',(SELECT count(*) FROM public.vehicle_notifications)) INTO v_result
 FROM public.pdc_overnight_synthetic_fleet_registry_363 r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.run_id=p_run_id AND (p_vehicle_id IS NULL OR r.vehicle_id=p_vehicle_id);
 RETURN v_result;
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_hermes_test_mutation_state_365(text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_hermes_test_mutation_state_365(text,uuid) TO authenticated;

DO $post$
BEGIN
 IF has_function_privilege('public','public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)','EXECUTE')
   OR has_function_privilege('authenticated','public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)','EXECUTE')
   OR has_table_privilege('authenticated','public.pdc_overnight_synthetic_mutation_receipts_365','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('service_role','public.pdc_overnight_synthetic_mutation_receipts_365','SELECT,INSERT,UPDATE,DELETE')
   OR NOT has_function_privilege('authenticated','public.pdc_hermes_test_set_work_states_365(text,uuid,integer,uuid,jsonb)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.read_pdc_hermes_test_mutation_state_365(text,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_365_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825020000','365_overnight_synthetic_mutation_wrappers',array[
 'Exact migration 364 head and disabled Monitor/mailbox/writer/notification containment',
 'Registry and static synthetic identity binding before and after every action',
 'Typed authenticated façades for work, lifecycle, Parts, Workshop and Sublet scenarios',
 'Actor-idempotent append-only receipts, version checks and protected-row digest proof',
 'QC to RFT synthetic path explicitly creates no external notification'
]);
NOTIFY pgrst,'reload schema';

DO $final$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_365_FINAL_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $final$;
COMMIT;
