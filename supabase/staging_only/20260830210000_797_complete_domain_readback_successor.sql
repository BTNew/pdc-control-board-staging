-- STAGING ONLY 797: complete typed authoritative domain readback successor.
-- This append-only successor preserves the applied 796 wrapper while adding
-- deterministic movement, alias, stoppage, Sublet receipt, booking and
-- assignment snapshots with before/after no-unrelated-drift enforcement.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-797-complete-domain-readback',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard()
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
       IS DISTINCT FROM '(20260830203000,796_historical_domain_readback_guard_successor)'
    OR to_regprocedure('public.submit_pdc_historical_reconciliation_778(jsonb)') IS NULL
    OR to_regprocedure('public.submit_pdc_historical_reconciliation_778_pre797(jsonb)') IS NOT NULL
    OR to_regclass('public.pdc_historical_complete_domain_readbacks_797') IS NOT NULL
    OR to_regclass('public.vehicle_movements') IS NULL
    OR to_regclass('public.vehicle_aliases') IS NULL
    OR to_regclass('public.pdc_pmb_stoppage_receipts_422') IS NULL
    OR to_regclass('public.pdc_sublet_email_update_receipts') IS NULL
    OR to_regclass('public.workshop_bookings') IS NULL
    OR to_regclass('public.workshop_booking_assignments') IS NULL
 THEN RAISE EXCEPTION 'PDC_797_CURRENT_HEAD_OR_DOMAIN_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_historical_complete_domain_readbacks_797(
 receipt_id uuid PRIMARY KEY REFERENCES public.pdc_historical_reconciliation_778_receipts(receipt_id) ON DELETE RESTRICT,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 before_authoritative_domain_state jsonb NOT NULL CHECK(jsonb_typeof(before_authoritative_domain_state)='object'),
 after_authoritative_domain_state jsonb NOT NULL CHECK(jsonb_typeof(after_authoritative_domain_state)='object'),
 before_complete_domain_fingerprints jsonb NOT NULL CHECK(jsonb_typeof(before_complete_domain_fingerprints)='object'),
 after_complete_domain_fingerprints jsonb NOT NULL CHECK(jsonb_typeof(after_complete_domain_fingerprints)='object'),
 before_complete_domain_counts jsonb NOT NULL CHECK(jsonb_typeof(before_complete_domain_counts)='object'),
 after_complete_domain_counts jsonb NOT NULL CHECK(jsonb_typeof(after_complete_domain_counts)='object'),
 complete_domain_fingerprint text NOT NULL CHECK(complete_domain_fingerprint~'^[a-f0-9]{32}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_historical_complete_domain_readbacks_797 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_historical_complete_domain_readbacks_797 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_historical_complete_domain_readbacks_797 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE OR REPLACE FUNCTION public.pdc_historical_complete_domain_readback_797_immutable() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $immutable$
BEGIN RAISE EXCEPTION 'PDC_797_COMPLETE_DOMAIN_READBACK_IMMUTABLE' USING errcode='55000'; END;
$immutable$;
REVOKE ALL ON FUNCTION public.pdc_historical_complete_domain_readback_797_immutable() FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_complete_domain_readback_797_immutable() TO postgres;
CREATE TRIGGER pdc_797_complete_domain_readback_immutable BEFORE UPDATE OR DELETE ON public.pdc_historical_complete_domain_readbacks_797 FOR EACH ROW EXECUTE FUNCTION public.pdc_historical_complete_domain_readback_797_immutable();

CREATE OR REPLACE FUNCTION public.pdc_historical_797_complete_domain_snapshot(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $snapshot$
DECLARE
 v_base jsonb;
 v_movements jsonb:='[]'::jsonb; v_aliases jsonb:='[]'::jsonb; v_pmb_stoppages jsonb:='[]'::jsonb;
 v_sublet_receipts jsonb:='[]'::jsonb; v_bookings jsonb:='[]'::jsonb; v_assignments jsonb:='[]'::jsonb;
 v_movements_fp text; v_aliases_fp text; v_pmb_stoppages_fp text; v_sublet_receipts_fp text; v_bookings_fp text; v_assignments_fp text; v_complete_fp text;
BEGIN
 v_base:=public.pdc_historical_796_domain_snapshot(p_vehicle_id);
 IF p_vehicle_id IS NOT NULL THEN
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]'::jsonb) INTO v_movements FROM (
     SELECT id,vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by,moved_at
     FROM public.vehicle_movements WHERE vehicle_id=p_vehicle_id
   ) x;
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]'::jsonb) INTO v_aliases FROM (
     SELECT id,vehicle_id,alias_type,alias_value,active,created_at,alias_type_normalized,normalized_alias_value,source_system,source_system_normalized,source_batch_id,version,created_by,updated_by,updated_at
     FROM public.vehicle_aliases WHERE vehicle_id=p_vehicle_id
   ) x;
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.receipt_id),'[]'::jsonb) INTO v_pmb_stoppages FROM (
     SELECT receipt_id,vehicle_id,action,expected_vehicle_version,vehicle_version_before,vehicle_version_after,actor_id,actor_email,reason,idempotency_key,request_sha256,before_state,after_state,response,created_at
     FROM public.pdc_pmb_stoppage_receipts_422 WHERE vehicle_id=p_vehicle_id
   ) x;
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.receipt_id),'[]'::jsonb) INTO v_sublet_receipts FROM (
     SELECT receipt_id,replay_key,booking_id,vehicle_id,provider_id,provider_name,sender_email,message_id,attachment_sha256,evidence,language_kind,prior_version,resulting_version,applied_out_date,applied_expected_return_date,received_at,applied_at,applied_by
     FROM public.pdc_sublet_email_update_receipts WHERE vehicle_id=p_vehicle_id
   ) x;
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]'::jsonb) INTO v_bookings FROM (
     SELECT id,vehicle_id,stage_id,bay_id,status::text AS status,scheduled_start_at,scheduled_end_at,default_duration_minutes,actual_start_at,actual_end_at,actual_duration_minutes,stoppage_reason,stoppage_started_at,stoppage_accumulated_minutes,returned_to_queue_at,deleted_at,deleted_reason,source,version,created_by,updated_by,created_at,updated_at,metadata_legacy_plan_id,metadata,eta_at_booking,eta_risk_status,eta_risk_detected_at,legacy_ambiguity_quarantined
     FROM public.workshop_bookings WHERE vehicle_id=p_vehicle_id
   ) x;
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]'::jsonb) INTO v_assignments FROM (
     SELECT a.id,a.booking_id,a.technician_id,a.assignment_type::text AS assignment_type,a.assigned_at,a.assigned_by,a.scheduled_start_at,a.scheduled_end_at,a.released_at,a.notes,a.created_at,a.updated_at
     FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE b.vehicle_id=p_vehicle_id
   ) x;
 END IF;
 v_movements_fp:=md5(v_movements::text); v_aliases_fp:=md5(v_aliases::text); v_pmb_stoppages_fp:=md5(v_pmb_stoppages::text); v_sublet_receipts_fp:=md5(v_sublet_receipts::text); v_bookings_fp:=md5(v_bookings::text); v_assignments_fp:=md5(v_assignments::text);
 v_complete_fp:=md5((v_movements_fp||':'||v_aliases_fp||':'||v_pmb_stoppages_fp||':'||v_sublet_receipts_fp||':'||v_bookings_fp||':'||v_assignments_fp));
 RETURN v_base || jsonb_build_object(
   'vehicle_movements',jsonb_build_object('rows',v_movements,'count',jsonb_array_length(v_movements),'fingerprint',v_movements_fp),
   'vehicle_aliases',jsonb_build_object('rows',v_aliases,'count',jsonb_array_length(v_aliases),'fingerprint',v_aliases_fp),
   'pmb_stoppage_receipts',jsonb_build_object('rows',v_pmb_stoppages,'count',jsonb_array_length(v_pmb_stoppages),'fingerprint',v_pmb_stoppages_fp),
   'sublet_email_update_receipts',jsonb_build_object('rows',v_sublet_receipts,'count',jsonb_array_length(v_sublet_receipts),'fingerprint',v_sublet_receipts_fp),
   'workshop_bookings',jsonb_build_object('rows',v_bookings,'count',jsonb_array_length(v_bookings),'fingerprint',v_bookings_fp),
   'workshop_booking_assignments',jsonb_build_object('rows',v_assignments,'count',jsonb_array_length(v_assignments),'fingerprint',v_assignments_fp),
   'complete_domain_fingerprints',jsonb_build_object('vehicle_movements',v_movements_fp,'vehicle_aliases',v_aliases_fp,'pmb_stoppage_receipts',v_pmb_stoppages_fp,'sublet_email_update_receipts',v_sublet_receipts_fp,'workshop_bookings',v_bookings_fp,'workshop_booking_assignments',v_assignments_fp),
   'complete_domain_counts',jsonb_build_object('vehicle_movements',jsonb_array_length(v_movements),'vehicle_aliases',jsonb_array_length(v_aliases),'pmb_stoppage_receipts',jsonb_array_length(v_pmb_stoppages),'sublet_email_update_receipts',jsonb_array_length(v_sublet_receipts),'workshop_bookings',jsonb_array_length(v_bookings),'workshop_booking_assignments',jsonb_array_length(v_assignments)),
   'complete_domain_fingerprint',v_complete_fp
 );
