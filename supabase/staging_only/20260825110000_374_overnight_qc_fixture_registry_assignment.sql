BEGIN;
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard() OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825100000' AND name='373_overnight_qc_fixture_completion')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825100000')
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_374_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.pdc_hermes_test_complete_qc_fixture_373(
 p_run_id text,p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_work_key text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $fn$
DECLARE
 v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_registry public.pdc_overnight_synthetic_fleet_registry_363%rowtype;
 v_vehicle_before public.vehicles%rowtype; v_vehicle_after public.vehicles%rowtype;
 v_work_before public.vehicle_work_items%rowtype; v_work_after public.vehicle_work_items%rowtype;
 v_receipt public.pdc_overnight_synthetic_mutation_receipts_365%rowtype;
 v_payload jsonb; v_request_sha text; v_receipt_id uuid; v_response jsonb; v_ok boolean:=false; v_replay boolean:=false;
 v_protected_before jsonb; v_protected_after jsonb; v_sibling_before jsonb; v_sibling_after jsonb;
 v_notifications_before bigint; v_notifications_after bigint;
 v_pdc_before bigint; v_pdc_after bigint; v_workshop_before bigint; v_workshop_after bigint; v_navision_before bigint; v_navision_after bigint;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR p_vehicle_id IS NULL OR p_expected_version IS NULL OR p_expected_version<1 OR p_idempotency_key IS NULL THEN
  RAISE EXCEPTION 'PDC_373_INVALID_INPUT' USING errcode='22023'; END IF;
 p_work_key:=lower(btrim(coalesce(p_work_key,'')));
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE) THEN
  RAISE EXCEPTION 'PDC_373_UNAUTHORIZED' USING errcode='42501'; END IF;
 v_payload:=jsonb_build_object('contract','pdc-overnight-qc-fixture-completion-373','run_id',p_run_id,'vehicle_id',p_vehicle_id,'expected_version',p_expected_version,'idempotency_key',p_idempotency_key,'work_key',p_work_key,'evidence','HERMES-TEST explicit synthetic completion; no physical-work claim');
 v_request_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-365-receipt:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_overnight_synthetic_mutation_receipts_365 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 v_replay:=FOUND;
 IF v_replay AND (v_receipt.request_sha256<>v_request_sha OR v_receipt.actor_email<>v_email) THEN
  RAISE EXCEPTION 'PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-365-vehicle:'||p_vehicle_id::text,0));
 LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
 LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
 LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
 LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 IF NOT public.pdc_monitor_staging_guard() OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_373_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 SELECT r.* INTO v_registry FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id FOR SHARE;
 IF NOT FOUND OR (v_registry.scenario_no,v_registry.stock_number,p_work_key) NOT IN ((12,'HERMES-TEST-012','fitting'),(13,'HERMES-TEST-013','electrical'),(14,'HERMES-TEST-014','fitting')) THEN
  RAISE EXCEPTION 'PDC_373_EXACT_SCENARIO_WORK_KEY_MISMATCH' USING errcode='42501'; END IF;
 SELECT * INTO v_vehicle_before FROM public.vehicles v WHERE v.id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v_vehicle_before.stock_number IS DISTINCT FROM v_registry.stock_number OR v_vehicle_before.customer_name IS DISTINCT FROM v_registry.customer_name
   OR v_vehicle_before.job_card_number IS DISTINCT FROM v_registry.job_card_number OR v_vehicle_before.vehicle_description IS DISTINCT FROM v_registry.vehicle_description
   OR v_vehicle_before.source_system IS DISTINCT FROM 'hermes_overnight_synthetic' OR v_vehicle_before.source_batch_id IS DISTINCT FROM p_run_id
   OR v_vehicle_before.source_record_id IS DISTINCT FROM v_registry.stock_number THEN
  RAISE EXCEPTION 'PDC_373_STATIC_IDENTITY_MISMATCH' USING errcode='55000'; END IF;
 PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);
 PERFORM 1 FROM public.vehicles v WHERE NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id) ORDER BY v.id FOR SHARE;
 v_protected_before:=public.pdc_hermes_test_protected_digest_365(); v_sibling_before:=public.pdc_hermes_test_sibling_digest_365(p_vehicle_id);
 v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT revision INTO v_pdc_before FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT revision INTO v_workshop_before FROM public.workshop_revision WHERE id=1;
 SELECT revision INTO v_navision_before FROM public.navision_backend_revision WHERE singleton;
 IF v_replay THEN
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)||jsonb_build_object('replay_containment_verified',true,'current_vehicle_version',v_vehicle_before.version,'current_protected_digest',v_protected_before,'current_notification_count',v_notifications_before);
 END IF;
 SELECT * INTO v_work_before FROM public.vehicle_work_items w WHERE w.vehicle_id=p_vehicle_id AND w.work_key=p_work_key FOR UPDATE;
 IF v_vehicle_before.version<>p_expected_version THEN
  v_response:=jsonb_build_object('ok',false,'error','vehicle_version_conflict','current_version',v_vehicle_before.version);
 ELSIF v_vehicle_before.lifecycle_state<>'active' OR upper(btrim(coalesce(v_vehicle_before.current_location,'')))<>'PMB' THEN
  v_response:=jsonb_build_object('ok',false,'error','fixture_not_active_in_pmb');
 ELSIF NOT FOUND OR NOT v_work_before.required OR v_work_before.completed THEN
  v_response:=jsonb_build_object('ok',false,'error','fixture_work_item_not_required_incomplete');
 ELSE
  UPDATE public.vehicle_work_items SET completed=true,completed_by=v_actor,completed_at=clock_timestamp(),updated_at=clock_timestamp()
   WHERE id=v_work_before.id RETURNING * INTO v_work_after;
  UPDATE public.vehicles SET version=version+1,qc_completed_at=NULL,qc_completed_by=NULL,updated_by=v_actor,updated_at=clock_timestamp()
   WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  PERFORM public.audit_pdc_event('update','vehicle_work_items',v_work_after.id,p_vehicle_id,to_jsonb(v_work_before),to_jsonb(v_work_after),
   jsonb_build_object('action','pdc_hermes_test_complete_qc_fixture_373','evidence','HERMES-TEST explicit synthetic completion','physical_work_claimed',false));
  v_ok:=true; v_response:=jsonb_build_object('ok',true,'code','synthetic_fixture_work_completed','work_item',to_jsonb(v_work_after),'vehicle',to_jsonb(v_vehicle_after),'physical_work_claimed',false);
 END IF;
 SELECT * INTO v_vehicle_after FROM public.vehicles WHERE id=p_vehicle_id;
 v_protected_after:=public.pdc_hermes_test_protected_digest_365(); v_sibling_after:=public.pdc_hermes_test_sibling_digest_365(p_vehicle_id);
 v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT revision INTO v_pdc_after FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT revision INTO v_workshop_after FROM public.workshop_revision WHERE id=1;
 SELECT revision INTO v_navision_after FROM public.navision_backend_revision WHERE singleton;
 IF v_protected_after IS DISTINCT FROM v_protected_before OR v_sibling_after IS DISTINCT FROM v_sibling_before OR v_notifications_before<>0 OR v_notifications_after<>0
   OR v_pdc_after<v_pdc_before OR v_pdc_after-v_pdc_before>6 OR v_workshop_after<v_workshop_before OR v_workshop_after-v_workshop_before>6
   OR v_navision_after<v_navision_before OR v_navision_after-v_navision_before>6
   OR (NOT v_ok AND (to_jsonb(v_vehicle_after) IS DISTINCT FROM to_jsonb(v_vehicle_before) OR to_jsonb(v_work_before) IS DISTINCT FROM to_jsonb((SELECT w FROM public.vehicle_work_items w WHERE w.vehicle_id=p_vehicle_id AND w.work_key=p_work_key)))) THEN
  RAISE EXCEPTION 'PDC_373_PROTECTED_NOTIFICATION_REVISION_OR_REJECTION_POSTCONDITION' USING errcode='55000'; END IF;
 v_receipt_id:=extensions.uuid_generate_v5('37300000-0000-5000-8000-000000000373'::uuid,p_run_id||':'||v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',coalesce((v_response->>'ok')::boolean,false),'code',CASE WHEN v_ok THEN 'synthetic_action_applied' ELSE 'synthetic_action_rejected' END,
  'synthetic_wrapper',true,'replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_sha,'run_id',p_run_id,'action','work_states','vehicle_id',p_vehicle_id,
  'vehicle_version_before',v_vehicle_before.version,'vehicle_version_after',v_vehicle_after.version,'protected_state',v_protected_after,'sibling_state',v_sibling_after,
  'notification_delta',v_notifications_after-v_notifications_before,'revisions',jsonb_build_object('pdc_email',jsonb_build_object('before',v_pdc_before,'after',v_pdc_after,'delta',v_pdc_after-v_pdc_before),'workshop',jsonb_build_object('before',v_workshop_before,'after',v_workshop_after,'delta',v_workshop_after-v_workshop_before),'navision',jsonb_build_object('before',v_navision_before,'after',v_navision_after,'delta',v_navision_after-v_navision_before)),'result',v_response);
 INSERT INTO public.pdc_overnight_synthetic_mutation_receipts_365(receipt_id,run_id,vehicle_id,actor_id,actor_email,idempotency_key,action,request_sha256,request_payload,response)
 VALUES(v_receipt_id,p_run_id,p_vehicle_id,v_actor,v_email,p_idempotency_key,'work_states',v_request_sha,v_payload,v_response);
 IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0 OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active) OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_373_FINAL_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 RETURN v_response;
END $fn$;

REVOKE ALL ON FUNCTION public.pdc_hermes_test_complete_qc_fixture_373(text,uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_complete_qc_fixture_373(text,uuid,integer,uuid,text) TO authenticated;
DO $post$
BEGIN
 IF has_function_privilege('public','public.pdc_hermes_test_complete_qc_fixture_373(text,uuid,integer,uuid,text)','EXECUTE')
  OR has_function_privilege('anon','public.pdc_hermes_test_complete_qc_fixture_373(text,uuid,integer,uuid,text)','EXECUTE')
  OR has_function_privilege('service_role','public.pdc_hermes_test_complete_qc_fixture_373(text,uuid,integer,uuid,text)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.pdc_hermes_test_complete_qc_fixture_373(text,uuid,integer,uuid,text)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_374_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825110000','374_overnight_qc_fixture_registry_assignment',array[
 'Exact migration 373 predecessor and disabled outbound containment',
 'Correct composite registry row assignment using SELECT r.* INTO rowtype',
 'Preserved exact scenarios, idempotency, ACL, digest and notification controls'
]);
COMMIT;
