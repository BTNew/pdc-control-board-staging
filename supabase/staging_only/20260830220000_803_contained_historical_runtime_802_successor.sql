-- STAGING ONLY 803: contained historical runtime compatibility successor.
-- The deployed 797 wrapper's scope_674 guard requires one active mailbox,
-- while approved 802/672 containment requires zero. This successor adds a
-- narrow authenticated adapter backed by the existing 672 verifier and
-- changes only the 797 wrapper's preflight guard. It never enables a mailbox,
-- task or pilot, contacts mail, performs historical Apply, creates outbox rows,
-- weakens RLS/identity or broadens grants.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-803-contained-historical-runtime-802',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v_wrapper text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR NOT public.pdc_monitor_staging_guard()
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830215000,802_repair_800_idempotency_cardinality)'
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260830215000')
 OR to_regprocedure('public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)') IS NOT NULL
 OR to_regprocedure('public.submit_pdc_historical_reconciliation_778(jsonb)') IS NULL
 OR to_regprocedure('public.submit_pdc_historical_reconciliation_778_pre797(jsonb)') IS NULL
 OR to_regclass('public.pdc_monitor_672_writer_reconciliation_800') IS NULL
 OR (SELECT count(*) FROM public.pdc_monitor_672_writer_reconciliation_800)<>1
 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
 OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
 OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
 OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled)<>1
 OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
 THEN RAISE EXCEPTION 'PDC_803_EXACT_802_CONTAINED_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
 SELECT p.prosrc INTO v_wrapper FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure;
 IF position('pdc_monitor_authenticated_active_scope_674' in v_wrapper)=0
 OR position('pdc_historical_797_complete_domain_snapshot' in v_wrapper)=0
 OR position('submit_pdc_historical_reconciliation_778_pre797' in v_wrapper)=0
 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v_wrapper)>0
 THEN RAISE EXCEPTION 'PDC_803_EXPECTED_797_WRAPPER_CONTRACT_MISSING' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.verify_pdc_historical_runtime_binding_authenticated_802(
  p_mode text,p_gateway_instance_id text,p_release_name text,p_source_sha text,p_manifest_sha256 text,
  p_semantic_planner_sha256 text DEFAULT NULL,p_semantic_planner_trust_receipt_sha256 text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $adapter$
DECLARE v_runtime jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
     OR coalesce(auth.jwt()->>'role','')<>'authenticated'
     OR lower(btrim(coalesce(p_mode,'')))<>'active'
  THEN RETURN jsonb_build_object('ok',false,'code','historical_runtime_binding_mismatch_802','activation_ready',false,'mailbox_active',false,'active_mailbox_count',0,'production_writes',false); END IF;
  v_runtime:=public.verify_pdc_monitor_runtime_binding_authenticated_672(
    p_mode,p_gateway_instance_id,p_release_name,p_source_sha,p_manifest_sha256,
    p_semantic_planner_sha256,p_semantic_planner_trust_receipt_sha256);
  IF v_runtime->>'ok' IS DISTINCT FROM 'true'
     OR v_runtime->>'writer_active' IS DISTINCT FROM 'true'
     OR v_runtime->>'operational' IS DISTINCT FROM 'true'
     OR v_runtime->>'activation_ready' IS DISTINCT FROM 'true'
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
  THEN RETURN jsonb_build_object('ok',false,'code','historical_runtime_containment_mismatch_802','activation_ready',false,'mailbox_active',false,'active_mailbox_count',0,'production_writes',false); END IF;
  RETURN v_runtime || jsonb_build_object(
    'ok',true,'code','historical_runtime_binding_verified_contained_802','mode','active',
    'operational',true,'activation_ready',true,'writer_active',true,'planner_commissioned',true,
    'mailbox_active',false,'active_mailbox_count',0,'task_enabled',false,
    'mailbox_contacted',false,'uid514_processed',false,'production_writes',false,
    'compatibility_successor_head',802);
END
$adapter$;
REVOKE ALL ON FUNCTION public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778(p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
SET statement_timeout='300s'
AS $wrapper$
DECLARE
 v_before jsonb; v_after jsonb; v_result jsonb; v_readback jsonb; v_vehicle_id uuid; v_stock text; v_request_hash text; v_receipt_id uuid;
 v_before_fp jsonb; v_after_fp jsonb; v_before_counts jsonb; v_after_counts jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    OR COALESCE(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true'
 THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 v_stock:=public.normalize_vehicle_stock_number(p_request->>'stock_number');
 IF v_stock IS NOT NULL AND v_stock<>'' THEN
   SELECT v.id INTO v_vehicle_id FROM public.vehicles v WHERE v.stock_number_normalized=v_stock ORDER BY (v.deleted_at IS NULL) DESC,v.id LIMIT 1;
 END IF;
 v_before:=public.pdc_historical_797_complete_domain_snapshot(v_vehicle_id);
 v_result:=public.submit_pdc_historical_reconciliation_778_pre797(p_request);
 IF v_result->>'ok'='true' THEN
   IF (v_result->'data'->'authoritative_state'->>'vehicle_id') IS NOT NULL THEN v_vehicle_id:=(v_result->'data'->'authoritative_state'->>'vehicle_id')::uuid; END IF;
   v_after:=public.pdc_historical_797_complete_domain_snapshot(v_vehicle_id);
   v_before_fp:=coalesce(v_before->'complete_domain_fingerprints','{}'::jsonb); v_after_fp:=coalesce(v_after->'complete_domain_fingerprints','{}'::jsonb);
   v_before_counts:=coalesce(v_before->'complete_domain_counts','{}'::jsonb); v_after_counts:=coalesce(v_after->'complete_domain_counts','{}'::jsonb);
   IF v_before_fp IS DISTINCT FROM v_after_fp OR v_before_counts IS DISTINCT FROM v_after_counts THEN
     RAISE EXCEPTION 'PDC_797_COMPLETE_DOMAIN_DRIFT' USING errcode='55000';
   END IF;
   IF (v_result->'data'->>'receipt_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_797_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   v_receipt_id:=(v_result->'data'->>'receipt_id')::uuid;
   SELECT r.request_sha256 INTO v_request_hash FROM public.pdc_historical_reconciliation_778_receipts r WHERE r.receipt_id=v_receipt_id;
   IF v_request_hash IS NULL THEN RAISE EXCEPTION 'PDC_797_AGGREGATE_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   INSERT INTO public.pdc_historical_complete_domain_readbacks_797(receipt_id,request_sha256,vehicle_id,before_authoritative_domain_state,after_authoritative_domain_state,before_complete_domain_fingerprints,after_complete_domain_fingerprints,before_complete_domain_counts,after_complete_domain_counts,complete_domain_fingerprint)
   VALUES(v_receipt_id,v_request_hash,v_vehicle_id,v_before,v_after,v_before_fp,v_after_fp,v_before_counts,v_after_counts,v_after->>'complete_domain_fingerprint') ON CONFLICT(receipt_id) DO NOTHING;
   SELECT jsonb_build_object('receipt_id',receipt_id,'request_sha256',request_sha256,'vehicle_id',vehicle_id,'before_authoritative_domain_state',before_authoritative_domain_state,'after_authoritative_domain_state',after_authoritative_domain_state,'before_complete_domain_fingerprints',before_complete_domain_fingerprints,'after_complete_domain_fingerprints',after_complete_domain_fingerprints,'before_complete_domain_counts',before_complete_domain_counts,'after_complete_domain_counts',after_complete_domain_counts,'complete_domain_fingerprint',complete_domain_fingerprint) INTO v_readback FROM public.pdc_historical_complete_domain_readbacks_797 WHERE receipt_id=v_receipt_id;
   IF v_readback IS NULL OR v_readback->>'request_sha256' IS NULL OR v_readback->>'complete_domain_fingerprint' IS NULL THEN RAISE EXCEPTION 'PDC_797_COMPLETE_DOMAIN_READBACK_FAILED' USING errcode='55000'; END IF;
   v_result:=jsonb_set(v_result,'{data,authoritative_domain_before}',v_readback->'before_authoritative_domain_state',true);
   v_result:=jsonb_set(v_result,'{data,authoritative_domain_state}',v_readback->'after_authoritative_domain_state',true);
   v_result:=jsonb_set(v_result,'{data,no_unrelated_drift}','true'::jsonb,true);
   v_result:=jsonb_set(v_result,'{data,complete_domain_fingerprints}',v_readback->'after_complete_domain_fingerprints',true);
   v_result:=jsonb_set(v_result,'{data,complete_domain_counts}',v_readback->'after_complete_domain_counts',true);
 END IF;
 RETURN v_result;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$wrapper$;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) TO authenticated;
DO $post$
DECLARE v_adapter text; v_wrapper text;
BEGIN
 SELECT pg_get_functiondef('public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)'::regprocedure),pg_get_functiondef('public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure) INTO v_adapter,v_wrapper;
 IF position('verify_pdc_monitor_runtime_binding_authenticated_672' in v_adapter)=0
 OR position('monitored_mailboxes where active' in v_adapter)=0
 OR position('historical_runtime_binding_verified_contained_802' in v_adapter)=0
 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v_wrapper)=0
 OR position('pdc_monitor_authenticated_active_scope_674' in v_wrapper)>0
 OR NOT has_function_privilege('authenticated','public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)','execute')
 OR has_function_privilege('anon','public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)','execute')
 OR has_function_privilege('service_role','public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)','execute')
 OR NOT has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
 OR has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
 OR has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_803_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830220000','803_contained_historical_runtime_802_successor',ARRAY[
 'Bind historical wrapper preflight to the exact authenticated 802/672 zero-mailbox containment contract',
 'Preserve fail-closed identity, planner, writer, pilot, task, RLS, authenticated-only and Production boundaries',
 'Keep the existing historical base, receipts, replay, authoritative readback and child processing unchanged'
]);
NOTIFY pgrST,'reload schema';
COMMIT;