END
$snapshot$;
REVOKE ALL ON FUNCTION public.pdc_historical_797_complete_domain_snapshot(uuid) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_797_complete_domain_snapshot(uuid) TO postgres;

ALTER FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) RENAME TO submit_pdc_historical_reconciliation_778_pre797;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre797(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre797(jsonb) TO postgres;

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
    OR NOT public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1')
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

DO $verify$
DECLARE w text; b boolean;
BEGIN
 SELECT pg_get_functiondef('public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure) INTO w;
 SELECT relrowsecurity AND relforcerowsecurity INTO b FROM pg_class WHERE oid='public.pdc_historical_complete_domain_readbacks_797'::regclass;
 IF position('submit_pdc_historical_reconciliation_778_pre797' in lower(w))=0 OR position('pdc_historical_797_complete_domain_snapshot' in lower(w))=0 OR position('pdc_797_complete_domain_drift' in lower(w))=0 OR position('authoritative_domain_before' in lower(w))=0 OR NOT coalesce(b,false) OR has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778_pre797(jsonb)','execute') OR has_function_privilege('authenticated','public.pdc_historical_797_complete_domain_snapshot(uuid)','execute') OR has_table_privilege('authenticated','public.pdc_historical_complete_domain_readbacks_797','select') OR has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute') OR has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute') OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_797_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830210000','797_complete_domain_readback_successor',ARRAY['Append-only complete typed vehicle movement, alias, PMB stoppage, Sublet receipt, workshop booking and assignment snapshots','Exact ordered identities, counts, timestamps, states and fingerprints with before/after no-unrelated-drift','Preserve 796 terminal guard, RLS, ACL, atomicity, replay and no mailbox/outbox/Production action']);
NOTIFY pgrst,'reload schema';
COMMIT;
