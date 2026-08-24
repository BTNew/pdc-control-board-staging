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
  'work_states','lifecycle_to_pmb','lifecycle_ready_qc','lifecycle_qc_to_rft','lifecycle_collect',
  'parts_eta','parts_ordered','parts_complete','workshop_schedule','workshop_move','workshop_start',
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
 v_protected_count_before bigint; v_protected_count_after bigint;
 v_protected_digest_before text; v_protected_digest_after text;
 v_notifications_before bigint; v_notifications_after bigint;
 v_subject_vehicle uuid;
 v_before_qc public.vehicles%rowtype; v_after_qc public.vehicles%rowtype;
 v_work_key text; v_reason text;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR p_vehicle_id IS NULL
   OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL
   OR p_action IS NULL OR jsonb_typeof(v_payload)<>'object' THEN
  RAISE EXCEPTION 'PDC_365_INVALID_INPUT' USING errcode='22023';
 END IF;
 IF p_action NOT IN('work_states','lifecycle_to_pmb','lifecycle_ready_qc','lifecycle_qc_to_rft','lifecycle_collect',
  'parts_eta','parts_ordered','parts_complete','workshop_schedule','workshop_move','workshop_start','workshop_stop',
  'workshop_resume','workshop_complete','sublet_create','sublet_update','sublet_return') THEN
  RAISE EXCEPTION 'PDC_365_ACTION_NOT_ALLOWED' USING errcode='22023';
 END IF;
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
  IF v_receipt.request_sha256<>v_request_sha THEN
   RAISE EXCEPTION 'PDC_365_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023';
  END IF;
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
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
 IF NOT FOUND OR v_vehicle_before.version<>p_expected_vehicle_version
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

 -- Share-lock every protected vehicle row so the before/after digest describes one stable set
 -- while different synthetic vehicles remain independently mutable for two-session tests.
 PERFORM 1 FROM public.vehicles v WHERE NOT EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id
 ) ORDER BY v.id FOR SHARE;
 SELECT count(*),encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
 INTO v_protected_count_before,v_protected_digest_before FROM public.vehicles v WHERE NOT EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id);
 v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);

 IF p_action='work_states' THEN
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
  IF p_subject_id IS NOT NULL OR p_expected_subject_version IS NOT NULL
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
   v_reason:=nullif(btrim(v_payload->>'override_reason'),'');
   IF v_reason IS NOT NULL AND (v_reason!~'^HERMES-TEST' OR length(v_reason)>240) THEN RAISE EXCEPTION 'PDC_365_SYNTHETIC_REASON_REQUIRED' USING errcode='22023'; END IF;
   v_result:=public.move_workshop_booking(p_subject_id,p_expected_subject_version,v_payload->>'stage_code',(v_payload->>'bay_number')::integer,
    (v_payload->>'scheduled_start_at')::timestamptz,nullif(v_payload->>'duration_minutes','')::integer,v_reason,
    jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='workshop_start' THEN
   v_result:=public.start_workshop_work(p_subject_id,p_expected_subject_version,nullif(v_payload->>'actual_at','')::timestamptz,
    jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='workshop_stop' THEN
   v_reason:=btrim(coalesce(v_payload->>'reason',''));
   IF v_reason!~'^HERMES-TEST' OR length(v_reason)>240 THEN RAISE EXCEPTION 'PDC_365_SYNTHETIC_REASON_REQUIRED' USING errcode='22023'; END IF;
   v_result:=public.stop_workshop_work(p_subject_id,p_expected_subject_version,v_reason,jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='workshop_resume' THEN
   v_result:=public.resume_workshop_work(p_subject_id,p_expected_subject_version,jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='workshop_complete' THEN
   v_work_key:=nullif(btrim(v_payload->>'work_key'),'');
   v_result:=public.complete_workshop_work(p_subject_id,p_expected_subject_version,v_work_key,
    nullif(v_payload->>'actual_at','')::timestamptz,jsonb_build_object('source','HERMES-TEST-RUN-20260824'));
  ELSIF p_action='sublet_update' THEN
   IF coalesce(v_payload->>'notes','')!~'^HERMES-TEST' OR length(v_payload->>'notes')>240 THEN RAISE EXCEPTION 'PDC_365_SYNTHETIC_NOTES_REQUIRED' USING errcode='22023'; END IF;
   v_result:=public.update_pdc_sublet_booking(p_subject_id,p_expected_subject_version,(v_payload->>'out_date')::date,
    (v_payload->>'expected_return_date')::date,v_payload->>'notes');
  ELSIF p_action='sublet_return' THEN
   v_result:=public.return_pdc_sublet_booking(p_subject_id,p_expected_subject_version,nullif(v_payload->>'returned_at','')::timestamptz);
  END IF;
 END IF;

 IF NOT coalesce((v_result->>'ok')::boolean,false) THEN RETURN v_result||jsonb_build_object('synthetic_wrapper',true,'replay',false); END IF;

 SELECT * INTO v_vehicle_after FROM public.vehicles WHERE id=p_vehicle_id;
 IF v_vehicle_after.stock_number IS DISTINCT FROM v_registry.stock_number
   OR v_vehicle_after.customer_name IS DISTINCT FROM v_registry.customer_name
   OR v_vehicle_after.job_card_number IS DISTINCT FROM v_registry.job_card_number
   OR v_vehicle_after.vehicle_description IS DISTINCT FROM v_registry.vehicle_description
   OR v_vehicle_after.source_system IS DISTINCT FROM 'hermes_overnight_synthetic'
   OR v_vehicle_after.source_batch_id IS DISTINCT FROM p_run_id OR v_vehicle_after.source_record_id IS DISTINCT FROM v_registry.stock_number THEN
  RAISE EXCEPTION 'PDC_365_SYNTHETIC_IDENTITY_POSTCONDITION' USING errcode='55000';
 END IF;
 SELECT count(*),encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
 INTO v_protected_count_after,v_protected_digest_after FROM public.vehicles v WHERE NOT EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id);
 v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
 IF v_protected_count_after<>v_protected_count_before OR v_protected_digest_after IS DISTINCT FROM v_protected_digest_before
   OR v_notifications_before<>0 OR v_notifications_after<>0 THEN
  RAISE EXCEPTION 'PDC_365_PROTECTED_OR_NOTIFICATION_POSTCONDITION' USING errcode='55000';
 END IF;
 v_receipt_id:=extensions.uuid_generate_v5('36500000-0000-5000-8000-000000000365'::uuid,
  p_run_id||':'||v_actor::text||':'||p_idempotency_key::text);
 v_result:=jsonb_build_object('ok',true,'code','synthetic_action_applied','synthetic_wrapper',true,'replay',false,
  'receipt_id',v_receipt_id,'request_sha256',v_request_sha,'run_id',p_run_id,'action',p_action,
  'vehicle_id',p_vehicle_id,'vehicle_version_before',v_vehicle_before.version,'vehicle_version_after',v_vehicle_after.version,
  'protected_vehicle_count',v_protected_count_after,'protected_vehicle_digest',v_protected_digest_after,
  'notification_delta',v_notifications_after-v_notifications_before,'result',v_result);
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

CREATE FUNCTION public.pdc_hermes_test_set_work_states_365(text,uuid,integer,uuid,jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'work_states',jsonb_build_object('work_states',$5)) $$;
CREATE FUNCTION public.pdc_hermes_test_lifecycle_365(text,uuid,integer,uuid,text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'lifecycle_'||lower(btrim($5)),'{}'::jsonb) $$;
CREATE FUNCTION public.pdc_hermes_test_parts_365(text,uuid,integer,uuid,text,date)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'parts_'||lower(btrim($5)),
  CASE WHEN lower(btrim($5))='eta' THEN jsonb_build_object('worst_eta',$6) ELSE '{}'::jsonb END) $$;
CREATE FUNCTION public.pdc_hermes_test_schedule_365(text,uuid,integer,uuid,text,integer,timestamptz,integer,uuid,text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,NULL,NULL,$4,'workshop_schedule',jsonb_strip_nulls(jsonb_build_object(
  'stage_code',$5,'bay_number',$6,'scheduled_start_at',$7,'duration_minutes',$8,'technician_id',$9,'override_reason',$10))) $$;
CREATE FUNCTION public.pdc_hermes_test_booking_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,$4,$5,$6,'workshop_'||lower(btrim($7)),coalesce($8,'{}'::jsonb)) $$;
CREATE FUNCTION public.pdc_hermes_test_sublet_365(text,uuid,integer,uuid,integer,uuid,text,uuid,date,date,timestamptz,text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.pdc_hermes_test_apply_365($1,$2,$3,$4,$5,$6,'sublet_'||lower(btrim($7)),jsonb_strip_nulls(jsonb_build_object(
  'provider_id',$8,'out_date',$9,'expected_return_date',$10,'returned_at',$11,'notes',$12))) $$;

REVOKE ALL ON FUNCTION public.pdc_hermes_test_set_work_states_365(text,uuid,integer,uuid,jsonb) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_lifecycle_365(text,uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_parts_365(text,uuid,integer,uuid,text,date) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_schedule_365(text,uuid,integer,uuid,text,integer,timestamptz,integer,uuid,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_booking_365(text,uuid,integer,uuid,integer,uuid,text,jsonb) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_sublet_365(text,uuid,integer,uuid,integer,uuid,text,uuid,date,date,timestamptz,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_set_work_states_365(text,uuid,integer,uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_lifecycle_365(text,uuid,integer,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_parts_365(text,uuid,integer,uuid,text,date) TO authenticated;
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
 IF p_vehicle_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
  WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id) THEN RAISE EXCEPTION 'PDC_365_READ_OUTSIDE_REGISTRY' USING errcode='42501'; END IF;
 SELECT jsonb_build_object('ok',true,'run_id',p_run_id,'vehicle_id',p_vehicle_id,
  'vehicles',coalesce(jsonb_agg(jsonb_build_object('scenario_no',r.scenario_no,'scenario_name',r.scenario_name,
   'vehicle',to_jsonb(v),'work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),
   'bookings',coalesce((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.created_at,b.id) FROM public.workshop_bookings b WHERE b.vehicle_id=v.id),'[]'::jsonb),
   'parts',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.updated_at,p.id) FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id),'[]'::jsonb),
   'sublets',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.created_at,s.booking_id) FROM public.pdc_sublet_booking_instances s WHERE s.vehicle_id=v.id),'[]'::jsonb),
   'receipts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.receipt_id) FROM public.pdc_overnight_synthetic_mutation_receipts_365 x WHERE x.vehicle_id=v.id),'[]'::jsonb)
  ) ORDER BY r.scenario_no),'[]'::jsonb),'notification_count',(SELECT count(*) FROM public.vehicle_notifications)) INTO v_result
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
