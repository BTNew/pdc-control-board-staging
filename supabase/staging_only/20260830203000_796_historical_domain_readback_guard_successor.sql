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

DO $dependency$
DECLARE v_owner text; v_secdef boolean; v_config text; v_body text; v_acl text; v_trigger_hash text; v_executor_hash text; r record;
BEGIN
 FOR r IN SELECT * FROM (VALUES
   ('public.pdc_monitor_staging_guard()','596f9c1c46c405b245b7aca9e21e33a1232a0cae01a596a61d3f11168328edba','search_path=pg_catalog, public','postgres:EXECUTE:false|service_role:EXECUTE:false','pdc_monitor_staging_guard'),
   ('public.pdc_monitor_authenticated_active_scope_674(text)','cdf74a6b90abd0839a7226c881830844e5d0dcc20f8652141395662e9853f5ba','search_path=pg_catalog, public, auth','postgres:EXECUTE:false','pdc_monitor_authenticated_active_scope_674'),
   ('public.pdc_historical_writer_authorized_773(text,text,text,jsonb,text)','9bd5a567213e77dd4fb3ff45fa7031443444707505e576a3c17ace1c7c6699dd','search_path=pg_catalog, public, auth, extensions','postgres:EXECUTE:false','pdc_historical_reconciliation_writer_authorizations_773'),
   ('public.submit_pdc_historical_reconciliation_778(jsonb)','382ed16e467867b7955b837946556d8bc3f74cea92b8a9710ae99ac92977fb9a','search_path=pg_catalog, public, auth, extensions,statement_timeout=300s','authenticated:EXECUTE:false|postgres:EXECUTE:false','submit_pdc_historical_reconciliation_793_proposal_review_succes'),
   ('public.submit_pdc_historical_reconciliation_793_proposal_review_succes(jsonb)','024094fcc95115070ec171410ff472afe41457a0645aa4ebe48a2b41a64a0c76','search_path=pg_catalog, public, auth, extensions,statement_timeout=300s','postgres:EXECUTE:false','import_pdc_jobcard_attachment_canonical'),
   ('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','6497f2ba7ad244ea414f26d80400a3fa4bff2bf090746fdaa4cad800cbe53cfb','search_path=pg_catalog, public, extensions,statement_timeout=180s','postgres:EXECUTE:false','pdc_historical_provider_observations_778'),
   ('public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)','f73dd525e5dc6caccde4d5658bea8a2cabd95ec7f55898b792e5984568de5950','search_path=pg_catalog, public, extensions','postgres:EXECUTE:false','pdc_monitor_staging_guard'),
   ('public.enqueue_pdc_email_intake(jsonb,jsonb)','f4f6f14d094afc04c110c72ca6d6d2c642bf6bf2fa8a96f59d3115793a6accd8','search_path=pg_catalog, public, extensions','authenticated:EXECUTE:false|postgres:EXECUTE:false','pdc_historical_writer_authorized_773'),
   ('public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)','ac5d8baa2adbda0c078b3da5fa721ff262301ab6402954a92603ccc57d1c6086','search_path=pg_catalog, public, auth, extensions','authenticated:EXECUTE:false|postgres:EXECUTE:false','runtime_binding'),
   ('public.read_pdc_historical_reconciliation_778_receipt(uuid)','f6a954d162f3b9d7ae53a6fa073f4195b6a1067f51fc8ba7346217a95f518bb8','search_path=pg_catalog, public, auth, extensions','authenticated:EXECUTE:false|postgres:EXECUTE:false','pdc_historical_reconciliation_778_receipts'),
   ('public.pdc_historical_782_boundary_snapshot()','5540e514e14cc883bb7fcfa9d302118b32d03160f707f4094624711d7dcd4ab6','search_path=pg_catalog, public','postgres:EXECUTE:false','vehicle_parts_updates'),
   ('public.pdc_historical_782_unrelated_snapshot(uuid)','e2fc3356fb65cef9b3ae4f42864c08091997e7397e2ab09a7d6e0a93c6b64c8e','search_path=pg_catalog, public','postgres:EXECUTE:false','vehicles'),
   ('public.pdc_historical_job_card_attachments_immutable_782()','fa3c8b3fdef6daa59362e20ef54f1597199ab61acae087dd40c0d562bd852355','search_path=pg_catalog, public','postgres:EXECUTE:false','pdc_782_jobcard_evidence_immutable'),
 ) AS x(sig,body_hash,config,acl,callee) LOOP
   SELECT pg_get_userbyid(p.proowner),p.prosecdef,coalesce(array_to_string(p.proconfig,','),''),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex'),coalesce((SELECT string_agg(coalesce(pg_get_userbyid(a.grantee),'PUBLIC')||':'||a.privilege_type||':'||a.is_grantable,'|' ORDER BY coalesce(pg_get_userbyid(a.grantee),'PUBLIC'),a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),'') INTO v_owner,v_secdef,v_config,v_body,v_acl FROM pg_proc p WHERE p.oid=x.sig::regprocedure;
   IF v_owner IS DISTINCT FROM 'postgres' OR v_secdef IS DISTINCT FROM true OR v_config IS DISTINCT FROM x.config OR v_body IS DISTINCT FROM x.body_hash OR v_acl IS DISTINCT FROM x.acl OR position(lower(x.callee) in lower(pg_get_functiondef(x.sig::regprocedure)))=0 THEN RAISE EXCEPTION 'PDC_796_DEPENDENCY_CONTRACT_DRIFT:%',x.sig USING errcode='55000'; END IF;
 END LOOP;
 SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x.event_object_table||'|'||x.trigger_name||'|'||x.event_manipulation||'|'||x.action_timing||'|'||x.action_statement||'|'||t.tgenabled::text||'|'||t.tgtype::text||'|'||t.tgconstraint::text||'|'||t.tgdeferrable::text||'|'||t.tginitdeferred::text,'|' ORDER BY x.event_object_table,x.trigger_name,x.event_manipulation),''),'UTF8'),'sha256'),'hex') INTO v_trigger_hash FROM information_schema.triggers x JOIN pg_trigger t ON t.tgname=x.trigger_name AND t.tgrelid=(x.event_object_schema||'.'||x.event_object_table)::regclass WHERE event_object_schema='public' AND event_object_table IN ('ai_email_intake','ai_email_attachments','vehicles','vehicle_work_items','pdc_authenticated_email_operation_lines','vehicle_workshop_line_adjustments','vehicle_parts_updates','workshop_bookings','workshop_booking_assignments','pdc_sublet_bookings','pdc_sublet_booking_instances','pdc_qc_operation_completions_379','pdc_pmb_stoppage_receipts_422','pdc_email_monitor_current_head_compatibility_controls_766','pdc_email_monitor_pilot','pdc_email_monitor_status','pdc_qc_salesperson_update_outbox_399','pdc_rft_transport_email_outbox_734','pdc_rft_transport_salesperson_outbox_412','pdc_sublet_email_update_receipts','pdc_historical_provider_observations_778','pdc_historical_reconciliation_778_receipts');
 IF v_trigger_hash IS DISTINCT FROM '5c4c1b765a26143bd85b76de9cb0664edee66a6cfbc17acd6a75463a14df8211' THEN RAISE EXCEPTION 'PDC_796_TRIGGER_CONTRACT_DRIFT' USING errcode='55000'; END IF;
 SELECT encode(extensions.digest(convert_to(coalesce(string_agg(x.event_object_table||'|'||x.trigger_name||'|'||x.event_manipulation||'|'||x.action_timing||'|'||x.action_statement||'|'||coalesce(encode(extensions.digest(convert_to(pg_get_functiondef(t.tgfoid),'UTF8'),'sha256'),'hex'),'')||'|'||coalesce(pg_get_userbyid(p.proowner),'')||'|'||coalesce(array_to_string(p.proconfig,','),'')||'|'||coalesce((SELECT string_agg(coalesce(pg_get_userbyid(a.grantee),'PUBLIC')||':'||a.privilege_type||':'||a.is_grantable,'|' ORDER BY coalesce(pg_get_userbyid(a.grantee),'PUBLIC'),a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),'') ,'|' ORDER BY x.event_object_table,x.trigger_name,x.event_manipulation),''),'UTF8'),'sha256'),'hex') INTO v_executor_hash FROM information_schema.triggers x JOIN pg_trigger t ON t.tgname=x.trigger_name AND t.tgrelid=(x.event_object_schema||'.'||x.event_object_table)::regclass JOIN pg_proc p ON p.oid=t.tgfoid WHERE x.event_object_schema='public' AND x.event_object_table IN ('ai_email_intake','ai_email_attachments','vehicles','vehicle_work_items','pdc_authenticated_email_operation_lines','vehicle_workshop_line_adjustments','vehicle_parts_updates','workshop_bookings','workshop_booking_assignments','pdc_sublet_bookings','pdc_sublet_booking_instances','pdc_qc_operation_completions_379','pdc_pmb_stoppage_receipts_422','pdc_email_monitor_current_head_compatibility_controls_766','pdc_email_monitor_pilot','pdc_email_monitor_status','pdc_qc_salesperson_update_outbox_399','pdc_rft_transport_email_outbox_734','pdc_rft_transport_salesperson_outbox_412','pdc_sublet_email_update_receipts','pdc_historical_provider_observations_778','pdc_historical_reconciliation_778_receipts');
 IF v_executor_hash IS DISTINCT FROM 'c0e2afc1205b1648ab3816a58938454facee55bfc49132ac6e7af3ee84ff8cf8' THEN RAISE EXCEPTION 'PDC_796_TRIGGER_EXECUTOR_CONTRACT_DRIFT' USING errcode='55000'; END IF;
END $dependency$;

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
 v_vehicle jsonb; v_parts_rows jsonb; v_parts_stoppage_rows jsonb; v_sublet_rows jsonb; v_sublet_instances jsonb; v_qc_rows jsonb; v_rft_rows jsonb; v_rft_salesperson_rows jsonb; v_rft_lifecycle_rows jsonb; v_rft_evidence_rows jsonb; v_rft_action_rows jsonb; v_rft_intercept_rows jsonb; v_rft_statistics_rows jsonb;
 v_vehicle_fp text; v_parts_fp text; v_sublet_fp text; v_qc_fp text; v_rft_fp text; v_lifecycle_fp text; v_all_fp text;
BEGIN
 IF p_vehicle_id IS NULL THEN
   v_vehicle:=NULL; v_parts_rows:='[]'::jsonb; v_parts_stoppage_rows:='[]'::jsonb; v_sublet_rows:='[]'::jsonb; v_sublet_instances:='[]'::jsonb; v_qc_rows:='[]'::jsonb; v_rft_rows:='[]'::jsonb; v_rft_salesperson_rows:='[]'::jsonb; v_rft_lifecycle_rows:='[]'::jsonb; v_rft_evidence_rows:='[]'::jsonb; v_rft_action_rows:='[]'::jsonb; v_rft_intercept_rows:='[]'::jsonb; v_rft_statistics_rows:='[]'::jsonb;
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
     v_parts_rows:='[]'::jsonb; v_parts_stoppage_rows:='[]'::jsonb; v_sublet_rows:='[]'::jsonb; v_sublet_instances:='[]'::jsonb; v_qc_rows:='[]'::jsonb; v_rft_rows:='[]'::jsonb; v_rft_salesperson_rows:='[]'::jsonb; v_rft_lifecycle_rows:='[]'::jsonb; v_rft_evidence_rows:='[]'::jsonb; v_rft_action_rows:='[]'::jsonb; v_rft_intercept_rows:='[]'::jsonb; v_rft_statistics_rows:='[]'::jsonb;
     v_vehicle_fp:=md5('missing'); v_lifecycle_fp:=md5('missing');
   ELSE
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]'::jsonb) INTO v_parts_rows FROM (
       SELECT id,vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_at
       FROM public.vehicle_parts_updates WHERE vehicle_id=p_vehicle_id
       ) x;
       SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.receipt_id),'[]'::jsonb) INTO v_parts_stoppage_rows FROM (
       SELECT receipt_id,vehicle_id,actor_id,actor_email,idempotency_key,action,reason,expected_vehicle_version,request_sha256,before_state,after_state,response,created_at
       FROM public.pdc_parts_stoppage_receipts_376 WHERE vehicle_id=p_vehicle_id
       ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.vehicle_id,x.provider,x.booking_date,x.expected_return_date),'[]'::jsonb) INTO v_sublet_rows FROM (
       SELECT vehicle_id,provider,provider_email,po_sent_date,booking_date,expected_return_date,actual_return_date,notes,email_sent,version,updated_at,provider_source,provider_names
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
       SELECT notification_id,lifecycle_receipt_id,vehicle_id,recipient_email,delivery_status,delivery_enabled,sent_at,delivered_at,md5(payload::text) AS payload_fingerprint,created_at
       FROM public.pdc_rft_transport_email_outbox_734 WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.notification_id),'[]'::jsonb) INTO v_rft_salesperson_rows FROM (
       SELECT notification_id,transport_receipt_id,vehicle_id,recipient_email,delivery_status,sent_at,delivered_at,md5(payload::text) AS payload_fingerprint,created_at
       FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.receipt_id),'[]'::jsonb) INTO v_rft_lifecycle_rows FROM (
       SELECT receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,before_state,after_state,md5(evidence::text) AS evidence_fingerprint,md5(response::text) AS response_fingerprint,created_at
       FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.evidence_id),'[]'::jsonb) INTO v_rft_evidence_rows FROM (
       SELECT evidence_id,notification_id,vehicle_id,mime_version,mime_content_type,mime_sha256,photo_receipt_id,photo_bucket_id,photo_storage_path,photo_content_type,photo_byte_length,photo_sha256,intercepted,sent_at,delivered_at,created_at
       FROM public.pdc_rft_transport_email_evidence_734 WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.receipt_id),'[]'::jsonb) INTO v_rft_action_rows FROM (
       SELECT receipt_id,vehicle_id,action,expected_vehicle_version,vehicle_version_before,vehicle_version_after,actor_id,actor_email,idempotency_key,request_sha256,before_state,after_state,md5(response::text) AS response_fingerprint,created_at
       FROM public.pdc_rft_transport_action_receipts_412 WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.receipt_id),'[]'::jsonb) INTO v_rft_intercept_rows FROM (
       SELECT receipt_id,notification_id,transport_receipt_id,vehicle_id,actor_id,actor_email,claim_token,payload_sha256,mime_sha256,attachment_sha256,artifact_sha256,artifact_bytes,outcome,created_at
       FROM public.pdc_rft_transport_email_intercept_receipts_429 WHERE vehicle_id=p_vehicle_id
     ) x;
     SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.statistic_id),'[]'::jsonb) INTO v_rft_statistics_rows FROM (
       SELECT statistic_id,vehicle_id,delivered_receipt_id,started_at,closed_at,duration_seconds,status_literal,created_at
       FROM public.pdc_rft_dealer_transit_statistics_734 WHERE vehicle_id=p_vehicle_id
     ) x;
     v_vehicle_fp:=md5(v_vehicle::text);
     v_lifecycle_fp:=md5(jsonb_build_object('lifecycle_state',v_vehicle->>'lifecycle_state','current_location',v_vehicle->>'current_location','deleted_at',v_vehicle->>'deleted_at','board_purged_at',v_vehicle->>'board_purged_at','rft_transferred_at',v_vehicle->>'rft_transferred_at','rft_collected_at',v_vehicle->>'rft_collected_at','rft_confirmed_at',v_vehicle->>'rft_confirmed_at','rft_transport_booked_at',v_vehicle->>'rft_transport_booked_at','dealer_transit_closed_at',v_vehicle->>'dealer_transit_closed_at','delivered_to_dealer_date',v_vehicle->>'delivered_to_dealer_date')::text);
   END IF;
 END IF;
 v_parts_fp:=md5(jsonb_build_object('rows',v_parts_rows,'stoppage_receipts',v_parts_stoppage_rows)::text); v_sublet_fp:=md5(jsonb_build_object('bookings',v_sublet_rows,'instances',v_sublet_instances)::text); v_qc_fp:=md5(v_qc_rows::text); v_rft_fp:=md5(jsonb_build_object('outbox',v_rft_rows,'salesperson_outbox',v_rft_salesperson_rows,'lifecycle_receipts',v_rft_lifecycle_rows,'evidence',v_rft_evidence_rows,'action_receipts',v_rft_action_rows,'intercept_receipts',v_rft_intercept_rows,'dealer_transit_statistics',v_rft_statistics_rows)::text);
 v_all_fp:=md5((v_vehicle_fp||':'||v_lifecycle_fp||':'||v_parts_fp||':'||v_sublet_fp||':'||v_qc_fp||':'||v_rft_fp));
 RETURN jsonb_build_object(
   'vehicle',v_vehicle,
   'parts',jsonb_build_object('rows',v_parts_rows,'stoppage_receipts',v_parts_stoppage_rows,'fingerprint',v_parts_fp),
   'sublet',jsonb_build_object('bookings',v_sublet_rows,'instances',v_sublet_instances,'fingerprint',v_sublet_fp),
   'qc',jsonb_build_object('rows',v_qc_rows,'fingerprint',v_qc_fp),
   'rft_transport',jsonb_build_object('outbox',v_rft_rows,'salesperson_outbox',v_rft_salesperson_rows,'lifecycle_receipts',v_rft_lifecycle_rows,'evidence',v_rft_evidence_rows,'action_receipts',v_rft_action_rows,'intercept_receipts',v_rft_intercept_rows,'dealer_transit_statistics',v_rft_statistics_rows,'fingerprint',v_rft_fp),
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
        OR v_location=ANY(ARRAY['yh','yard hold','vehicle yard hold','pmb','qc','pit','other','rft','collected','completed','delivered','delivered - at dealer','delivered - at body builder','planned for despatch - from twa','despatched - from body builder','vehicle out on consignment','vehicle delayed','vehicle waiting for wholesale','planned for production','waiting pd1','waiting pd2','vehicle at wharf','in transit to wa','ready for shipment']::text[])
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
   IF v_replay AND v_vehicle_id IS NULL AND v_stock IS NOT NULL THEN
     SELECT count(*) INTO v_match_count FROM public.vehicles v WHERE v.stock_number_normalized=v_stock;
     IF v_match_count>1 THEN RAISE EXCEPTION 'PDC_796_REPLAY_IDENTITY_CONFLICT' USING errcode='55000'; END IF;
     IF v_match_count=1 THEN SELECT v.id INTO v_vehicle_id FROM public.vehicles v WHERE v.stock_number_normalized=v_stock ORDER BY v.id LIMIT 1; v_after:=public.pdc_historical_796_domain_snapshot(v_vehicle_id); END IF;
   END IF;
   IF v_replay AND v_vehicle_id IS NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_result->'data'->'attachment_receipts','[]'::jsonb)) r WHERE coalesce(r->'result'->>'code','')<>'historical_child_ambiguous') THEN RAISE EXCEPTION 'PDC_796_REPLAY_VEHICLE_READBACK_FAILED' USING errcode='55000'; END IF;
   SELECT r.request_sha256 INTO v_request_hash FROM public.pdc_historical_reconciliation_778_receipts r WHERE r.receipt_id=v_receipt_id;
   IF v_request_hash IS NULL THEN RAISE EXCEPTION 'PDC_796_AGGREGATE_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
   INSERT INTO public.pdc_historical_domain_readbacks_796(receipt_id,request_sha256,vehicle_id,authoritative_domain_state,before_protected_fingerprints,after_protected_fingerprints,protected_fingerprint)
   VALUES(v_receipt_id,v_request_hash,v_vehicle_id,v_after,coalesce(v_before->'protected_fingerprints','{}'::jsonb),v_after->'protected_fingerprints',v_after->'protected_fingerprints'->>'all') ON CONFLICT(receipt_id) DO NOTHING;
   SELECT jsonb_build_object('receipt_id',receipt_id,'request_sha256',request_sha256,'vehicle_id',vehicle_id,'authoritative_domain_state',authoritative_domain_state,'before_protected_fingerprints',before_protected_fingerprints,'after_protected_fingerprints',after_protected_fingerprints,'protected_fingerprint',protected_fingerprint) INTO v_readback FROM public.pdc_historical_domain_readbacks_796 WHERE receipt_id=v_receipt_id;
   IF v_readback IS NULL OR v_readback->>'request_sha256' IS NULL OR v_readback->>'protected_fingerprint' IS NULL THEN RAISE EXCEPTION 'PDC_796_DOMAIN_READBACK_FAILED' USING errcode='55000'; END IF;
   v_result:=jsonb_set(v_result,'{data,replay}',to_jsonb(v_replay),true);
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
