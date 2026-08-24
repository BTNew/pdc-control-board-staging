-- STAGING ONLY 368: assign the registry row fields, not the composite row value.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-368-overnight-registry-row-assignment',0));
LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825040000' AND name='367_overnight_sublet_history_primary_key')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260825040000' AND version~'^[0-9]{14}$')
   OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_368_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_hermes_test_apply_365(
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
 v_sibling_before jsonb; v_sibling_after jsonb;
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

 SELECT r.* INTO v_registry
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
 PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);

 -- Share-lock every protected vehicle row so the cross-relation digest describes one stable set
 -- while different synthetic vehicles remain independently mutable for two-session tests.
 PERFORM 1 FROM public.vehicles v WHERE NOT EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id
 ) ORDER BY v.id FOR SHARE;
 v_protected_before:=public.pdc_hermes_test_protected_digest_365();
 v_sibling_before:=public.pdc_hermes_test_sibling_digest_365(p_vehicle_id);
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
  'sublet_history',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.history_id) FROM public.pdc_sublet_booking_instance_history x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
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
 v_sibling_after:=public.pdc_hermes_test_sibling_digest_365(p_vehicle_id);
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
  'sublet_history',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.history_id) FROM public.pdc_sublet_booking_instance_history x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'movements',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicle_movements x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb),
  'audit',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.audit_events x WHERE x.vehicle_id=p_vehicle_id),'[]'::jsonb))::text,'UTF8'),'sha256'),'hex') INTO v_target_state_after;
 IF v_protected_after IS DISTINCT FROM v_protected_before OR v_sibling_after IS DISTINCT FROM v_sibling_before
   OR v_notifications_before<>0 OR v_notifications_after<>0
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
  'protected_state',v_protected_after,'sibling_state',v_sibling_after,'notification_delta',v_notifications_after-v_notifications_before,
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


DO $post$ BEGIN
 IF pg_get_functiondef('public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)'::regprocedure) NOT LIKE '%SELECT r.* INTO v_registry%'
   OR pg_get_functiondef('public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)'::regprocedure) LIKE '%SELECT r INTO v_registry%'
   OR has_function_privilege('authenticated','public.pdc_hermes_test_apply_365(text,uuid,integer,uuid,integer,uuid,text,jsonb)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_368_FUNCTION_OR_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825050000','368_overnight_registry_row_assignment',array[
 'Exact migration 367 head and staging containment',
 'Assign registry columns with SELECT r.* INTO the registry rowtype',
 'Preserve the reviewed core signature, body, owner and private ACL'
]);
NOTIFY pgrst,'reload schema';
DO $final$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_368_FINAL_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $final$;
COMMIT;
