-- STAGING ONLY 804: nested pre796/pre797 contained-runtime successor.
-- Public 803 preflight already uses the approved 802/672 zero-mailbox adapter,
-- but both private nested predecessors still called legacy scope_674. This
-- append-only successor replaces only those two nested preflight guards with
-- the exact authenticated contained adapter. Historical Apply, outbox,
-- mailbox, task, pilot, outbound and Production paths remain untouched.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-804-nested-pre797-contained-runtime',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v_pre796 text; v_pre797 text; v_wrapper text; v_owner text; v_secdef boolean; v_config text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR NOT public.pdc_monitor_staging_guard()
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830220000,803_contained_historical_runtime_802_successor)'
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260830220000')
 OR to_regprocedure('public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)') IS NULL
 OR to_regprocedure('public.submit_pdc_historical_reconciliation_778(jsonb)') IS NULL
 OR to_regprocedure('public.submit_pdc_historical_reconciliation_778_pre796(jsonb)') IS NULL
 OR to_regprocedure('public.submit_pdc_historical_reconciliation_778_pre797(jsonb)') IS NULL
 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_778_receipts)<>0
 OR (SELECT count(*) FROM public.pdc_historical_provider_observations_778)<>0
 OR (SELECT count(*) FROM public.pdc_historical_complete_domain_readbacks_797)<>0
 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
 OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
 OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
 OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND NOT enabled)<>1
 OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND NOT enabled AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
 THEN RAISE EXCEPTION 'PDC_804_EXACT_803_CONTAINED_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef('public.submit_pdc_historical_reconciliation_778_pre796(jsonb)'::regprocedure),pg_get_functiondef('public.submit_pdc_historical_reconciliation_778_pre797(jsonb)'::regprocedure),pg_get_functiondef('public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure) INTO v_pre796,v_pre797,v_wrapper;
 IF encode(extensions.digest(convert_to(v_pre796,'UTF8'),'sha256'),'hex')<>'08158b7512ea534702d26b70bc0450610c5f970b8a5027e36557091d9bd9dee5'
 OR encode(extensions.digest(convert_to(v_pre797,'UTF8'),'sha256'),'hex')<>'92d38d0ec984e0898332ca9d531cc202d4be9b81f174a63c921302837f4ea612'
 OR position('pdc_monitor_authenticated_active_scope_674' in v_pre796)=0
 OR position('pdc_monitor_authenticated_active_scope_674' in v_pre797)=0
 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v_pre796)>0
 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v_pre797)>0
 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v_wrapper)=0
 OR position('pdc_monitor_authenticated_active_scope_674' in v_wrapper)>0
 THEN RAISE EXCEPTION 'PDC_804_NESTED_SOURCE_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_userbyid(p.proowner),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'') INTO v_owner,v_secdef,v_config FROM pg_proc p WHERE p.oid='public.submit_pdc_historical_reconciliation_778_pre796(jsonb)'::regprocedure;
 IF v_owner IS DISTINCT FROM 'postgres' OR v_secdef IS DISTINCT FROM true OR v_config IS DISTINCT FROM 'search_path=pg_catalog, public, auth, extensions,statement_timeout=300s' OR has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778_pre796(jsonb)','execute') OR has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778_pre796(jsonb)','execute') OR has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778_pre796(jsonb)','execute') THEN RAISE EXCEPTION 'PDC_804_NESTED_SECURITY_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778_pre796(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
 v_before jsonb; v_after jsonb; v_location_before text; v_location_after text; v_result jsonb; v_canonical_request text; v_booking_created boolean:=false; v_completion_created boolean:=false; v_location_scheduled boolean:=false; v_parts_changed boolean:=false;
 v_vehicle_id uuid; v_vehicle public.vehicles%rowtype; v_existing public.pdc_historical_reconciliation_778_receipts%rowtype; v_existing_proposal public.pdc_ai_intake_proposals%rowtype; v_child_receipt public.pdc_jobcard_attachment_import_receipts%rowtype; v_request_hash text; v_uid text; v_parent text; v_sender text; v_stock text; v_source jsonb; v_items jsonb; v_auth jsonb; v_runtime jsonb; v_authz public.pdc_historical_reconciliation_writer_authorizations_773%rowtype; v_authz_count integer; v_intake public.ai_email_intake%rowtype; v_intake_id uuid; v_attachment_id uuid; v_child jsonb; v_item jsonb; v_required jsonb; v_work_key text; v_booking_count integer:=0; v_completion_count integer:=0; v_parts_count integer:=0; v_receipt_count integer:=0;
BEGIN
 IF auth.uid()='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid AND lower(btrim(coalesce(auth.jwt()->>'email','')))= 'sales@broometoyota.com.au' AND public.pdc_monitor_staging_guard() AND jsonb_typeof(p_request)='object' AND p_request->>'parent_source_hash' IS NOT NULL AND p_request->>'provider_uid' IS NOT NULL THEN
   SELECT * INTO v_existing_proposal FROM public.pdc_ai_intake_proposals WHERE source_hash=lower(p_request->>'parent_source_hash') AND source_uid=btrim(p_request->>'provider_uid') ORDER BY submitted_at DESC,proposal_id DESC LIMIT 1 FOR UPDATE;
   IF FOUND THEN
     IF v_existing_proposal.status::text<>'pending' THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_terminal_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'status',v_existing_proposal.status,'review_required',true)); END IF;
     IF v_existing_proposal.evidence_hash IS DISTINCT FROM lower(p_request->>'evidence_hash') OR lower(v_existing_proposal.sender_address) IS DISTINCT FROM lower(p_request->>'sender_email') OR v_existing_proposal.authentication IS DISTINCT FROM coalesce(p_request->'authentication','null'::jsonb) OR public.normalize_vehicle_stock_number(v_existing_proposal.stock_number) IS DISTINCT FROM public.normalize_vehicle_stock_number(p_request->>'stock_number') THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_tuple_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'review_required',true,'source_tuple_conflict',true)); END IF;
     IF v_existing_proposal.subject IS DISTINCT FROM p_request->>'subject' OR v_existing_proposal.action_type IS DISTINCT FROM p_request->>'action_type' OR v_existing_proposal.summary IS DISTINCT FROM p_request->>'summary' THEN RETURN jsonb_build_object('ok',false,'code','historical_proposal_payload_conflict','data',jsonb_build_object('proposal_id',v_existing_proposal.proposal_id,'review_required',true,'payload_conflict',true)); END IF;
   END IF;
 END IF;
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au' OR COALESCE(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true' OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_request) k) IS DISTINCT FROM ARRAY['action_type','attachment_manifest','authentication','canonical_request_utf8','evidence_hash','gateway_instance_id','job_card_children','manifest_high_water_uid','manifest_sha256','manifest_uid_count','manifest_uidvalidity','observations','parent_source_hash','provider_uid','release_manifest_sha256','release_name','release_source_sha','sender_email','source_metadata','stock_number','subject','summary']::text[] THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 v_uid:=btrim(coalesce(p_request->>'provider_uid','')); v_parent:=lower(btrim(coalesce(p_request->>'parent_source_hash',''))); v_sender:=lower(btrim(coalesce(p_request->>'sender_email',''))); v_stock:=public.normalize_vehicle_stock_number(p_request->>'stock_number'); v_source:=coalesce(p_request->'source_metadata','null'::jsonb); v_items:=coalesce(p_request->'attachment_manifest','null'::jsonb); v_auth:=coalesce(p_request->'authentication','null'::jsonb);
 IF p_request->>'gateway_instance_id' IS DISTINCT FROM 'pdc-monitor-staging-sales-uid509-v1' OR p_request->>'release_name' IS DISTINCT FROM 'pdc-monitor-staging-m502-2026.08.44' OR lower(p_request->>'release_source_sha') IS DISTINCT FROM 'e850c319989d98b45b95a28aa815d78e2c2e3a4b' OR lower(p_request->>'release_manifest_sha256') IS DISTINCT FROM 'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' OR p_request->>'manifest_sha256' IS DISTINCT FROM 'aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018' OR p_request->>'manifest_uidvalidity' IS DISTINCT FROM '1' OR p_request->>'manifest_high_water_uid' IS DISTINCT FROM '685' OR p_request->>'manifest_uid_count' IS DISTINCT FROM '669' OR v_request_hash!~'^[a-f0-9]{64}$' OR v_uid!~'^1:[1-9][0-9]{0,5}$' OR v_uid='1:197' OR v_parent!~'^[a-f0-9]{64}$' OR v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$' OR v_stock='13056899' OR NOT public.is_real_vehicle_stock_number(v_stock) OR p_request->>'evidence_hash'!~'^[a-f0-9]{64}$' OR p_request->>'action_type' NOT IN ('board_activate_only','review_only') OR jsonb_typeof(v_auth) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth) k) IS DISTINCT FROM ARRAY['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[] OR v_auth->>'sender_domain' IS DISTINCT FROM split_part(v_sender,'@',2) OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb) OR jsonb_typeof(v_items) IS DISTINCT FROM 'array' OR jsonb_array_length(v_items) NOT BETWEEN 1 AND 25 OR jsonb_typeof(p_request->'job_card_children') IS DISTINCT FROM 'array' OR jsonb_array_length(p_request->'job_card_children')>25 OR jsonb_typeof(v_source) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_source) k) IS DISTINCT FROM ARRAY['attachment_names','graph_message_id','internet_message_id','parsed_text','provider_authserv_id','raw_body','received_at','recipient_mailbox','sender_name','uid','uidvalidity']::text[] OR v_source->>'uidvalidity' IS DISTINCT FROM '1' OR v_source->>'uid' IS DISTINCT FROM substring(v_uid FROM '^1:([0-9]+)$') OR v_source->>'provider_authserv_id' IS DISTINCT FROM 'mx.google.com' OR lower(v_source->>'recipient_mailbox') IS DISTINCT FROM 'pmbcontroller@gmail.com' OR v_source->>'received_at' IS NULL OR (v_source->>'received_at')::timestamptz > clock_timestamp()+interval '5 minutes' OR (v_source->>'received_at')::timestamptz < clock_timestamp()-interval '120 days' OR v_source->'attachment_names' IS DISTINCT FROM (SELECT jsonb_agg(m->>'filename' ORDER BY ordinality) FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality)) THEN RETURN jsonb_build_object('ok',false,'code','historical_wrapper_preflight_failed'); END IF;
 v_runtime:=public.verify_pdc_monitor_runtime_binding_authenticated_766('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227');
 IF v_runtime->>'ok' IS DISTINCT FROM 'true' OR v_runtime->>'actor_id' IS DISTINCT FROM auth.uid()::text OR v_runtime->>'actor_email' IS DISTINCT FROM lower(auth.jwt()->>'email') OR v_runtime->>'task_enabled' IS DISTINCT FROM 'false' OR v_runtime->>'mailbox_contacted' IS DISTINCT FROM 'false' OR v_runtime->>'production_writes' IS DISTINCT FROM 'false' THEN RETURN jsonb_build_object('ok',false,'code','historical_wrapper_preflight_failed'); END IF;
