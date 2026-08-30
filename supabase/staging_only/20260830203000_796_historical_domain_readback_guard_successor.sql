-- STAGING ONLY 796: server-side terminal/location guard and complete domain readback.
-- This successor preserves the immutable 795 receipt and predecessor, while
-- adding an immutable domain readback keyed to the aggregate receipt.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-796-historical-domain-readback',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard()
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
       IS DISTINCT FROM '(20260830202000,795_historical_wrapper_short_name_repair)'
    OR to_regprocedure('public.submit_pdc_historical_reconciliation_778(jsonb)') IS NULL
    OR to_regprocedure('public.submit_pdc_historical_reconciliation_778_pre796(jsonb)') IS NOT NULL
    OR to_regclass('public.pdc_historical_domain_readbacks_796') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_796_CURRENT_HEAD_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_historical_domain_readbacks_796(
 receipt_id uuid PRIMARY KEY REFERENCES public.pdc_historical_reconciliation_778_receipts(receipt_id) ON DELETE RESTRICT,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 authoritative_domain_state jsonb NOT NULL CHECK(jsonb_typeof(authoritative_domain_state)='object'),
 before_protected_fingerprints jsonb NOT NULL CHECK(jsonb_typeof(before_protected_fingerprints)='object'),
 after_protected_fingerprints jsonb NOT NULL CHECK(jsonb_typeof(after_protected_fingerprints)='object'),
 protected_fingerprint text NOT NULL CHECK(protected_fingerprint~'^[a-f0-9]{32}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_historical_domain_readbacks_796 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_historical_domain_readbacks_796 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_historical_domain_readbacks_796 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE OR REPLACE FUNCTION public.pdc_historical_domain_readback_796_immutable() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $immutable$
BEGIN RAISE EXCEPTION 'PDC_796_DOMAIN_READBACK_IMMUTABLE' USING errcode='55000'; END;
$immutable$;
REVOKE ALL ON FUNCTION public.pdc_historical_domain_readback_796_immutable() FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_domain_readback_796_immutable() TO postgres;
CREATE TRIGGER pdc_796_domain_readback_immutable BEFORE UPDATE OR DELETE ON public.pdc_historical_domain_readbacks_796 FOR EACH ROW EXECUTE FUNCTION public.pdc_historical_domain_readback_796_immutable();

CREATE OR REPLACE FUNCTION public.pdc_historical_796_domain_snapshot(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $snapshot$
DECLARE
 v_vehicle jsonb; v_parts_rows jsonb; v_sublet_rows jsonb; v_sublet_instances jsonb; v_qc_rows jsonb; v_rft_rows jsonb;
 v_vehicle_fp text; v_parts_fp text; v_sublet_fp text; v_qc_fp text; v_rft_fp text; v_lifecycle_fp text; v_all_fp text;
BEGIN
 IF p_vehicle_id IS NULL THEN
   v_vehicle:=NULL; v_parts_rows:='[]'::jsonb; v_sublet_rows:='[]'::jsonb; v_sublet_instances:='[]'::jsonb; v_qc_rows:='[]'::jsonb; v_rft_rows:='[]'::jsonb;
   v_vehicle_fp:=md5('null'); v_lifecycle_fp:=md5('null');
 ELSE
   SELECT jsonb_build_object(
     'vehicle_id',v.id,'lifecycle_state',v.lifecycle_state::text,'current_location',v.current_location,'version',v.version,
     'deleted_at',v.deleted_at,'board_purged_at',v.board_purged_at,'rft_transferred_at',v.rft_transferred_at,
     'rft_collected_at',v.rft_collected_at,'rft_confirmed_at',v.rft_confirmed_at,'rft_transport_booked_at',v.rft_transport_booked_at,
     'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,
     'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'delivered_to_dealer_date',v.delivered_to_dealer_date,
     'qc_completed_at',v.qc_completed_at,'workshop_status',v.workshop_status
   ) INTO v_vehicle FROM public.vehicles v WHERE v.id=p_vehicle_id;
   IF v_vehicle IS NULL THEN
     v_parts_rows:='[]'::jsonb; v_sublet_rows:='[]'::jsonb; v_sublet_instances:='[]'::jsonb; v_qc_rows:='[]'::jsonb; v_rft_rows:='[]'::jsonb;
     v_vehicle_fp:=md5('missing'); v_lifecycle_fp:=md5('missing');
   ELSE
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]'::jsonb) INTO v_parts_rows FROM (
       SELECT id,vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_at
       FROM public.vehicle_parts_updates WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.vehicle_id,x.provider,x.booking_date,x.expected_return_date),'[]'::jsonb) INTO v_sublet_rows FROM (
       SELECT vehicle_id,provider,provider_email,po_sent_date,booking_date,expected_return_date,actual_return_date,notes,email_sent,version,updated_at,provider_source,provider_names,provider_source_values
       FROM public.pdc_sublet_bookings WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.booking_id),'[]'::jsonb) INTO v_sublet_instances FROM (
       SELECT booking_id,vehicle_id,vehicle_version,provider_id,provider_name,provider_email,out_date,expected_return_date,status,returned_at,cancelled_at,notes,source_kind,source_ref,source_evidence,version,updated_at
       FROM public.pdc_sublet_booking_instances WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.line_identity),'[]'::jsonb) INTO v_qc_rows FROM (
       SELECT vehicle_id,line_identity,source_kind,source_line_id,stage_code,completed,completed_by,completed_at,version,updated_at
       FROM public.pdc_qc_operation_completions_379 WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.notification_id),'[]'::jsonb) INTO v_rft_rows FROM (
       SELECT notification_id,lifecycle_receipt_id,vehicle_id,delivery_status,delivery_enabled,sent_at,delivered_at,created_at
       FROM public.pdc_rft_transport_email_outbox_734 WHERE vehicle_id=p_vehicle_id
     ) x;
     v_vehicle_fp:=md5(v_vehicle::text);
     v_lifecycle_fp:=md5(jsonb_build_object('lifecycle_state',v_vehicle->>'lifecycle_state','current_location',v_vehicle->>'current_location','deleted_at',v_vehicle->>'deleted_at','board_purged_at',v_vehicle->>'board_purged_at','rft_transferred_at',v_vehicle->>'rft_transferred_at','rft_collected_at',v_vehicle->>'rft_collected_at','rft_confirmed_at',v_vehicle->>'rft_confirmed_at','rft_transport_booked_at',v_vehicle->>'rft_transport_booked_at','dealer_transit_closed_at',v_vehicle->>'dealer_transit_closed_at','delivered_to_dealer_date',v_vehicle->>'delivered_to_dealer_date')::text);
   END IF;
 END IF;
 v_parts_fp:=md5(v_parts_rows::text); v_sublet_fp:=md5(jsonb_build_object('bookings',v_sublet_rows,'instances',v_sublet_instances)::text); v_qc_fp:=md5(v_qc_rows::text); v_rft_fp:=md5(v_rft_rows::text);
 v_all_fp:=md5((v_vehicle_fp||':'||v_lifecycle_fp||':'||v_parts_fp||':'||v_sublet_fp||':'||v_qc_fp||':'||v_rft_fp));
 RETURN jsonb_build_object(
   'vehicle',v_vehicle,
   'parts',jsonb_build_object('rows',v_parts_rows,'fingerprint',v_parts_fp),
   'sublet',jsonb_build_object('bookings',v_sublet_rows,'instances',v_sublet_instances,'fingerprint',v_sublet_fp),
   'qc',jsonb_build_object('rows',v_qc_rows,'fingerprint',v_qc_fp),
   'rft_transport',jsonb_build_object('rows',v_rft_rows,'fingerprint',v_rft_fp),
   'protected_fingerprints',jsonb_build_object('vehicle',v_vehicle_fp,'lifecycle_location',v_lifecycle_fp,'parts',v_parts_fp,'sublet',v_sublet_fp,'qc',v_qc_fp,'rft_transport',v_rft_fp,'all',v_all_fp)
 );
