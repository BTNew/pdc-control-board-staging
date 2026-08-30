-- STAGING ONLY 833: correct an already-persisted all-unknown-hours
-- historical child receipt without mutating immutable legacy evidence. The
-- correction readback preserves NULL per-line values, keeps the legacy zero as
-- provenance only, and exposes explicit known/unknown counts and coverage.
BEGIN;
SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-833-operation-hours-correction',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v text;
BEGIN
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830252000,831_historical_navision_refresh_successor)' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'f8b349be16131a94067d3a48118e92ddcf43a6f9a0af7c746a7a65116ca194d0' OR (SELECT count(*) FROM public.pdc_historical_reconciliation_778_receipts)<>5 OR (SELECT coalesce(array_agg(provider_uid ORDER BY provider_uid),'{}'::text[]) FROM public.pdc_historical_reconciliation_778_receipts) IS DISTINCT FROM ARRAY['1:133','1:134','1:137','1:168','1:172']::text[] OR (SELECT count(*) FROM public.pdc_historical_provider_observations_778)<>24 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_809 WHERE active AND expires_at>clock_timestamp())<>5 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0 OR to_regclass('public.pdc_historical_operation_hours_evidence_833') IS NOT NULL THEN RAISE EXCEPTION 'PDC_833_CURRENT_HEAD_OR_OPERATION_HOURS_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_historical_operation_hours_evidence_833(
 evidence_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 historical_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_historical_reconciliation_778_receipts(receipt_id) ON DELETE RESTRICT,
 jobcard_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_jobcard_attachment_import_receipts(receipt_id) ON DELETE RESTRICT,
 provider_uid text NOT NULL CHECK(provider_uid='1:134'),
 operation_count integer NOT NULL CHECK(operation_count BETWEEN 1 AND 50),
 legacy_estimated_hours_sum numeric(10,2) NOT NULL,
 authoritative_estimated_hours_sum numeric(10,2),
 known_hours_sum numeric(10,2),
 known_hours_count integer NOT NULL CHECK(known_hours_count BETWEEN 0 AND 50),
 unknown_hours_count integer NOT NULL CHECK(unknown_hours_count BETWEEN 0 AND 50),
 hours_coverage numeric(6,5) NOT NULL CHECK(hours_coverage BETWEEN 0 AND 1),
 line_values_sha256 text NOT NULL CHECK(line_values_sha256~'^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(known_hours_count+unknown_hours_count=operation_count),
 CHECK((known_hours_count=0 AND authoritative_estimated_hours_sum IS NULL AND known_hours_sum IS NULL) OR (known_hours_count>0 AND authoritative_estimated_hours_sum IS NOT NULL AND known_hours_sum IS NOT NULL)),
 CHECK((known_hours_count=0 AND hours_coverage=0) OR (known_hours_count>0 AND hours_coverage>0))
);
ALTER TABLE public.pdc_historical_operation_hours_evidence_833 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_historical_operation_hours_evidence_833 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_historical_operation_hours_evidence_833 FROM public,anon,authenticated,service_role,pdc_email_monitor;
INSERT INTO public.pdc_historical_operation_hours_evidence_833(
 historical_receipt_id,jobcard_receipt_id,provider_uid,operation_count,legacy_estimated_hours_sum,
 authoritative_estimated_hours_sum,known_hours_sum,known_hours_count,unknown_hours_count,hours_coverage,line_values_sha256)
SELECT h.receipt_id,j.receipt_id,h.provider_uid,j.operation_count,j.estimated_hours_sum,
 CASE WHEN count(ol.estimated_hours)=0 THEN NULL ELSE sum(ol.estimated_hours) END,
 CASE WHEN count(ol.estimated_hours)=0 THEN NULL ELSE sum(ol.estimated_hours) END,
 count(ol.estimated_hours),count(*)-count(ol.estimated_hours),
 round(count(ol.estimated_hours)::numeric/nullif(j.operation_count,0),5),
 encode(extensions.digest(convert_to(jsonb_agg(jsonb_build_object('operation_no',ol.operation_no,'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source) ORDER BY ol.operation_no)::text,'UTF8'),'sha256'),'hex')
FROM public.pdc_historical_reconciliation_778_receipts h
JOIN public.pdc_jobcard_attachment_import_receipts j ON j.parent_source_hash=h.parent_source_hash AND j.operation_count=9
JOIN public.pdc_authenticated_email_operation_lines ol ON ol.source_hash=j.canonical_source_hash AND ol.source_uid=j.source_uid AND ol.vehicle_id=j.vehicle_id
WHERE h.provider_uid='1:134'
GROUP BY h.receipt_id,h.provider_uid,j.receipt_id,j.operation_count,j.estimated_hours_sum;
DO $evidence$
BEGIN
 IF (SELECT count(*) FROM public.pdc_historical_operation_hours_evidence_833 WHERE provider_uid='1:134' AND operation_count=9 AND legacy_estimated_hours_sum=0 AND authoritative_estimated_hours_sum IS NULL AND known_hours_sum IS NULL AND known_hours_count=0 AND unknown_hours_count=9 AND hours_coverage=0)<>1 THEN RAISE EXCEPTION 'PDC_833_OPERATION_HOURS_EVIDENCE_READBACK_FAILED' USING errcode='55000'; END IF;
END $evidence$;
CREATE FUNCTION public.pdc_historical_operation_hours_overlay_833(p_response jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $overlay$
DECLARE
 v_output jsonb:=p_response; v_items jsonb; v_item jsonb; v_data jsonb; v_id uuid; v_index integer; v_known_sum numeric; v_authoritative_sum numeric; v_known_count integer; v_unknown_count integer; v_coverage numeric; v_status text;
BEGIN
 IF jsonb_typeof(p_response) IS DISTINCT FROM 'object' OR jsonb_typeof(p_response->'data') IS DISTINCT FROM 'object' THEN RETURN p_response; END IF;
 v_items:=coalesce(p_response->'data'->'attachment_receipts','[]'::jsonb);
 IF jsonb_typeof(v_items) IS DISTINCT FROM 'array' THEN RETURN p_response; END IF;
 FOR v_index IN 0..jsonb_array_length(v_items)-1 LOOP
   v_item:=v_items->v_index;
   v_id:=NULLIF(v_item->'result'->'data'->>'receipt_id','')::uuid;
   SELECT authoritative_estimated_hours_sum,known_hours_sum,known_hours_count,unknown_hours_count,hours_coverage,
     CASE WHEN unknown_hours_count=0 THEN 'complete' WHEN known_hours_count=0 THEN 'all_unknown' ELSE 'partial' END
   INTO v_authoritative_sum,v_known_sum,v_known_count,v_unknown_count,v_coverage,v_status
   FROM public.pdc_historical_operation_hours_evidence_833 WHERE jobcard_receipt_id=v_id;
   IF FOUND THEN
     v_data:=coalesce(v_item->'result'->'data','{}'::jsonb)||jsonb_build_object(
       'estimated_hours_sum',v_authoritative_sum,'known_hours_sum',v_known_sum,
       'known_hours_count',v_known_count,'unknown_hours_count',v_unknown_count,
       'hours_coverage',v_coverage,'hours_knowledge_status',v_status,
       'operation_hours_evidence_source','pdc_historical_operation_hours_evidence_833');
     v_item:=jsonb_set(v_item,'{result,data}',v_data,true);
     v_items:=jsonb_set(v_items,ARRAY[v_index::text],v_item,true);
   END IF;
 END LOOP;
 RETURN jsonb_set(v_output,'{data,attachment_receipts}',v_items,true);
END
$overlay$;
REVOKE ALL ON FUNCTION public.pdc_historical_operation_hours_overlay_833(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_operation_hours_overlay_833(jsonb) TO postgres;
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
 v_before jsonb; v_after jsonb; v_result jsonb; v_readback jsonb; v_vehicle_id uuid; v_stock text; v_request_hash text; v_receipt_id uuid;
 v_before_fp jsonb; v_after_fp jsonb; v_before_counts jsonb; v_after_counts jsonb;
BEGIN
 if jsonb_typeof(coalesce(p_request,'null'::jsonb))='object' then
   p_request:=jsonb_set(p_request,'{authentication}',public.pdc_historical_authentication_canonical_806(p_request->'authentication'),true);
 end if;
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
 v_result:=public.pdc_historical_operation_hours_overlay_833(v_result);
RETURN v_result;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$function$;
REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778(jsonb) TO authenticated;
DO $post$
DECLARE v text; own text; acl text; sd boolean;
BEGIN
 SELECT p.prosrc,p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO v,own,sd,acl FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure;
 IF encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex')<>'46d36b1c75b3004933c1699bbfb744e5b0190fbf62152dfcda7cbcdb4ddd4f78' OR own<>'postgres' OR NOT sd OR acl<>'{postgres=X/postgres,authenticated=X/postgres}' OR position('pdc_historical_operation_hours_overlay_833' in v)=0 THEN RAISE EXCEPTION 'PDC_833_OPERATION_HOURS_OVERLAY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830254000','833_historical_operation_hours_correction_successor',ARRAY['preserve immutable legacy receipt and line NULL values','add authoritative all-unknown hours correction with explicit known/unknown counts and coverage','distinguish explicit numeric zero from unknown without coalescing unknown to zero','preserve replay idempotency atomic security RLS grants ten conflicts and zero mailbox containment','no historical Apply outbox mailbox task outbound or Production operation']);
COMMIT;