v_canonical_request:=public.pdc_historical_canonical_request_788(p_request,auth.uid(),lower(auth.jwt()->>'email'),v_runtime);
IF p_request->>'canonical_request_utf8' IS DISTINCT FROM v_canonical_request THEN RETURN jsonb_build_object('ok',false,'code','historical_canonical_request_mismatch'); END IF;
v_request_hash:=encode(extensions.digest(convert_to(v_canonical_request,'UTF8'),'sha256'),'hex');
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_items) WITH ORDINALITY x(m,ordinality) WHERE jsonb_typeof(x.m) IS DISTINCT FROM 'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x.m) k) IS DISTINCT FROM ARRAY['attachment_kind','content_type','filename','ordinal','sha256','size']::text[] OR x.m->>'attachment_kind' NOT IN ('job_card','ambiguous_job_card','non_job_card_sibling') OR x.m->>'sha256'!~'^[a-f0-9]{64}$' OR x.m->>'ordinal'!~'^[1-9][0-9]{0,2}$' OR (x.m->>'ordinal')::integer<>x.ordinality OR x.m->>'size'!~'^[1-9][0-9]{0,7}$' OR x.m->>'content_type' IS NULL OR x.m->>'filename' IS NULL) THEN RETURN jsonb_build_object('ok',false,'code','historical_wrapper_preflight_failed'); END IF;
 SELECT count(*) INTO v_authz_count FROM public.pdc_historical_reconciliation_writer_authorizations_773 e WHERE e.active AND e.manifest_sha256=p_request->>'manifest_sha256' AND e.provider_uid=v_uid AND e.parent_source_hash=v_parent AND e.sender_email=v_sender AND e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex') AND e.provider_authentication IS NOT DISTINCT FROM v_auth AND public.normalize_vehicle_stock_number(e.stock_number)=v_stock AND e.authorized_actor_id=auth.uid() AND e.authorized_actor_email=lower(auth.jwt()->>'email') AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND public.pdc_historical_writer_authorized_773(v_parent,v_uid,v_sender,v_auth,v_stock);
 IF v_authz_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','pdc_778_exact_authorization_failed'); END IF;
 SELECT * INTO v_authz FROM public.pdc_historical_reconciliation_writer_authorizations_773 e WHERE e.active AND e.manifest_sha256=p_request->>'manifest_sha256' AND e.provider_uid=v_uid AND e.parent_source_hash=v_parent AND e.sender_email=v_sender AND e.authorized_actor_id=auth.uid() AND e.authorized_actor_email=lower(auth.jwt()->>'email') AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1';
 SELECT * INTO v_existing FROM public.pdc_historical_reconciliation_778_receipts WHERE actor_id=auth.uid() AND provider_uid=v_uid AND parent_source_hash=v_parent;
 IF FOUND THEN IF v_existing.request_sha256<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','historical_replay_conflict'); END IF; RETURN v_existing.canonical_response; END IF;
 SELECT * INTO v_intake FROM public.ai_email_intake WHERE source_hash=v_parent ORDER BY created_at DESC LIMIT 1;
 IF FOUND AND (v_intake.duplicate_of IS NOT NULL OR v_intake.status::text NOT IN ('received','processing') OR v_intake.received_at IS NULL OR v_intake.received_at>clock_timestamp()+interval '5 minutes' OR v_intake.received_at<clock_timestamp()-interval '120 days') THEN RETURN jsonb_build_object('ok',false,'code','pdc_782_old_mail_completed'); END IF;
 IF clock_timestamp()>v_authz.authorized_at+interval '24 hours' THEN RETURN jsonb_build_object('ok',false,'code','historical_authorization_expired'); END IF;
 v_before:=public.pdc_historical_782_boundary_snapshot();
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY to_jsonb(x)::text) FROM public.vehicle_movements x),'')||'|'||coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY to_jsonb(x)::text) FROM public.vehicle_aliases x),'')) INTO v_location_before;
 v_result:=public.submit_pdc_historical_reconciliation_793_proposal_review_succes(p_request);
 v_after:=public.pdc_historical_782_boundary_snapshot();
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY to_jsonb(x)::text) FROM public.vehicle_movements x),'')||'|'||coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY to_jsonb(x)::text) FROM public.vehicle_aliases x),'')) INTO v_location_after;
 v_booking_created:=v_after->>'workshop_bookings' IS DISTINCT FROM v_before->>'workshop_bookings' OR v_after->>'workshop_booking_assignments' IS DISTINCT FROM v_before->>'workshop_booking_assignments';
 v_completion_created:=v_after->>'pdc_qc_operation_completions_379' IS DISTINCT FROM v_before->>'pdc_qc_operation_completions_379';
 v_location_scheduled:=v_booking_created;
 v_parts_changed:=v_after->>'vehicle_parts_updates' IS DISTINCT FROM v_before->>'vehicle_parts_updates';
 v_location_scheduled:=v_location_scheduled OR v_location_after IS DISTINCT FROM v_location_before;
 IF v_booking_created OR v_completion_created OR v_location_scheduled OR v_parts_changed THEN RAISE EXCEPTION 'PDC_782_1740_PROTECTED_BOUNDARY_DRIFT' USING errcode='55000'; END IF;
IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'PDC_788_PROTECTED_BOUNDARY_DRIFT' USING errcode='55000'; END IF;
 IF v_result->>'ok'='true' THEN
   IF v_result->'data'->>'booking_created' IS DISTINCT FROM v_booking_created::text OR v_result->'data'->>'completion_created' IS DISTINCT FROM v_completion_created::text OR v_result->'data'->>'location_scheduled' IS DISTINCT FROM v_location_scheduled::text OR v_result->'data'->>'parts_changed' IS DISTINCT FROM v_parts_changed::text THEN RAISE EXCEPTION 'PDC_782_1740_FLAG_READBACK_FAILED' USING errcode='55000'; END IF;
   IF jsonb_typeof(v_result->'data'->'authoritative_state') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'PDC_782_1740_AUTHORITATIVE_STATE_MISSING' USING errcode='55000'; END IF;
   IF v_result->'data'->'authoritative_state'->>'vehicle_id' IS NOT NULL THEN
     IF v_result->'data'->'authoritative_state'->>'vehicle_id' !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' THEN RAISE EXCEPTION 'PDC_782_1740_VEHICLE_ID_READBACK_FAILED' USING errcode='55000'; END IF;
     v_vehicle_id:=(v_result->'data'->'authoritative_state'->>'vehicle_id')::uuid;
     SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_vehicle_id;
     IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active' OR v_vehicle.board_purged_at IS NOT NULL OR NOT coalesce(v_vehicle.visible_on_board,false) THEN RAISE EXCEPTION 'PDC_782_1740_AUTHORITATIVE_VEHICLE_FAILED' USING errcode='55000'; END IF;
     select count(*) into v_booking_count from public.workshop_bookings where vehicle_id=v_vehicle_id;
     select count(*) into v_completion_count from public.pdc_qc_operation_completions_379 where vehicle_id=v_vehicle_id;
     select count(*) into v_parts_count from public.vehicle_parts_updates where vehicle_id=v_vehicle_id;
     IF v_booking_count<>0 OR v_completion_count<>0 OR v_parts_count<>0 THEN RAISE EXCEPTION 'PDC_782_1740_AUTHORITATIVE_PROTECTED_STATE_FAILED' USING errcode='55000'; END IF;
     FOR v_child IN SELECT value FROM jsonb_array_elements(p_request->'job_card_children') LOOP
       IF v_child->>'attachment_kind'='job_card' THEN
         v_intake_id:=NULLIF(v_result->'data'->>'intake_id','')::uuid;
         SELECT count(*) INTO v_receipt_count FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=p_request->>'provider_uid'||':historical-782-'||lpad((v_child->>'attachment_ordinal')::integer::text,3,'0')||'-'||lower(v_child->>'attachment_hash') AND lower(a.source_hash)=lower(v_child->>'attachment_hash');
         IF v_receipt_count<>1 THEN RAISE EXCEPTION 'PDC_782_1740_CHILD_ATTACHMENT_READBACK_FAILED' USING errcode='55000'; END IF;
         SELECT a.id INTO v_attachment_id FROM public.ai_email_attachments a WHERE a.intake_id=v_intake_id AND a.graph_attachment_id=p_request->>'provider_uid'||':historical-782-'||lpad((v_child->>'attachment_ordinal')::integer::text,3,'0')||'-'||lower(v_child->>'attachment_hash');
         SELECT count(*) INTO v_receipt_count FROM public.pdc_jobcard_attachment_import_receipts r WHERE r.intake_id=v_intake_id AND r.attachment_id=v_attachment_id AND r.parent_source_hash=p_request->>'parent_source_hash' AND r.attachment_source_hash=lower(v_child->>'attachment_hash') AND r.attachment_content_type='application/pdf' AND r.job_card_number= v_child->'extraction'->'email_vehicle'->>'job_card_number' AND r.operation_count=jsonb_array_length(v_child->'extraction'->'operation_lines') AND r.canonical_import_receipt_id IS NOT NULL AND r.vehicle_id IS NOT NULL;
         IF v_receipt_count<>1 THEN RAISE EXCEPTION 'PDC_782_1740_CHILD_RECEIPT_READBACK_FAILED' USING errcode='55000'; END IF;
         v_vehicle_id:=NULLIF((SELECT r->>'authoritative_vehicle_id' FROM jsonb_array_elements(v_result->'data'->'attachment_receipts') r WHERE r->>'attachment_hash'=v_child->>'attachment_hash' LIMIT 1),'')::uuid;
         v_required:=coalesce(v_child->'extraction'->'required_work','[]'::jsonb);
         IF v_vehicle_id IS NULL OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_required) k WHERE NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v_vehicle_id AND wi.work_key=k AND wi.required)) THEN RAISE EXCEPTION 'PDC_782_1740_AUTHORITATIVE_WORK_FAILED' USING errcode='55000'; END IF;
       END IF;
     END LOOP;
   END IF;
 END IF;
 RETURN v_result;
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('ok',false,'code','historical_reconciliation_782_atomic_rollback');
END
$function$;

REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre796(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre796(jsonb) TO postgres;
CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778_pre797(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
 v_before jsonb; v_after jsonb; v_result jsonb; v_readback jsonb; v_vehicle public.vehicles%rowtype; v_vehicle_id uuid; v_receipt_id uuid; v_request_hash text; v_existing_request_hash text;
 v_stock text; v_match_count integer:=0; v_had_vehicle boolean:=false; v_replay boolean:=false; v_replay_vehicle_id uuid; v_location text; v_lifecycle text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    OR COALESCE(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true'
 THEN RETURN jsonb_build_object('ok',false,'code','unauthorized'); END IF;
 v_stock:=public.normalize_vehicle_stock_number(p_request->>'stock_number');
 IF jsonb_typeof(p_request)='object' THEN
   SELECT r.request_sha256 INTO v_existing_request_hash FROM public.pdc_historical_reconciliation_778_receipts r WHERE r.actor_id=auth.uid() AND r.provider_uid=btrim(coalesce(p_request->>'provider_uid','')) AND r.parent_source_hash=lower(btrim(coalesce(p_request->>'parent_source_hash','')));
   IF v_existing_request_hash IS NOT NULL AND encode(extensions.digest(convert_to(coalesce(p_request->>'canonical_request_utf8',''),'UTF8'),'sha256'),'hex')=v_existing_request_hash THEN v_replay:=true; END IF;
 END IF;
 IF v_replay AND v_stock IS NOT NULL AND v_stock<>'' THEN
   SELECT count(*) INTO v_match_count FROM public.vehicles v WHERE v.stock_number_normalized=v_stock;
   IF v_match_count>1 THEN RETURN jsonb_build_object('ok',false,'code','PDC_796_REPLAY_IDENTITY_CONFLICT'); END IF;
   IF v_match_count=1 THEN SELECT v.id INTO v_replay_vehicle_id FROM public.vehicles v WHERE v.stock_number_normalized=v_stock ORDER BY v.id LIMIT 1; END IF;
 END IF;
 IF NOT v_replay AND jsonb_typeof(p_request)='object' AND v_stock IS NOT NULL AND v_stock<>'' THEN
   SELECT count(*) INTO v_match_count FROM public.vehicles v WHERE v.stock_number_normalized=v_stock;
   IF v_match_count>1 THEN RETURN jsonb_build_object('ok',false,'code','PDC_796_IDENTITY_CONFLICT'); END IF;
   SELECT * INTO v_vehicle FROM public.vehicles v WHERE v.stock_number_normalized=v_stock ORDER BY (v.deleted_at IS NULL) DESC,v.id LIMIT 1 FOR UPDATE;
   IF FOUND THEN
     v_had_vehicle:=true; v_vehicle_id:=v_vehicle.id; v_location:=lower(regexp_replace(btrim(coalesce(v_vehicle.current_location,'')),'\s+',' ','g')); v_lifecycle:=v_vehicle.lifecycle_state::text;
     IF v_lifecycle IN ('rft','completed','deleted','tombstoned') OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.board_purged_at IS NOT NULL
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
   IF v_replay AND v_stock IS NOT NULL AND v_stock<>'' THEN
     IF v_replay_vehicle_id IS NOT NULL AND v_vehicle_id IS NOT NULL AND v_replay_vehicle_id IS DISTINCT FROM v_vehicle_id THEN RAISE EXCEPTION 'PDC_796_REPLAY_VEHICLE_ID_MISMATCH' USING errcode='55000'; END IF;
     IF v_vehicle_id IS NULL THEN v_vehicle_id:=v_replay_vehicle_id; v_after:=public.pdc_historical_796_domain_snapshot(v_vehicle_id); END IF;
     IF v_vehicle_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND v.stock_number_normalized=v_stock) THEN RAISE EXCEPTION 'PDC_796_REPLAY_VEHICLE_READBACK_FAILED' USING errcode='55000'; END IF;
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
$function$;

REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre797(jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre797(jsonb) TO postgres;
DO $post$
DECLARE v_pre796 text; v_pre797 text; v_wrapper text;
BEGIN
 SELECT pg_get_functiondef('public.submit_pdc_historical_reconciliation_778_pre796(jsonb)'::regprocedure),pg_get_functiondef('public.submit_pdc_historical_reconciliation_778_pre797(jsonb)'::regprocedure),pg_get_functiondef('public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure) INTO v_pre796,v_pre797,v_wrapper;
 IF encode(extensions.digest(convert_to(v_pre796,'UTF8'),'sha256'),'hex')<>'333280ab2dfb4f8ce74daa76b29ff3124fe76ee4eb16e116aab0ac3786c6efc9'
 OR encode(extensions.digest(convert_to(v_pre797,'UTF8'),'sha256'),'hex')<>'a9b8ab309c613b6467657dd32d9d15630ca6447f40c549158f2870f151094d19'
 OR position('pdc_monitor_authenticated_active_scope_674' in v_pre796)>0
 OR position('pdc_monitor_authenticated_active_scope_674' in v_pre797)>0
 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v_pre796)=0
 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v_pre797)=0
 OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v_wrapper)=0
 OR position('pdc_monitor_authenticated_active_scope_674' in v_wrapper)>0
 OR NOT has_function_privilege('authenticated','public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)','execute')
 OR has_function_privilege('anon','public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)','execute')
 OR has_function_privilege('service_role','public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text)','execute')
 OR has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778_pre796(jsonb)','execute')
 OR has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778_pre797(jsonb)','execute')
 OR NOT has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
 OR has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
 OR has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_804_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830221000','804_nested_pre797_contained_runtime_802_successor',ARRAY[
 'Bind private pre796 and pre797 historical preflight to the exact authenticated 802/672 zero-mailbox containment adapter',
 'Preserve nested identity, source, attachment, digest, evidence, receipt, replay, RLS, grant, task, outbound and Production fail-closed boundaries',
 'Leave normal 766 runtime and the public 803 adapter contract unchanged'
]);
NOTIFY pgrST,'reload schema';
COMMIT;