END
$snapshot$;
REVOKE ALL ON FUNCTION public.pdc_historical_796_domain_snapshot(uuid) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_796_domain_snapshot(uuid) TO postgres;

ALTER FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) RENAME TO submit_pdc_historical_reconciliation_778_pre796;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre796(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre796(jsonb) TO postgres;

CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778(p_request jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
SET statement_timeout='300s'
AS $wrapper$
DECLARE
 v_before jsonb; v_after jsonb; v_result jsonb; v_readback jsonb; v_vehicle public.vehicles%rowtype; v_vehicle_id uuid; v_receipt_id uuid; v_request_hash text; v_existing_request_hash text;
 v_stock text; v_match_count integer:=0; v_had_vehicle boolean:=false; v_replay boolean:=false; v_location text; v_lifecycle text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    OR NOT public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1')
 THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 v_stock:=public.normalize_vehicle_stock_number(p_request->>'stock_number');
 IF jsonb_typeof(p_request)='object' THEN
   SELECT r.request_sha256 INTO v_existing_request_hash FROM public.pdc_historical_reconciliation_778_receipts r WHERE r.actor_id=auth.uid() AND r.provider_uid=btrim(coalesce(p_request->>'provider_uid','')) AND r.parent_source_hash=lower(btrim(coalesce(p_request->>'parent_source_hash','')));
   IF v_existing_request_hash IS NOT NULL AND encode(extensions.digest(convert_to(coalesce(p_request->>'canonical_request_utf8',''),'UTF8'),'sha256'),'hex')=v_existing_request_hash THEN v_replay:=true; END IF;
 END IF;
 IF NOT v_replay AND jsonb_typeof(p_request)='object' AND v_stock IS NOT NULL AND v_stock<>'' THEN
   SELECT count(*) INTO v_match_count FROM public.vehicles v WHERE v.stock_number_normalized=v_stock;
   IF v_match_count>1 THEN RETURN jsonb_build_object('ok',false,'code','PDC_796_IDENTITY_CONFLICT'); END IF;
   SELECT * INTO v_vehicle FROM public.vehicles v WHERE v.stock_number_normalized=v_stock ORDER BY (v.deleted_at IS NULL) DESC,v.id LIMIT 1 FOR UPDATE;
   IF FOUND THEN
     v_had_vehicle:=true; v_vehicle_id:=v_vehicle.id; v_location:=lower(regexp_replace(btrim(coalesce(v_vehicle.current_location,'')),'\s+',' ','g')); v_lifecycle:=v_vehicle.lifecycle_state::text;
     IF v_lifecycle IN ('rft','completed','deleted') OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.board_purged_at IS NOT NULL
        OR v_vehicle.rft_transferred_at IS NOT NULL OR v_vehicle.rft_collected_at IS NOT NULL OR v_vehicle.rft_confirmed_at IS NOT NULL
        OR v_vehicle.rft_transport_booked_at IS NOT NULL OR v_vehicle.delivered_to_dealer_date IS NOT NULL OR v_vehicle.dealer_transit_closed_at IS NOT NULL
        OR v_location=ANY(ARRAY['yh','yard hold','vehicle yard hold','pmb','qc','pit','other','rft','collected','completed','delivered','delivered - at dealer','delivered - at body builder','planned for despatch - from twa','despatched - from body builder','vehicle out on consignment','waiting pd1','waiting pd2','vehicle at wharf','in transit to wa','ready for shipment']::text[])
     THEN RETURN jsonb_build_object('ok',false,'code','historical_terminal_or_protected_location','data',jsonb_build_object('vehicle_id',v_vehicle_id,'lifecycle_state',v_lifecycle,'current_location',v_vehicle.current_location,'review_required',true)); END IF;
     v_before:=public.pdc_historical_796_domain_snapshot(v_vehicle_id);
   END IF;
 END IF;
 v_result:=public.submit_pdc_historical_reconciliation_778_pre796(p_request);
 IF v_result->>'ok'='true' THEN
   IF (v_result->'data'->'authoritative_state'->>'vehicle_id') IS NOT NULL THEN v_vehicle_id:=(v_result->'data'->'authoritative_state'->>'vehicle_id')::uuid; END IF;
   IF v_vehicle_id IS NULL AND v_stock IS NOT NULL THEN SELECT v.id INTO v_vehicle_id FROM public.vehicles v WHERE v.stock_number_normalized=v_stock AND v.deleted_at IS NULL ORDER BY v.id LIMIT 1; END IF;
   v_after:=public.pdc_historical_796_domain_snapshot(v_vehicle_id);
   IF NOT v_replay THEN
     IF jsonb_typeof(v_after->'vehicle')='object' AND v_after->'vehicle'->>'lifecycle_state' IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'PDC_796_TERMINAL_READBACK_FAILED' USING errcode='55000'; END IF;
     IF v_had_vehicle AND (v_after->'vehicle'->>'lifecycle_state' IS DISTINCT FROM v_before->'vehicle'->>'lifecycle_state' OR v_after->'vehicle'->>'current_location' IS DISTINCT FROM v_before->'vehicle'->>'current_location' OR v_after->'protected_fingerprints' IS DISTINCT FROM v_before->'protected_fingerprints') THEN RAISE EXCEPTION 'PDC_796_PROTECTED_DOMAIN_DRIFT' USING errcode='55000'; END IF;
   END IF;
   IF (v_result->'data'->>'receipt_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_796_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   v_receipt_id:=(v_result->'data'->>'receipt_id')::uuid;
   SELECT r.request_sha256 INTO v_request_hash FROM public.pdc_historical_reconciliation_778_receipts r WHERE r.receipt_id=v_receipt_id;
   IF v_request_hash IS NULL THEN RAISE EXCEPTION 'PDC_796_AGGREGATE_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   INSERT INTO public.pdc_historical_domain_readbacks_796(receipt_id,request_sha256,vehicle_id,authoritative_domain_state,before_protected_fingerprints,after_protected_fingerprints,protected_fingerprint)
   VALUES(v_receipt_id,v_request_hash,v_vehicle_id,v_after,coalesce(v_before->'protected_fingerprints','{}'::jsonb),v_after->'protected_fingerprints',v_after->'protected_fingerprints'->>'all') ON CONFLICT(receipt_id) DO NOTHING;
   SELECT jsonb_build_object('receipt_id',receipt_id,'request_sha256',request_sha256,'vehicle_id',vehicle_id,'authoritative_domain_state',authoritative_domain_state,'before_protected_fingerprints',before_protected_fingerprints,'after_protected_fingerprints',after_protected_fingerprints,'protected_fingerprint',protected_fingerprint) INTO v_readback FROM public.pdc_historical_domain_readbacks_796 WHERE receipt_id=v_receipt_id;
   IF v_readback IS NULL OR v_readback->>'request_sha256' IS NULL OR v_readback->>'protected_fingerprint' IS NULL THEN RAISE EXCEPTION 'PDC_796_DOMAIN_READBACK_FAILED' USING errcode='55000'; END IF;
   IF v_readback->'authoritative_domain_state' IS NOT NULL THEN v_result:=jsonb_set(v_result,'{data,authoritative_domain_state}',v_readback->'authoritative_domain_state',true); END IF;
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
 SELECT relrowsecurity AND relforcerowsecurity INTO b FROM pg_class WHERE oid='public.pdc_historical_domain_readbacks_796'::regclass;
 IF position('submit_pdc_historical_reconciliation_778_pre796' in lower(w))=0 OR position('historical_terminal_or_protected_location' in lower(w))=0 OR position('pdc_historical_796_domain_snapshot' in lower(w))=0 OR position('pdc_796_protected_domain_drift' in lower(w))=0 OR NOT coalesce(b,false) OR has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778_pre796(jsonb)','execute') OR has_function_privilege('authenticated','public.pdc_historical_796_domain_snapshot(uuid)','execute') OR has_table_privilege('authenticated','public.pdc_historical_domain_readbacks_796','select') OR has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute') OR has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute') OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_796_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830203000','796_historical_domain_readback_guard_successor',ARRAY['Pre-DML server-side terminal and protected-location guard for historical canonical work','Immutable complete Parts/Sublet/QC/RFT transport and lifecycle/location readback with protected fingerprints','Preserve private predecessor, RLS, ACL, atomic rollback and replay; no mailbox or outbound action']);
NOTIFY pgrst,'reload schema';
COMMIT;
