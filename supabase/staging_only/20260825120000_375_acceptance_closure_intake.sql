-- STAGING ONLY 375: protected UI intake for three acceptance journeys.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-375-acceptance-closure-intake',0));
LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825110000' AND name='374_overnight_qc_fixture_registry_assignment')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825110000')
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR public.pdc_hermes_test_protected_digest_365() IS DISTINCT FROM jsonb_build_object('rows',1498,'sha256','cb43c3582df4fd646ffb457a627273ce59dc273034bc0e7b95c24c13f2dc437e') THEN
  RAISE EXCEPTION 'PDC_375_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

CREATE TABLE public.pdc_acceptance_vehicle_registry_375(
 registry_id uuid PRIMARY KEY,
 run_id text NOT NULL CHECK(run_id='HERMES-TEST-ACCEPTANCE-20260825'),
 journey_code text NOT NULL CHECK(journey_code IN('A','B','C')),
 stock_number text NOT NULL UNIQUE CHECK(stock_number IN('HERMES-TEST-AC-A','HERMES-TEST-AC-B','HERMES-TEST-AC-C')),
 customer_name text NOT NULL CHECK(customer_name LIKE 'HERMES-TEST%'),
 vehicle_description text NOT NULL CHECK(vehicle_description LIKE 'HERMES-TEST%'),
 job_card_number text NOT NULL UNIQUE CHECK(job_card_number LIKE 'HERMES-TEST%'),
 initial_location text NOT NULL CHECK(initial_location IN('YH','IT')),
 spec jsonb NOT NULL CHECK(jsonb_typeof(spec)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_acceptance_vehicle_registry_375 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_acceptance_vehicle_registry_375 FROM public,anon,authenticated,service_role;

INSERT INTO public.pdc_acceptance_vehicle_registry_375(registry_id,run_id,journey_code,stock_number,customer_name,vehicle_description,job_card_number,initial_location,spec) VALUES
(extensions.uuid_generate_v5('37500000-0000-5000-8000-000000000375'::uuid,'registry:A'),'HERMES-TEST-ACCEPTANCE-20260825','A','HERMES-TEST-AC-A','HERMES-TEST AC A','HERMES-TEST Standard acceptance journey','HERMES-TEST-AC-JC-A','YH',jsonb_build_object('journey','standard','duration_minutes',120,'required_work',jsonb_build_array('fitting','electrical','parts','sublet'))),
(extensions.uuid_generate_v5('37500000-0000-5000-8000-000000000375'::uuid,'registry:B'),'HERMES-TEST-ACCEPTANCE-20260825','B','HERMES-TEST-AC-B','HERMES-TEST AC B','HERMES-TEST Exact 918 minute acceptance journey','HERMES-TEST-AC-JC-B','IT',jsonb_build_object('journey','exact_918','duration_minutes',918,'required_work',jsonb_build_array('fitting','electrical','parts','sublet'))),
(extensions.uuid_generate_v5('37500000-0000-5000-8000-000000000375'::uuid,'registry:C'),'HERMES-TEST-ACCEPTANCE-20260825','C','HERMES-TEST-AC-C','HERMES-TEST AC C','HERMES-TEST Concurrent acceptance journey','HERMES-TEST-AC-JC-C','YH',jsonb_build_object('journey','concurrent','duration_minutes',180,'required_work',jsonb_build_array('fitting','electrical','parts','sublet')));

CREATE TABLE public.pdc_acceptance_vehicle_bindings_375(
 binding_id uuid PRIMARY KEY,
 registry_id uuid NOT NULL UNIQUE REFERENCES public.pdc_acceptance_vehicle_registry_375(registry_id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL UNIQUE REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 bound_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 bound_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_acceptance_vehicle_bindings_375 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_acceptance_vehicle_bindings_375 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_acceptance_vehicle_create_receipts_375(
 receipt_id uuid PRIMARY KEY,
 registry_id uuid NOT NULL REFERENCES public.pdc_acceptance_vehicle_registry_375(registry_id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key),
 UNIQUE(registry_id)
);
ALTER TABLE public.pdc_acceptance_vehicle_create_receipts_375 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_acceptance_vehicle_create_receipts_375 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_acceptance_lifecycle_receipts_375(
 receipt_id uuid PRIMARY KEY,
 registry_id uuid NOT NULL REFERENCES public.pdc_acceptance_vehicle_registry_375(registry_id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 idempotency_key uuid NOT NULL,
 action text NOT NULL CHECK(action IN('qc_complete','rft_transfer')),
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_acceptance_lifecycle_receipts_375 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_acceptance_lifecycle_receipts_375 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_acceptance_append_only_375()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $append$
BEGIN RAISE EXCEPTION 'PDC_375_APPEND_ONLY' USING errcode='55000'; END $append$;
REVOKE ALL ON FUNCTION public.pdc_acceptance_append_only_375() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_acceptance_registry_append_only_375 BEFORE UPDATE OR DELETE ON public.pdc_acceptance_vehicle_registry_375 FOR EACH ROW EXECUTE FUNCTION public.pdc_acceptance_append_only_375();
CREATE TRIGGER pdc_acceptance_bindings_append_only_375 BEFORE UPDATE OR DELETE ON public.pdc_acceptance_vehicle_bindings_375 FOR EACH ROW EXECUTE FUNCTION public.pdc_acceptance_append_only_375();
CREATE TRIGGER pdc_acceptance_receipts_append_only_375 BEFORE UPDATE OR DELETE ON public.pdc_acceptance_vehicle_create_receipts_375 FOR EACH ROW EXECUTE FUNCTION public.pdc_acceptance_append_only_375();
CREATE TRIGGER pdc_acceptance_lifecycle_receipts_append_only_375 BEFORE UPDATE OR DELETE ON public.pdc_acceptance_lifecycle_receipts_375 FOR EACH ROW EXECUTE FUNCTION public.pdc_acceptance_append_only_375();

CREATE FUNCTION public.pdc_acceptance_protected_digest_375()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET row_security=off AS $digest$
 WITH protected AS MATERIALIZED(
  SELECT v.id FROM public.vehicles v
  WHERE NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id)
    AND NOT EXISTS(SELECT 1 FROM public.pdc_acceptance_vehicle_bindings_375 b WHERE b.vehicle_id=v.id)
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
  coalesce(jsonb_agg(jsonb_build_object('relation',relation,'row',row_data) ORDER BY relation,row_data::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM material
$digest$;
REVOKE ALL ON FUNCTION public.pdc_acceptance_protected_digest_375() FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.create_pdc_acceptance_vehicle_375(
 p_stock_number text,p_customer_name text,p_vehicle_description text,p_job_card_number text,p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $create$
DECLARE
 v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_stock text:=upper(btrim(coalesce(p_stock_number,''))); v_customer text:=btrim(coalesce(p_customer_name,''));
 v_description text:=btrim(coalesce(p_vehicle_description,'')); v_job text:=upper(btrim(coalesce(p_job_card_number,'')));
 v_registry public.pdc_acceptance_vehicle_registry_375%rowtype; v_binding public.pdc_acceptance_vehicle_bindings_375%rowtype;
 v_receipt public.pdc_acceptance_vehicle_create_receipts_375%rowtype; v_vehicle public.vehicles%rowtype;
 v_request jsonb; v_request_sha text; v_receipt_id uuid; v_vehicle_id uuid; v_response jsonb;
 v_protected_before jsonb; v_protected_after jsonb; v_notifications_before bigint; v_pdc_before bigint; v_pdc_after bigint;
BEGIN
 IF v_actor IS NULL OR v_email='' OR p_idempotency_key IS NULL THEN RAISE EXCEPTION 'PDC_375_INVALID_INPUT' USING errcode='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.role='administrator' AND r.active AND r.account_status='approved' FOR SHARE) THEN
  RAISE EXCEPTION 'PDC_375_ADMINISTRATOR_REQUIRED' USING errcode='42501'; END IF;
 SELECT * INTO v_registry FROM public.pdc_acceptance_vehicle_registry_375 r WHERE r.stock_number=v_stock FOR SHARE;
 IF NOT FOUND OR v_customer<>v_registry.customer_name OR v_description<>v_registry.vehicle_description OR v_job<>v_registry.job_card_number THEN
  RAISE EXCEPTION 'PDC_375_REGISTRY_SPEC_MISMATCH' USING errcode='22023'; END IF;
 v_request:=jsonb_build_object('contract','pdc-acceptance-closure-intake-375','run_id',v_registry.run_id,'stock_number',v_stock,
  'customer_name',v_customer,'vehicle_description',v_description,'job_card_number',v_job,'idempotency_key',p_idempotency_key,'actor_id',v_actor);
 v_request_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-375-create:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_acceptance_vehicle_create_receipts_375 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_request_sha OR v_receipt.actor_email<>v_email THEN RAISE EXCEPTION 'PDC_375_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF;
  IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0
    OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->'protected_state'
    OR NOT EXISTS(SELECT 1 FROM public.pdc_acceptance_vehicle_bindings_375 b JOIN public.vehicles v ON v.id=b.vehicle_id
      WHERE b.registry_id=v_receipt.registry_id AND b.vehicle_id=v_receipt.vehicle_id AND v.deleted_at IS NULL
        AND v.source_batch_id='HERMES-TEST-ACCEPTANCE-20260825' AND v.source_record_id=v_stock) THEN
   RAISE EXCEPTION 'PDC_375_REPLAY_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)||jsonb_build_object('replay_containment_verified',true,'current_protected_state',public.pdc_acceptance_protected_digest_375(),'current_notification_count',(SELECT count(*) FROM public.vehicle_notifications));
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-375-registry:'||v_registry.registry_id::text,0));
 SELECT * INTO v_binding FROM public.pdc_acceptance_vehicle_bindings_375 WHERE registry_id=v_registry.registry_id FOR SHARE;
 IF FOUND THEN RAISE EXCEPTION 'PDC_375_REGISTRY_ALREADY_BOUND' USING errcode='23505'; END IF;
 LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
 LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
 LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
 LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_375_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.deleted_at IS NULL AND upper(btrim(v.stock_number))=v_stock) THEN
  RAISE EXCEPTION 'PDC_375_STOCK_ALREADY_EXISTS' USING errcode='23505'; END IF;
 v_protected_before:=public.pdc_acceptance_protected_digest_375(); v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT revision INTO v_pdc_before FROM public.pdc_email_vehicle_revision WHERE singleton FOR UPDATE;
 v_vehicle_id:=extensions.uuid_generate_v5('37500000-0000-5000-8000-000000000375'::uuid,'vehicle:'||v_registry.journey_code);
 PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v_vehicle_id::text,true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,make,model,
  lifecycle_state,visible_on_board,current_location,pmb_stage,eta_to_kewdale,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
 VALUES(v_vehicle_id,'HERMES-AC-'||v_registry.journey_code,v_stock,v_job,v_customer,v_description,'HERMES-TEST',v_description,
  'active',true,v_registry.initial_location,NULL,CASE WHEN v_registry.initial_location='IT' THEN DATE '2026-08-26' ELSE NULL END,
  'hermes_acceptance_synthetic','HERMES-TEST-ACCEPTANCE-20260825',v_stock,
  jsonb_build_object('contract','pdc-acceptance-closure-intake-375','run_id',v_registry.run_id,'journey_code',v_registry.journey_code,'registry_id',v_registry.registry_id,'request_sha256',v_request_sha),v_actor,v_actor)
 RETURNING * INTO v_vehicle;
 INSERT INTO public.pdc_acceptance_vehicle_bindings_375(binding_id,registry_id,vehicle_id,bound_by)
 VALUES(extensions.uuid_generate_v5('37500000-0000-5000-8000-000000000375'::uuid,'binding:'||v_registry.journey_code),v_registry.registry_id,v_vehicle.id,v_actor);
 PERFORM public.audit_pdc_event('insert','vehicles',v_vehicle.id,v_vehicle.id,NULL,to_jsonb(v_vehicle),
  jsonb_build_object('action','create_pdc_acceptance_vehicle_375','run_id',v_registry.run_id,'journey_code',v_registry.journey_code,'notification_enqueued',false));
 SELECT revision INTO v_pdc_after FROM public.pdc_email_vehicle_revision WHERE singleton;
 v_protected_after:=public.pdc_acceptance_protected_digest_375();
 IF v_protected_after IS DISTINCT FROM v_protected_before OR v_notifications_before<>0 OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR v_pdc_after<v_pdc_before OR v_pdc_after-v_pdc_before>6
   OR v_vehicle.source_batch_id<>'HERMES-TEST-ACCEPTANCE-20260825' OR v_vehicle.source_record_id<>v_stock THEN
  RAISE EXCEPTION 'PDC_375_PROTECTED_NOTIFICATION_REVISION_OR_IDENTITY_POSTCONDITION' USING errcode='55000'; END IF;
 v_receipt_id:=extensions.uuid_generate_v5('37500000-0000-5000-8000-000000000375'::uuid,v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','acceptance_vehicle_created','replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_sha,
  'run_id',v_registry.run_id,'journey_code',v_registry.journey_code,'registry_id',v_registry.registry_id,'vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version,
  'vehicle',to_jsonb(v_vehicle),'protected_state',v_protected_after,'notification_delta',0,'pdc_revision',jsonb_build_object('before',v_pdc_before,'after',v_pdc_after));
 INSERT INTO public.pdc_acceptance_vehicle_create_receipts_375(receipt_id,registry_id,vehicle_id,actor_id,actor_email,idempotency_key,request_sha256,request_payload,response)
 VALUES(v_receipt_id,v_registry.registry_id,v_vehicle.id,v_actor,v_email,p_idempotency_key,v_request_sha,v_request,v_response);
 RETURN v_response;
END $create$;
REVOKE ALL ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid) TO authenticated;

CREATE FUNCTION public.pdc_acceptance_lifecycle_375(
 p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_action text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $lifecycle$
DECLARE
 v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_action text:=lower(btrim(coalesce(p_action,'')));
 v_registry public.pdc_acceptance_vehicle_registry_375%rowtype; v_binding public.pdc_acceptance_vehicle_bindings_375%rowtype;
 v_receipt public.pdc_acceptance_lifecycle_receipts_375%rowtype; v_before public.vehicles%rowtype; v_after public.vehicles%rowtype;
 v_request jsonb; v_request_sha text; v_receipt_id uuid; v_response jsonb;
 v_protected_before jsonb; v_protected_after jsonb; v_notifications_before bigint; v_notifications_after bigint;
 v_pdc_before bigint; v_pdc_after bigint; v_workshop_before bigint; v_workshop_after bigint;
BEGIN
 IF p_vehicle_id IS NULL OR p_expected_version IS NULL OR p_expected_version<1 OR p_idempotency_key IS NULL OR v_action NOT IN('qc_complete','rft_transfer') THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_INVALID_INPUT' USING errcode='22023'; END IF;
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
   AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE) THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_UNAUTHORIZED' USING errcode='42501'; END IF;
 SELECT b.* INTO v_binding FROM public.pdc_acceptance_vehicle_bindings_375 b WHERE b.vehicle_id=p_vehicle_id FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_375_LIFECYCLE_OUTSIDE_REGISTRY' USING errcode='42501'; END IF;
 SELECT * INTO v_registry FROM public.pdc_acceptance_vehicle_registry_375 r WHERE r.registry_id=v_binding.registry_id FOR SHARE;
 v_request:=jsonb_build_object('contract','pdc-acceptance-lifecycle-375','run_id',v_registry.run_id,'vehicle_id',p_vehicle_id,
  'expected_version',p_expected_version,'idempotency_key',p_idempotency_key,'action',v_action,'actor_id',v_actor);
 v_request_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-375-lifecycle:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_acceptance_lifecycle_receipts_375 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_request_sha OR v_receipt.actor_email<>v_email THEN RAISE EXCEPTION 'PDC_375_LIFECYCLE_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF;
  IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0
    OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->'protected_state'
    OR NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=v_receipt.vehicle_id AND v.deleted_at IS NULL
      AND v.source_batch_id='HERMES-TEST-ACCEPTANCE-20260825' AND v.source_record_id=v_registry.stock_number) THEN
   RAISE EXCEPTION 'PDC_375_LIFECYCLE_REPLAY_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)||jsonb_build_object('replay_containment_verified',true,'current_notification_count',0);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-375-vehicle:'||p_vehicle_id::text,0));
 LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
 LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
 LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
 LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 SELECT * INTO v_before FROM public.vehicles v WHERE v.id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v_before.stock_number<>v_registry.stock_number OR v_before.customer_name<>v_registry.customer_name
   OR v_before.vehicle_description<>v_registry.vehicle_description OR v_before.job_card_number<>v_registry.job_card_number
   OR v_before.source_system<>'hermes_acceptance_synthetic' OR v_before.source_batch_id<>'HERMES-TEST-ACCEPTANCE-20260825'
   OR v_before.source_record_id<>v_registry.stock_number OR v_before.deleted_at IS NOT NULL THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_STATIC_IDENTITY_MISMATCH' USING errcode='55000'; END IF;
 IF v_before.version<>p_expected_version THEN RAISE EXCEPTION 'PDC_375_LIFECYCLE_VERSION_CONFLICT' USING errcode='40001'; END IF;
 PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);
 PERFORM 1 FROM public.vehicles v WHERE NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id)
   AND NOT EXISTS(SELECT 1 FROM public.pdc_acceptance_vehicle_bindings_375 b WHERE b.vehicle_id=v.id) ORDER BY v.id FOR SHARE;
 v_protected_before:=public.pdc_acceptance_protected_digest_375(); v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT revision INTO v_pdc_before FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT revision INTO v_workshop_before FROM public.workshop_revision WHERE id=1;
 IF v_action='qc_complete' THEN
  IF upper(btrim(coalesce(v_before.current_location,'')))<>'QC' OR v_before.lifecycle_state<>'active' OR v_before.qc_completed_at IS NOT NULL
    OR coalesce(array_length(public.pdc_qc_gate_issues(p_vehicle_id),1),0)>0 THEN
   RAISE EXCEPTION 'PDC_375_QC_GATE_BLOCKED' USING errcode='22023'; END IF;
  UPDATE public.vehicles SET qc_completed_at=clock_timestamp(),qc_completed_by=v_actor,version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
   WHERE id=p_vehicle_id RETURNING * INTO v_after;
  PERFORM public.audit_pdc_event('update','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),
   jsonb_build_object('action','pdc_acceptance_qc_complete_375','journey_code',v_registry.journey_code,'notification_enqueued',false,'remained_in_qc',true));
 ELSE
  IF upper(btrim(coalesce(v_before.current_location,'')))<>'QC' OR v_before.lifecycle_state<>'active' OR v_before.qc_completed_at IS NULL
    OR coalesce(array_length(public.pdc_qc_gate_issues(p_vehicle_id),1),0)>0 THEN
   RAISE EXCEPTION 'PDC_375_RFT_GATE_BLOCKED' USING errcode='22023'; END IF;
  UPDATE public.vehicles SET lifecycle_state='rft',current_location='RFT',rft_transferred_at=coalesce(rft_transferred_at,clock_timestamp()),
   version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v_after;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,
   from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(p_vehicle_id,'QC','RFT',v_before.pmb_stage,v_before.pmb_stage,v_before.pmb_bay_stage,v_before.pmb_bay_stage,
   v_before.pmb_bay_number,v_before.pmb_bay_number,'HERMES-TEST acceptance QC-to-RFT separate transfer; no notification',v_actor);
  PERFORM public.audit_pdc_event('rft','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),
   jsonb_build_object('action','pdc_acceptance_rft_transfer_375','journey_code',v_registry.journey_code,'notification_enqueued',false,'separate_from_qc_signoff',true));
 END IF;
 v_protected_after:=public.pdc_acceptance_protected_digest_375(); v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT revision INTO v_pdc_after FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT revision INTO v_workshop_after FROM public.workshop_revision WHERE id=1;
 IF v_protected_after IS DISTINCT FROM v_protected_before OR v_notifications_before<>0 OR v_notifications_after<>0
   OR v_pdc_after<v_pdc_before OR v_pdc_after-v_pdc_before>8 OR v_workshop_after<v_workshop_before OR v_workshop_after-v_workshop_before>8
   OR v_after.version<>v_before.version+1 OR v_after.source_batch_id<>'HERMES-TEST-ACCEPTANCE-20260825' THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 v_receipt_id:=extensions.uuid_generate_v5('37500000-0000-5000-8000-000000000375'::uuid,'lifecycle:'||v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','acceptance_'||v_action,'replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_sha,
  'run_id',v_registry.run_id,'journey_code',v_registry.journey_code,'registry_id',v_registry.registry_id,'vehicle_id',p_vehicle_id,
  'vehicle_version_before',v_before.version,'vehicle_version_after',v_after.version,'vehicle',to_jsonb(v_after),'protected_state',v_protected_after,
  'notification_delta',0,'pdc_revision',jsonb_build_object('before',v_pdc_before,'after',v_pdc_after),'workshop_revision',jsonb_build_object('before',v_workshop_before,'after',v_workshop_after));
 INSERT INTO public.pdc_acceptance_lifecycle_receipts_375(receipt_id,registry_id,vehicle_id,actor_id,actor_email,idempotency_key,action,request_sha256,request_payload,response)
 VALUES(v_receipt_id,v_registry.registry_id,p_vehicle_id,v_actor,v_email,p_idempotency_key,v_action,v_request_sha,v_request,v_response);
 RETURN v_response;
END $lifecycle$;
REVOKE ALL ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) TO authenticated;

CREATE FUNCTION public.read_pdc_acceptance_vehicle_state_375()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_result jsonb;
BEGIN
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved') THEN
  RAISE EXCEPTION 'PDC_375_READ_UNAUTHORIZED' USING errcode='42501'; END IF;
 IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN RAISE EXCEPTION 'PDC_375_READ_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 SELECT jsonb_build_object('ok',true,'run_id','HERMES-TEST-ACCEPTANCE-20260825','protected_state',public.pdc_acceptance_protected_digest_375(),
  'notification_count',(SELECT count(*) FROM public.vehicle_notifications),'vehicles',coalesce(jsonb_agg(jsonb_build_object('registry',to_jsonb(r),'binding',to_jsonb(b),'vehicle',to_jsonb(v),
   'work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),
   'bookings',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.id) FROM public.workshop_bookings x WHERE x.vehicle_id=v.id),'[]'::jsonb),
   'parts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.updated_at,x.id) FROM public.vehicle_parts_updates x WHERE x.vehicle_id=v.id),'[]'::jsonb),
   'sublets',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.booking_id) FROM public.pdc_sublet_booking_instances x WHERE x.vehicle_id=v.id),'[]'::jsonb),
   'movements',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.moved_at,x.id) FROM public.vehicle_movements x WHERE x.vehicle_id=v.id),'[]'::jsonb),
   'audit_events',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.id) FROM public.audit_events x WHERE x.vehicle_id=v.id),'[]'::jsonb),
   'lifecycle_receipts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.receipt_id) FROM public.pdc_acceptance_lifecycle_receipts_375 x WHERE x.vehicle_id=v.id),'[]'::jsonb),
   'create_receipt',to_jsonb(c)) ORDER BY r.journey_code),'[]'::jsonb)) INTO v_result
 FROM public.pdc_acceptance_vehicle_registry_375 r
 LEFT JOIN public.pdc_acceptance_vehicle_bindings_375 b ON b.registry_id=r.registry_id
 LEFT JOIN public.vehicles v ON v.id=b.vehicle_id
 LEFT JOIN public.pdc_acceptance_vehicle_create_receipts_375 c ON c.registry_id=r.registry_id;
 RETURN v_result;
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_acceptance_vehicle_state_375() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_acceptance_vehicle_state_375() TO authenticated;

DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_acceptance_vehicle_registry_375)<>3
   OR EXISTS(SELECT 1 FROM public.pdc_acceptance_vehicle_bindings_375)
   OR EXISTS(SELECT 1 FROM public.pdc_acceptance_vehicle_create_receipts_375)
   OR EXISTS(SELECT 1 FROM public.pdc_acceptance_lifecycle_receipts_375)
   OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM jsonb_build_object('rows',1498,'sha256','cb43c3582df4fd646ffb457a627273ce59dc273034bc0e7b95c24c13f2dc437e')
   OR has_function_privilege('public','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.create_pdc_acceptance_vehicle_375(text,text,text,text,uuid)','EXECUTE')
   OR has_function_privilege('public','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_375_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825120000','375_acceptance_closure_intake',array[
 'Three immutable HERMES-TEST acceptance journey reservations without fixture vehicle rows',
 'Administrator UI creation with exact registry identity and stable idempotency receipt',
 'Protected 153-vehicle cross-relation digest excluding both synthetic registries',
 'Disabled Monitor, mailbox, activation writer and zero-notification containment'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
